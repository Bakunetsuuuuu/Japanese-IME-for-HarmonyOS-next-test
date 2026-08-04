#!/usr/bin/env node
// One-shot side-by-side comparison of the two conversion engines
// (KanaKanjiConverter's track A "custom" hand-built dictionary vs track B
// "mozc" statistical engine) against a tools/ime-eval/ corpus file.
//
// This is NOT a regression gate like tools/ime-eval/regress.js -- track B
// is not expected to match track A. It exists to get an honest read on
// where the mozc engine currently stands, on corpora it was never tuned
// against (see each corpus file's own header for its blind/spent status).
//
// Usage:
//   node tools/mozc_data/compare_engines.js                        # corpus_test10.js, summary only
//   node tools/mozc_data/compare_engines.js --misses                # also print every mozc miss
//   node tools/mozc_data/compare_engines.js corpus_test9.js         # any other corpus file
//   node tools/mozc_data/compare_engines.js corpus_test9.js --misses
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');
const { loadMozcArgs } = require('./load_mozc');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cmpeng-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  // bun で走らせた場合は TypeScript をそのまま require できるので tsc を
  // 挟まない (tsc の入っていない環境でも動かせる):
  //   bun tools/mozc_data/compare_engines.js
  if (typeof Bun !== 'undefined') { return tsPath; }
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
  // Every per-reading mozc structure ships pre-flattened at build time (see
  // tools/mozc_data/convert_to_binary.py); loadMozcArgs (load_mozc.js) reads
  // the files and returns them in loadMozcEngine's argument order.
  KanaKanjiConverter.loadMozcEngine(...loadMozcArgs());
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

  const corpusFile = process.argv.find((a) => a.startsWith('corpus_')) || 'corpus_test10.js';
  const corpus = require(path.join(ROOT, 'tools/ime-eval', corpusFile));

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
  const hybrid = run('hybrid');
  const n = corpus.length;
  console.log(`[custom] strict ${custom.strict}/${n} (${(100 * custom.strict / n).toFixed(1)}%)`);
  console.log(`[mozc]   strict ${mozc.strict}/${n} (${(100 * mozc.strict / n).toFixed(1)}%)`);
  console.log(`[hybrid] strict ${hybrid.strict}/${n} (${(100 * hybrid.strict / n).toFixed(1)}%)`);

  if (showMisses) {
    console.log('\n--- hybrid misses ---');
    for (const [r, g, got] of hybrid.misses) {
      console.log(`${r}\n  gold: ${g}\n  got : ${got}`);
    }
  }
}

main();
