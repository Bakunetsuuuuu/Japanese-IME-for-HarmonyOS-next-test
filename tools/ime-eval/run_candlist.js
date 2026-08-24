#!/usr/bin/env node
// 候補リストの質を測る。候補[0]の完全一致ではなく「正解が何番目に出るか」。
//
// なぜこの軸か
// ------------
// 実機で見えているのは候補の並びで、2番目3番目を選ぶのは1タップ。正解が
// 常に上位に見えているIMEは、1番目が外れても実用上は強い。逆に、正解が
// リストに1つも無ければユーザーには打ち直す以外の手が無い。
// 分割を固定した上限の測定 (tools/ime-eval の run_prediction とは別) では、
// 各セグメント上位3から選べれば81.7%に届く一方、実際の出力は57%台だった。
// つまり「並びの中には居るのに1番目に来ていない」が主な失敗の形。
//
// 何を候補とするか
// ----------------
// KeyboardController が候補欄に出すものと同じ手順を踏む (updateCandidates の
// 分岐: 単一セグメントなら lookup(全体)、複数セグメントなら全体 lookup が
// 実ヒットならそれ、でなければ 前方は autoConvert + 末尾セグメントの候補)。
//
//   bun tools/ime-eval/run_candlist.js
//   bun tools/ime-eval/run_candlist.js --misses   # リストに無い文を出す
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..', '..');
const RAW = path.join(ROOT, 'entry/src/main/resources/rawfile');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cand-'));
const ts = path.join(tmp, 'KKC.ts');
fs.writeFileSync(ts, '// @ts-nocheck\n' +
  fs.readFileSync(path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets'), 'utf-8'));
const { KanaKanjiConverter } = require(ts);

const u8 = (n) => new Uint8Array(fs.readFileSync(path.join(RAW, n)));
const u32 = (n) => {
  const b = fs.readFileSync(path.join(RAW, n));
  return new Uint32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));
};
const pa = (n) => [u8(n + '.keys.blob'), u8(n + '.keys.len'), u32(n + '.keys.base'),
  u8(n + '.vals.blob'), u8(n + '.vals.len'), u32(n + '.vals.base'), u32(n + '.idx.bin')];
KanaKanjiConverter.loadDictionaryPacked(...pa('dict'));
KanaKanjiConverter.setGlobalDictPacked(...pa('global_dict'));
KanaKanjiConverter.initConnectionMatrix();
const { loadMozcArgs } = require('../mozc_data/load_mozc');
KanaKanjiConverter.loadMozcEngine(...loadMozcArgs(RAW));

const pairs = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/blind-eval/blind_corpus.json'), 'utf-8'));
const showMisses = process.argv.includes('--misses');

// KeyboardController.updateCandidates と同じ組み立て。
function candidates(conv, target) {
  const fullKatakana = KanaKanjiConverter.toKatakana(target);
  const segs = conv.segment(target);
  if (segs.length <= 1) { return conv.lookup(target); }
  const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
  const hasSymbolPrefix = prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p));
  const fullCands = conv.lookup(target);
  const fullFirst = fullCands[0];
  const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== target)
    || KanaKanjiConverter.isDictionaryWord(target);
  if (hasRealHit) { return fullCands; }
  if (hasSymbolPrefix) { return [target]; }
  const prefixText = prefixParts.join('');
  return conv.lookup(segs[segs.length - 1]).map((x) => prefixText + x);
}

for (const engine of ['custom', 'mozc', 'hybrid']) {
  KanaKanjiConverter.setEngine(engine);
  const conv = new KanaKanjiConverter();
  const ranks = [];
  const missing = [];
  let lenSum = 0;
  for (const [r, g] of pairs) {
    const list = candidates(conv, r) || [];
    lenSum += list.length;
    const at = list.indexOf(g);
    ranks.push(at);
    if (at < 0 && missing.length < 15) { missing.push(`${g}\n     候補: ${list.slice(0, 5).join(' / ')}`); }
  }
  const n = pairs.length;
  const upto = (k) => ranks.filter((x) => x >= 0 && x < k).length;
  const pct = (a) => `${a}/${n} (${(100 * a / n).toFixed(1)}%)`;
  console.log(`[${engine}]  候補数 平均 ${(lenSum / n).toFixed(1)}`);
  for (const k of [1, 2, 3, 5, 10, 20]) { console.log(`  正解が上位${String(k).padStart(2)}以内 : ${pct(upto(k))}`); }
  console.log(`  リストに無い          : ${pct(ranks.filter((x) => x < 0).length)}`);
  if (showMisses) { for (const m of missing) { console.log('   ' + m); } }
}
