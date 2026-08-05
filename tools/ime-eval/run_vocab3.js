#!/usr/bin/env node
// Basic-vocabulary coverage check -- bare single-reading lookup(), not
// sentence conversion. See vocab_test3.js for why this exists: corpus_test.js
// (the sentence-level "TEST" set) turned out to overlap in spirit with words
// patched the same session, so this list checks broad everyday-word coverage
// independent of any specific bug fixed so far.
//
// Usage:
//   node tools/ime-eval/run_vocab.js            # summary accuracy
//   node tools/ime-eval/run_vocab.js --misses   # also print every miss
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

  const words = require('./vocab_test3.js');
  let hit = 0;
  const misses = [];
  for (const [reading, gold] of words) {
    const got = conv.lookup(reading, true)[0];
    if (got === gold) { hit++; } else { misses.push([reading, gold, got]); }
  }
  const n = words.length;
  console.log(`[VOCAB3] coverage: ${hit}/${n} (${(100 * hit / n).toFixed(1)}%)`);
  if (showMisses) {
    for (const [r, g, got] of misses) {
      console.log(`\n${r}\n  gold: ${g}\n  got : ${got}`);
    }
  }
}

main();
