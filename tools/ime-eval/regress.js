#!/usr/bin/env node
// Regression classifier: build the converter twice (committed HEAD vs. the
// current working tree) and run every corpus in this directory
// (TRAIN/TEST1-10/VOCAB1-3) through both, classifying every row whose answer
// changed into one of:
//   FIXED              - was wrong before, now matches gold/accept
//   REGRESSED          - matched gold/accept before, now wrong
//   CHANGED_STILL_WRONG - wrong both before and after, but the guess changed
// Rows whose answer didn't change at all are not printed.
//
// This is the tool for answering "did we trade a lucky-correct kanji guess
// for an honest kana fallback, or genuinely regress" -- REGRESSED rows where
// the old answer contained kanji are exactly the tradeoff cases to eyeball
// by hand (see tools/ime-eval/README.md).
//
// Usage:
//   node tools/ime-eval/regress.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json');
const GDICT = path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json');
const EVAL = __dirname;

function build(useHead) {
  const rel = (f) => path.relative(ROOT, f);
  const readF = (f) => useHead
    ? execFileSync('git', ['show', 'HEAD:' + rel(f)], { cwd: ROOT, maxBuffer: 1e9 }).toString('utf-8')
    : fs.readFileSync(f, 'utf-8');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'regress-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + readF(SRC));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return { js: path.join(tmp, 'KKC.js'), dict: JSON.parse(readF(DICT)), gdict: JSON.parse(readF(GDICT)) };
}

function mk(useHead) {
  const { js, dict, gdict } = build(useHead);
  delete require.cache[require.resolve(js)];
  const KKC = require(js).KanaKanjiConverter;
  KKC.loadDictionary(dict);
  KKC.setGlobalDict(gdict);
  KKC.initConnectionMatrix();
  return { KKC, conv: new KKC() };
}

function convertWith(conv, KKC, reading) {
  if (!reading) return '';
  const fullKata = KKC.toKatakana(reading);
  const segs = conv.segment(reading);
  if (segs.length <= 1) return conv.lookup(reading)[0];
  const full = conv.lookup(reading);
  if ((full[0] !== fullKata && full[0] !== reading) || KKC.isDictionaryWord(reading)) return full[0];
  const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1]));
  if (prefixParts.some((p) => KKC.isSymbolOnly(p))) return reading;
  return prefixParts.join('') + conv.lookup(segs[segs.length - 1])[0];
}

function main() {
  const { KKC: KKCOld, conv: convOld } = mk(true);
  const { KKC: KKCNew, conv: convNew } = mk(false);

  const req = (f) => require(path.join(EVAL, f));
  const corpora = [
    ['TRAIN', [...req('corpus.js'), ...req('corpus2.js'), ...req('corpus3.js')], req('accept.js')],
    ['TEST1', req('corpus_test.js'), req('accept_test.js')],
    ['TEST2', req('corpus_test2.js'), req('accept_test2.js')],
    ['TEST3', req('corpus_test3.js'), req('accept_test3.js')],
    ['TEST4', req('corpus_test4.js'), req('accept_test4.js')],
    ['TEST5', req('corpus_test5.js'), req('accept_test5.js')],
    ['TEST6', req('corpus_test6.js'), req('accept_test6.js')],
    ['TEST7', req('corpus_test7.js'), req('accept_test7.js')],
    ['TEST8', req('corpus_test8.js'), req('accept_test8.js')],
    ['TEST9', req('corpus_test9.js'), req('accept_test9.js')],
    ['TEST10', req('corpus_test10.js'), req('accept_test10.js')],
    ['VOCAB1', req('vocab_test.js'), {}],
    ['VOCAB2', req('vocab_test2.js'), {}],
    ['VOCAB3', req('vocab_test3.js'), {}],
  ];

  const totals = { FIXED: 0, REGRESSED: 0, CHANGED_STILL_WRONG: 0 };
  for (const [name, corpus, accept] of corpora) {
    const rows = { FIXED: [], REGRESSED: [], CHANGED_STILL_WRONG: [] };
    for (const [reading, gold] of corpus) {
      const oldGot = convertWith(convOld, KKCOld, reading);
      const newGot = convertWith(convNew, KKCNew, reading);
      if (oldGot === newGot) continue;
      const okSet = [gold, ...((accept && accept[reading]) || [])];
      const oldOk = okSet.includes(oldGot);
      const newOk = okSet.includes(newGot);
      if (oldOk && !newOk) rows.REGRESSED.push([reading, gold, oldGot, newGot]);
      else if (!oldOk && newOk) rows.FIXED.push([reading, gold, oldGot, newGot]);
      else if (!oldOk && !newOk) rows.CHANGED_STILL_WRONG.push([reading, gold, oldGot, newGot]);
    }
    for (const k of Object.keys(totals)) totals[k] += rows[k].length;
    if (rows.FIXED.length || rows.REGRESSED.length || rows.CHANGED_STILL_WRONG.length) {
      console.log(`\n[${name}] FIXED ${rows.FIXED.length}  REGRESSED ${rows.REGRESSED.length}  CHANGED_STILL_WRONG ${rows.CHANGED_STILL_WRONG.length}`);
      for (const [reading, gold, oldGot, newGot] of rows.REGRESSED) {
        console.log(`  REGRESSED: ${reading} | gold: ${gold} | old: ${oldGot} | new: ${newGot}`);
      }
      for (const [reading, gold, oldGot, newGot] of rows.FIXED) {
        console.log(`  FIXED: ${reading} | gold: ${gold} | old: ${oldGot} | new: ${newGot}`);
      }
      for (const [reading, gold, oldGot, newGot] of rows.CHANGED_STILL_WRONG) {
        console.log(`  CHANGED_STILL_WRONG: ${reading} | gold: ${gold} | old: ${oldGot} | new: ${newGot}`);
      }
    }
  }
  console.log(`\nTOTAL: FIXED ${totals.FIXED}  REGRESSED ${totals.REGRESSED}  CHANGED_STILL_WRONG ${totals.CHANGED_STILL_WRONG}`);
}

main();
