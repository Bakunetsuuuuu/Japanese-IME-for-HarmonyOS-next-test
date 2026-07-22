#!/usr/bin/env node
// Eleventh held-out TEST corpus (corpus_test11.js/accept_test11.js), authored
// fresh (not reused from TEST1-10) after the かぜ/風邪 collocation, ん-merge,
// and boundary-detour N-best segmentation fix round -- see corpus_test11.js's
// own header for how it avoids overlapping with that round's own smoke tests.
//
// Usage:
//   node tools/ime-eval/run_test11.js            # summary accuracy
//   node tools/ime-eval/run_test11.js --misses   # also print every miss
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json');
const GDICT = path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json');

function buildConverterModule() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imeeval-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const showMisses = process.argv.includes('--misses');
  const { KanaKanjiConverter } = require(buildConverterModule());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  const convert = (reading) => {
    if (!reading) return '';
    const fullKata = KanaKanjiConverter.toKatakana(reading);
    const segs = conv.segment(reading);
    if (segs.length <= 1) return conv.lookup(reading)[0];
    const full = conv.lookup(reading);
    if ((full[0] !== fullKata && full[0] !== reading) || KanaKanjiConverter.isDictionaryWord(reading)) return full[0];
    const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
    if (prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p))) return reading;
    return prefixParts.join('') + conv.lookup(segs[segs.length - 1])[0];
  };

  const corpus = require('./corpus_test11.js');
  const accept = require('./accept_test11.js');
  let strict = 0, lenient = 0;
  const misses = [];
  for (const [reading, gold] of corpus) {
    const got = convert(reading);
    const okSet = [gold, ...(accept[reading] || [])];
    if (got === gold) strict++;
    if (okSet.includes(got)) lenient++; else misses.push([reading, gold, got]);
  }
  const n = corpus.length;
  console.log(`[TEST11] strict accuracy : ${strict}/${n} (${(100 * strict / n).toFixed(1)}%)`);
  console.log(`[TEST11] lenient accuracy: ${lenient}/${n} (${(100 * lenient / n).toFixed(1)}%)`);
  if (showMisses) {
    for (const [r, g, got] of misses) {
      console.log(`\n${r}\n  gold: ${g}\n  got : ${got}`);
    }
  }
}

main();
