#!/usr/bin/env node
// 予測機能のベンチマーク。変換精度とは別の軸で、「打たずに済んだか」を測る。
//
// 何を正解とするか
// ----------------
// アプリ上でユーザーが確定していく単位は、このエンジン自身の分割そのもの
// (KeyboardController は segment() の各セグメントを順に確定する)。なので
// 盲検コーパスの読みを segment() にかけ、各セグメントとその確定表記を
// 「ユーザーが順に打った語の列」とみなす。変換精度の評価ではこれは循環に
// なるが、予測の評価では循環しない -- 問いが「直前まで確定した内容から
// 次を当てられるか」だからで、その直前までの内容は実機でもこの分割で決まる。
//
// 測る軸は2つ:
//
//   次単語予測  words[0..i-1] を与えて words[i] が候補に入るか (hit@1/3/5)
//   前方一致補完 words[i] の読みを k 文字打った時点で表記が候補に入るか
//                -> 「何文字打たずに済んだか」= 節約打鍵率
//
// 学習ゼロ (cold) と、コーパス前半で学習させた状態 (warm) の両方を出す。
// NextWordPredictor は使うほど当たる設計なので、cold だけでは実力を
// 過小評価する。
//
//   bun tools/ime-eval/run_prediction.js
//   bun tools/ime-eval/run_prediction.js --misses   # 外した例も出す

const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..', '..');
const RAW = path.join(ROOT, 'entry/src/main/resources/rawfile');
const CORPUS = path.join(ROOT, 'tools/blind-eval/blind_corpus.json');

function load(name) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pred-'));
  const p = path.join(tmp, name + '.ts');
  fs.writeFileSync(p, '// @ts-nocheck\n' +
    fs.readFileSync(path.join(ROOT, 'entry/src/main/ets/ime', name + '.ets'), 'utf-8'));
  return require(p);
}

const { KanaKanjiConverter } = load('KanaKanjiConverter');
const { NextWordPredictor } = load('NextWordPredictor');
const { PredictiveConversion } = load('PredictiveConversion');

// 実機と同じパック辞書で駆動する。前方一致補完は整列済みの表を二分探索する
// 実装なので、Record 版 (走査) とは速度も並びも違う -- 測るなら実機と同じ側。
const u8 = (n) => new Uint8Array(fs.readFileSync(path.join(RAW, n)));
const u32 = (n) => {
  const b = fs.readFileSync(path.join(RAW, n));
  return new Uint32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));
};
const packArgs = (name) => [u8(name + '.keys.blob'), u8(name + '.keys.len'), u32(name + '.keys.base'),
  u8(name + '.vals.blob'), u8(name + '.vals.len'), u32(name + '.vals.base'), u32(name + '.idx.bin')];
KanaKanjiConverter.loadDictionaryPacked(...packArgs('dict'));
KanaKanjiConverter.setGlobalDictPacked(...packArgs('global_dict'));
KanaKanjiConverter.initConnectionMatrix();
const { loadMozcArgs } = require('../mozc_data/load_mozc');
KanaKanjiConverter.loadMozcEngine(...loadMozcArgs(RAW));

const pairs = JSON.parse(fs.readFileSync(CORPUS, 'utf-8'));
const showMisses = process.argv.includes('--misses');

// 読み -> [{reading, surface}]。lookup() は直前の segment() のヒントを見るので
// 必ずその場で引く。
function words(conv, reading) {
  const segs = conv.segment(reading);
  return segs.map((s) => ({ reading: s, surface: conv.lookup(s)[0] }));
}

function measure(engine, trainRatio) {
  KanaKanjiConverter.setEngine(engine);
  const conv = new KanaKanjiConverter();
  const seqs = pairs.map(([r]) => words(conv, r)).filter((w) => w.length >= 2);

  const cut = Math.floor(seqs.length * trainRatio);
  NextWordPredictor.setLearned({});
  KanaKanjiConverter.setLearned({});
  for (let i = 0; i < cut; i++) {
    const w = seqs[i];
    for (let j = 0; j < w.length; j++) {
      NextWordPredictor.record(j >= 2 ? w[j - 2].surface : '', j >= 1 ? w[j - 1].surface : '', w[j].surface);
      KanaKanjiConverter.recordChoice(w[j].reading, w[j].surface);
    }
  }
  const learned = KanaKanjiConverter.getLearned();

  let nTries = 0;
  const hit = [0, 0, 0];          // @1 @3 @5
  let kanaTotal = 0;
  let kanaSaved = 0;
  const missed = [];

  for (let i = cut; i < seqs.length; i++) {
    const w = seqs[i];
    for (let j = 1; j < w.length; j++) {
      const got = NextWordPredictor.predict(w[j - 1].surface, j >= 2 ? w[j - 2].surface : undefined) || [];
      const at = got.indexOf(w[j].surface);
      nTries++;
      if (at === 0) hit[0]++;
      if (at >= 0 && at < 3) hit[1]++;
      if (at >= 0 && at < 5) hit[2]++;
      else if (showMisses && missed.length < 20) {
        missed.push(`${w[j - 1].surface} -> ${w[j].surface}   予測: ${got.slice(0, 5).join(' ')}`);
      }
    }
    // 前方一致補完: 各語の読みを1文字ずつ打っていき、表記が出た時点で確定できる
    for (const x of w) {
      kanaTotal += x.reading.length;
      let firstHit = x.reading.length;      // 出なければ全部打つ
      for (let k = 1; k < x.reading.length; k++) {
        const pfx = x.reading.slice(0, k);
        const cands = PredictiveConversion.predict(pfx, learned,
          KanaKanjiConverter.prefixCompletions(pfx, 8)) || [];
        if (cands.indexOf(x.surface) >= 0) { firstHit = k; break; }
      }
      kanaSaved += x.reading.length - firstHit;
    }
  }

  const pct = (a, b) => (100 * a / b).toFixed(1) + '%';
  console.log(`[${engine}] 学習 ${Math.round(trainRatio * 100)}% / 評価 ${seqs.length - cut} 文`);
  console.log(`  次単語予測  hit@1 ${pct(hit[0], nTries)}  hit@3 ${pct(hit[1], nTries)}  hit@5 ${pct(hit[2], nTries)}   (${nTries} 回)`);
  console.log(`  前方一致補完 節約打鍵 ${pct(kanaSaved, kanaTotal)}  (${kanaSaved}/${kanaTotal} かな)`);
  if (showMisses && missed.length) {
    console.log('  --- 外した例 ---');
    for (const m of missed) console.log('    ' + m);
  }
}

for (const engine of ['custom', 'mozc']) {
  measure(engine, 0);      // cold start
  measure(engine, 0.5);    // 半分で学習してから
}
