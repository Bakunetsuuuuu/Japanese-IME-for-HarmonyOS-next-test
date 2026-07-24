#!/usr/bin/env node
// One-shot battery: build the converter exactly once and score it against
// every corpus in this directory (TRAIN, all held-out TEST rounds, VOCAB).
// Equivalent to running run.js + run_test.js..run_test11.js + run_vocab.js..
// run_vocab3.js separately, but ~10x faster since the tsc transpile (the
// slow part) only happens once instead of once per corpus.
//
// Usage:
//   node tools/ime-eval/run_all.js
//
// Use this as the standard before/after check for any converter change --
// see README.md's Workflow section. For a change that touches joinSegs()/
// segmentJoinFallback()/lookupCore()'s no-dict-entry branch specifically,
// this alone is NOT sufficient -- also run sweep_join.js (see its header
// comment for why: every corpus sentence here only exercises readings that
// already resolve via a direct or Viterbi-segmented dictionary hit, never
// the "no dict entry at all" fallback path).
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json');
const GDICT = path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json');
const EVAL = __dirname;

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imeeval-all-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const { KanaKanjiConverter } = require(build());
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
    const _ls = segs[segs.length - 1], _pt = prefixParts.join('');
    const _lc = conv.lookup(_ls), _f = KanaKanjiConverter.contextLead(_ls, _pt);
    return _pt + ((_f !== null && _lc[0] !== _f) ? _f : _lc[0]);
  };

  function runCorpus(name, corpus, accept) {
    let strict = 0, lenient = 0;
    for (const [reading, gold] of corpus) {
      const got = convert(reading);
      const okSet = [gold, ...((accept && accept[reading]) || [])];
      if (got === gold) strict++;
      if (okSet.includes(got)) lenient++;
    }
    const n = corpus.length;
    console.log(`[${name}] strict ${strict}/${n} (${(100 * strict / n).toFixed(1)}%)  lenient ${lenient}/${n} (${(100 * lenient / n).toFixed(1)}%)`);
  }

  const req = (f) => require(path.join(EVAL, f));

  // TRAIN mirrors run.js exactly: corpus.js+corpus2.js+corpus3.js concatenated.
  runCorpus('TRAIN', [...req('corpus.js'), ...req('corpus2.js'), ...req('corpus3.js')], req('accept.js'));
  runCorpus('TEST1', req('corpus_test.js'), req('accept_test.js'));
  runCorpus('TEST2', req('corpus_test2.js'), req('accept_test2.js'));
  runCorpus('TEST3', req('corpus_test3.js'), req('accept_test3.js'));
  runCorpus('TEST4', req('corpus_test4.js'), req('accept_test4.js'));
  runCorpus('TEST5', req('corpus_test5.js'), req('accept_test5.js'));
  runCorpus('TEST6', req('corpus_test6.js'), req('accept_test6.js'));
  runCorpus('TEST7', req('corpus_test7.js'), req('accept_test7.js'));
  runCorpus('TEST8', req('corpus_test8.js'), req('accept_test8.js'));
  runCorpus('TEST9', req('corpus_test9.js'), req('accept_test9.js'));
  runCorpus('TEST10', req('corpus_test10.js'), req('accept_test10.js'));
  runCorpus('TEST11', req('corpus_test11.js'), req('accept_test11.js'));
  runCorpus('VOCAB1', req('vocab_test.js'), null);
  runCorpus('VOCAB2', req('vocab_test2.js'), null);
  runCorpus('VOCAB3', req('vocab_test3.js'), null);
}

main();
