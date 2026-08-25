#!/usr/bin/env node
// Offline conversion-accuracy harness for the shunti IME.
//
// KanaKanjiConverter.ets has no ArkTS-only runtime dependencies, so it runs as
// plain TypeScript. This script transpiles it on the fly (via the local
// typescript compiler), loads the real bundled dictionaries, reproduces the
// app's default sentence conversion (KeyboardController.updateCandidates ->
// candidate[0]), and reports accuracy against a labeled corpus of natural
// Japanese (reading -> gold surface) pairs.
//
// Usage:
//   node tools/ime-eval/run.js            # summary accuracy
//   node tools/ime-eval/run.js --misses   # also print every miss
//
// Requires a local `typescript` (npx tsc). Intended for iterating on conversion
// quality: change the converter, re-run, confirm accuracy went up and no
// labeled sentence regressed.
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

function buildConverterModule() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imeeval-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit', shell: true });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const showMisses = process.argv.includes('--misses');
  const { KanaKanjiConverter } = require(buildConverterModule());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  // Faithful port of KeyboardController.updateCandidates() candidate[0].
  const convert = (reading) => {
    if (!reading) return '';
    const fullKata = KanaKanjiConverter.toKatakana(reading);
    const segs = conv.segment(reading);
    if (segs.length <= 1) return conv.lookup(reading)[0];
    const full = conv.lookup(reading);
    if ((full[0] !== fullKata && full[0] !== reading) || KanaKanjiConverter.isDictionaryWord(reading)) return full[0];
    const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
    // A prefix segment that resolves to a bare symbol (e.g. かっこ->"()") means
    // Viterbi split a casual word across a symbol "word" -- joining it would
    // produce nonsense like "()よ" for かっこよ. Fall back to plain kana.
    if (prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p))) return reading;
    return prefixParts.join('') + conv.lookup(segs[segs.length - 1])[0];
  };

  const corpus = [...require('./corpus.js'), ...require('./corpus2.js'), ...require('./corpus3.js')];
  // accept.js lists additional *valid* natural-Japanese outputs per reading
  // (okurigana/kana-kanji/homophone variation the IME can't disambiguate). The
  // lenient score counts those as correct; garbage never appears there.
  const accept = require('./accept.js');
  let strict = 0, lenient = 0;
  const misses = [];
  for (const [reading, gold] of corpus) {
    const got = convert(reading);
    const okSet = [gold, ...(accept[reading] || [])];
    if (got === gold) strict++;
    if (okSet.includes(got)) lenient++; else misses.push([reading, gold, got]);
  }
  const n = corpus.length;
  console.log(`strict accuracy : ${strict}/${n} (${(100 * strict / n).toFixed(1)}%)  [exact gold match]`);
  console.log(`lenient accuracy: ${lenient}/${n} (${(100 * lenient / n).toFixed(1)}%)  [any valid natural output]`);
  if (showMisses) {
    for (const [r, g, got] of misses) {
      console.log(`\n${r}\n  gold: ${g}\n  got : ${got}`);
    }
  }
}

main();
