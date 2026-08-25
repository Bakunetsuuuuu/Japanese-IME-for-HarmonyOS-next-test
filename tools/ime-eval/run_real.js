#!/usr/bin/env node
// Score the converter against the real-sentence corpus built by
// build_real_corpus.js (~42k Tatoeba sentences), and -- more usefully --
// rank what it gets wrong by how often each mistake occurs.
//
// The hand-written corpus*.js files are small (~1.2k) and were authored
// alongside the fixes they cover, so they mostly confirm known-good behaviour.
// This one is large, external, and written by people who had never heard of
// this IME, so its accuracy number is much lower and much more honest -- treat
// it as a bug-finding instrument, not a score to maximise.
//
// --rank is the mode to actually use: it strips the common prefix/suffix from
// every miss to isolate the differing span, then reports the most frequent
// (gold <- got) pairs with an example. Kana/kanji spelling preference shows up
// there too (事/こと, 時/とき) in BOTH directions, which is the signal that
// those are author style, not conversion errors -- skip them and work down the
// list of pairs where one side is plainly a different word.
//
// Usage:
//   node tools/ime-eval/run_real.js            summary only
//   node tools/ime-eval/run_real.js --rank     frequency-ranked mistake spans
//   node tools/ime-eval/run_real.js --misses   every miss (very long)
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const CORPUS = path.join(__dirname, 'cache_real', 'real_corpus.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imereal-'));
  const ts = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(ts, '// @ts-nocheck\n' +
    fs.readFileSync(path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets'), 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', ts], { stdio: 'inherit', shell: true });
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

  // Same candidate[0] construction the other corpus scripts port.
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
  let ok = 0;
  const misses = [];
  for (const [reading, gold] of data) {
    const got = convert(reading);
    if (got === gold) { ok++; } else { misses.push([reading, gold, got]); }
  }
  console.log(`[REAL] ${ok}/${data.length} (${(100 * ok / data.length).toFixed(1)}%) exact match`);

  if (process.argv.includes('--rank')) {
    const freq = new Map();
    const example = new Map();
    for (const [reading, gold, got] of misses) {
      let a = 0;
      while (a < gold.length && a < got.length && gold[a] === got[a]) { a++; }
      let b = 0;
      while (b < gold.length - a && b < got.length - a && gold[gold.length - 1 - b] === got[got.length - 1 - b]) { b++; }
      const g = gold.slice(a, gold.length - b);
      const o = got.slice(a, got.length - b);
      if (!g.length || !o.length || g.length > 5 || o.length > 5) { continue; }
      const key = `${g} ← ${o}`;
      freq.set(key, (freq.get(key) || 0) + 1);
      if (!example.has(key)) { example.set(key, [gold, got]); }
    }
    const kanaOnly = (s) => /^[ぁ-んァ-ヶー]+$/.test(s);
    console.log('\n件数  gold ← got            例');
    for (const [key, n] of [...freq.entries()].sort((x, y) => y[1] - x[1]).slice(0, 80)) {
      const [g, o] = key.split(' ← ');
      // Both-kana or both-kanji-of-the-same-word differences are spelling
      // preference; the interesting rows are where one side is another word.
      if (kanaOnly(g) || kanaOnly(o)) { continue; }
      const ex = example.get(key);
      console.log(String(n).padStart(5), ' ', key.padEnd(18), ex[0] + '  /  ' + ex[1]);
    }
  }
  if (process.argv.includes('--misses')) {
    for (const [reading, gold, got] of misses) {
      console.log(`\n${reading}\n  gold: ${gold}\n  got : ${got}`);
    }
  }
}

main();
