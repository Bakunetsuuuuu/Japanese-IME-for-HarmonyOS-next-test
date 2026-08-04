#!/usr/bin/env node
// 同音異義語の選択だけを採点するテスト。
//
// run_real.js の「文全体が一致したか」は、この段階ではもう鈍い指標になっている。
// 残る差の大半は 事/こと・時/とき のような書き手の表記の好みで、それが両方向に
// 出るため、同音語の選択を1つ直しても全体の％はほとんど動かない。逆に表記の
// 好みに引きずられて％を上げようとすると、変換の質はむしろ下がる。
//
// そこでこのスクリプトは、判定の単位を「文」から「1回の同音語選択」に落とす。
//
//   1. 実文コーパスのトークン整列から、読み→表記の出現を全部数える
//   2. 漢字を含む表記が2種類以上、それぞれ MIN_OCCUR 回以上出ている読みを
//      「実際に迷う同音語」として抽出する(辞書に何十個候補があっても、実文で
//      1種類しか使われない読みは迷いようがないので対象外)
//   3. その読みを含む文を変換し、その位置に gold の表記が出たかだけを見る
//
// 表記の好みは対象外になる(かな表記のみの語は 2. で落ちる)ので、点数がそのまま
// 「文脈から正しい同音語を選べた割合」になる。--rank で読みごとの内訳が出るので、
// 直すべき対象がそのまま並ぶ。
//
// Usage:
//   node tools/ime-eval/run_homophone.js           全体の正解率
//   node tools/ime-eval/run_homophone.js --rank    読みごとの誤り内訳(多い順)
//   node tools/ime-eval/run_homophone.js --reading きく   特定の読みの実例
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const CORPUS = path.join(__dirname, 'cache_real', 'real_corpus.json');

// 実文で何回出ていれば「実際に使われる表記」とみなすか。1回だけの表記は
// 誤記や特殊な用法のことがあり、それを gold にすると直しようがない。
const MIN_OCCUR = 3;

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imehomo-'));
  const ts = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(ts, '// @ts-nocheck\n' +
    fs.readFileSync(path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets'), 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', ts], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  if (!fs.existsSync(CORPUS)) {
    console.error('missing ' + path.relative(ROOT, CORPUS));
    console.error('run: node tools/ime-eval/fetch_real_corpus.js && node tools/ime-eval/build_real_corpus.js');
    process.exit(1);
  }
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/dict_src/dict.json'), 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/dict_src/global_dict.json'), 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  const convert = (reading) => {
    const fullKata = KanaKanjiConverter.toKatakana(reading);
    const segs = conv.segment(reading);
    if (segs.length <= 1) { return conv.lookup(reading)[0]; }
    const full = conv.lookup(reading);
    if ((full[0] !== fullKata && full[0] !== reading) || KanaKanjiConverter.isDictionaryWord(reading)) { return full[0]; }
    const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
    if (prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p))) { return reading; }
    return prefixParts.join('') + conv.lookup(segs[segs.length - 1])[0];
  };

  const data = JSON.parse(fs.readFileSync(CORPUS, 'utf-8'));
  const hasKanji = (s) => /[一-鿿]/.test(s);

  // 1. 読み -> 表記の出現数
  const usage = new Map();
  for (const row of data) {
    for (const [r, w] of (row[2] || [])) {
      if (r.length < 2 || !hasKanji(w)) { continue; }
      let m = usage.get(r);
      if (!m) { m = new Map(); usage.set(r, m); }
      m.set(w, (m.get(w) || 0) + 1);
    }
  }
  // 2. 実際に迷う読み = 漢字表記が2種類以上、それぞれ MIN_OCCUR 回以上
  const ambiguous = new Map();
  for (const [r, m] of usage) {
    const kept = [...m.entries()].filter(([, n]) => n >= MIN_OCCUR);
    if (kept.length >= 2) { ambiguous.set(r, new Map(kept)); }
  }

  // 3. 該当トークンごとに採点。
  //
  // ここで文の他の部分まで巻き込まないことが重要。同音語トークンを含む文を
  // 単純に「gold と一致したか」で採点すると、分割が崩れて文全体が壊れている
  // 例(「潜水士て泳げる甲斐」「野手はボールを鳥そこ寝た」)まで同音語の誤りとして
  // 数えてしまい、上位が"文が壊れている読み"で埋まって直す対象を見誤る。
  //
  // そこで採点するのは「差分が同音語トークン1箇所だけの文」に限る。gold と got の
  // 共通接頭辞・接尾辞を剥がして残った差が、ちょうどその語の gold 表記であれば
  // 同音語の選択ミス。それ以外の場所が違っていれば、それは別の原因なので対象外。
  //
  // 誤りは更に3種類に分かれ、直す価値が全く違うので分けて数える。
  //   漢字→漢字 (神←髪, 航海←後悔)  … 本当の同音異義語の選択ミス。これが本題。
  //   かな→漢字 (かい←甲斐)          … 過剰変換。終助詞の かい を 甲斐 にする等、
  //                                     語の選択としても誤りなので直す価値がある。
  //   漢字→かな (物←もの, 後←あと)   … 書き手の表記の好み。同じ語なので誤りでない。
  // 3つ目を混ぜていた頃は もの/あと/とし が上位を占めて、直す対象を見誤った。
  let total = 0, correct = 0, skipped = 0, over = 0, styleOnly = 0;
  const perReading = new Map();
  for (const [reading, gold, tokens] of data) {
    if (!tokens) { continue; }
    const amb = tokens.filter(([r]) => ambiguous.has(r));
    if (amb.length !== 1) { continue; }   // 2つ以上あると差分の帰属が決まらない
    const [r, w] = amb[0];
    const got = convert(reading);
    let s = perReading.get(r);
    if (!s) { s = { ok: 0, ng: 0, examples: [] }; perReading.set(r, s); }
    if (got === gold) { total++; correct++; s.ok++; continue; }
    let a = 0;
    while (a < gold.length && a < got.length && gold[a] === got[a]) { a++; }
    let b = 0;
    while (b < gold.length - a && b < got.length - a && gold[gold.length - 1 - b] === got[got.length - 1 - b]) { b++; }
    const goldSpan = gold.slice(a, gold.length - b);
    if (goldSpan !== w) { skipped++; continue; }   // 誤りは同音語以外の場所
    const gotSpan = got.slice(a, got.length - b);
    if (!hasKanji(gotSpan)) { styleOnly++; continue; }   // 漢字→かな: 表記の好み
    if (!hasKanji(goldSpan)) { over++; }                 // かな→漢字: 過剰変換
    total++; s.ng++;
    if (s.examples.length < 3) { s.examples.push([reading, w, gotSpan, got]); }
  }
  console.log(`[HOMOPHONE] ${correct}/${total} (${(100 * correct / total).toFixed(1)}%) 同音語の選択が正解`);
  console.log(`  対象の読み: ${ambiguous.size} 種 (実文で漢字表記が2種類以上, 各${MIN_OCCUR}回以上)`);
  console.log(`  内訳: 誤り ${total - correct} 件 (うち かな→漢字の過剰変換 ${over} 件)`);
  console.log(`  除外: 同音語以外の誤り ${skipped} 文 / 漢字⇔かなの表記の好み ${styleOnly} 文`);

  const target = process.argv.indexOf('--reading');
  if (target >= 0 && process.argv[target + 1]) {
    const r = process.argv[target + 1];
    const s = perReading.get(r);
    console.log(`\n${r}: ${s ? `正解 ${s.ok} / 誤り ${s.ng}` : '対象外'}`);
    if (usage.get(r)) { console.log('  実文での表記:', [...usage.get(r).entries()].sort((a, b) => b[1] - a[1]).map(([w, n]) => `${w}(${n})`).join(' ')); }
    if (s) { for (const [rd, gw, gotSpan, full] of s.examples) { console.log(`  ${rd}\n    gold: ${gw}  got: ${gotSpan}\n    ${full}`); } }
    return;
  }

  if (process.argv.includes('--rank')) {
    const rows = [...perReading.entries()].filter(([, s]) => s.ng > 0).sort((a, b) => b[1].ng - a[1].ng);
    console.log('\n誤り数  読み        実文での表記(出現数)                    例');
    for (const [r, s] of rows.slice(0, 40)) {
      const u = [...usage.get(r).entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([w, n]) => `${w}${n}`).join(' ');
      const ex = s.examples[0];
      console.log(String(s.ng).padStart(5), ' ', r.padEnd(10), u.padEnd(30), ex ? `${ex[1]} ← ${ex[2]}   ${ex[3]}` : '');
    }
  }
}

main();
