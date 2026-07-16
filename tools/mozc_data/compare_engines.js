#!/usr/bin/env node
// One-shot side-by-side comparison of the two conversion engines
// (KanaKanjiConverter's track A "custom" hand-built dictionary vs track B
// "mozc" statistical engine) against tools/ime-eval/corpus_test10.js.
//
// This is NOT a regression gate like tools/ime-eval/regress.js -- track B
// is not expected to match track A (see corpus_test10.js header). It exists
// to get an honest first read on where the mozc engine currently stands.
//
// Usage:
//   node tools/mozc_data/compare_engines.js            # summary only
//   node tools/mozc_data/compare_engines.js --misses   # print every mozc miss
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json');
const GDICT = path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json');
const MOZC_DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/mozc_dict.json');
const MOZC_COSTS = path.join(ROOT, 'entry/src/main/resources/rawfile/mozc_costs.json');
const MOZC_MATRIX = path.join(ROOT, 'entry/src/main/resources/rawfile/mozc_matrix.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cmpeng-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const showMisses = process.argv.includes('--misses');
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  KanaKanjiConverter.loadMozcEngine(
    JSON.parse(fs.readFileSync(MOZC_DICT, 'utf-8')),
    JSON.parse(fs.readFileSync(MOZC_COSTS, 'utf-8')),
    JSON.parse(fs.readFileSync(MOZC_MATRIX, 'utf-8')));
  const conv = new KanaKanjiConverter();

  const convert = (reading) => {
    if (!reading) return '';
    const fullKata = KanaKanjiConverter.toKatakana(reading);
    const segs = conv.segment(reading);
    if (segs.length <= 1) return conv.lookup(reading)[0];
    const full = conv.lookup(reading);
    if ((full[0] !== fullKata && full[0] !== reading) || KanaKanjiConverter.isDictionaryWord(reading)) return full[0];
    const prefixParts = segs.slice(0, -1).map((s) => conv.autoConvert(s));
    if (prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p))) return reading;
    return prefixParts.join('') + conv.lookup(segs[segs.length - 1])[0];
  };

  const corpus = require(path.join(ROOT, 'tools/ime-eval/corpus_test10.js'));

  function run(engine) {
    KanaKanjiConverter.setEngine(engine);
    let strict = 0;
    const misses = [];
    for (const [reading, gold] of corpus) {
      const got = convert(reading);
      if (got === gold) strict++;
      else misses.push([reading, gold, got]);
    }
    return { strict, misses };
  }

  const custom = run('custom');
  const mozc = run('mozc');
  const n = corpus.length;
  console.log(`[custom] strict ${custom.strict}/${n} (${(100 * custom.strict / n).toFixed(1)}%)`);
  console.log(`[mozc]   strict ${mozc.strict}/${n} (${(100 * mozc.strict / n).toFixed(1)}%)`);

  if (showMisses) {
    console.log('\n--- mozc misses ---');
    for (const [r, g, got] of mozc.misses) {
      console.log(`${r}\n  gold: ${g}\n  got : ${got}`);
    }
  }
}

main();
