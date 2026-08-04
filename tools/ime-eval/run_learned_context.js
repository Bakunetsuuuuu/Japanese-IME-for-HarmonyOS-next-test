#!/usr/bin/env node
// General learned-context disambiguation test. Proves the scalable mechanism:
// a homophone with NO hand-coded CONTEXT_HINTS entry gets disambiguated purely
// from the user's own writing (the learned next-word bigram), for arbitrary
// vocabulary. Mirrors InputHandler.applyContextRerank + pushPredictions'
// learning, without ArkUI.
//
// Usage: node tools/ime-eval/run_learned_context.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const KKC_SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const NW_SRC = path.join(ROOT, 'entry/src/main/ets/ime/NextWordPredictor.ets');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lctx-'));
  for (const [src, name] of [[KKC_SRC, 'KKC'], [NW_SRC, 'NW']]) {
    fs.writeFileSync(path.join(tmp, name + '.ts'), '// @ts-nocheck\n' + fs.readFileSync(src, 'utf-8'));
  }
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS', '--skipLibCheck',
    path.join(tmp, 'KKC.ts'), path.join(tmp, 'NW.ts')], { stdio: 'inherit' });
  return tmp;
}

let failures = 0;
function check(label, cond, detail) {
  if (cond) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}${detail ? '  -- ' + detail : ''}`); failures++; }
}

function main() {
  const tmp = build();
  const { KanaKanjiConverter } = require(path.join(tmp, 'KKC.js'));
  const { NextWordPredictor } = require(path.join(tmp, 'NW.js'));
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  // Port of applyContextRerank(candidates) with an explicit recentWords array.
  const rerank = (candidates, recentWords) => {
    if (candidates.length < 2 || recentWords.length === 0) return candidates;
    const prev1 = recentWords[recentWords.length - 1];
    const prev2 = recentWords.length >= 2 ? recentWords[recentWords.length - 2] : undefined;
    const learned = NextWordPredictor.learnedNext(prev1, prev2);
    if (learned.length === 0) return candidates;
    const boosted = [];
    for (const s of learned) if (candidates.indexOf(s) >= 0 && boosted.indexOf(s) < 0) boosted.push(s);
    if (boosted.length === 0) return candidates;
    const rest = candidates.filter((c) => boosted.indexOf(c) < 0);
    return [...boosted, ...rest];
  };
  const convertTop = (reading, recentWords) => rerank(conv.lookup(reading).slice(), recentWords)[0];

  // Simulate committing a word sequence, recording bigram transitions exactly
  // as pushPredictions does.
  const commitSeq = (words) => {
    let w1 = '', w2 = '';
    for (const w of words) { NextWordPredictor.record(w1, w2, w); w1 = w2; w2 = w; }
  };

  NextWordPredictor.setLearned({});

  // Teaching flips the default: pick a reading and teach the NON-default sense
  // (no dedicated CONTEXT_HINTS entry involved), proving pure-usage generality.
  // かんじ's default is 感じ; teach 「難しい漢字」so after 難しい it converts to 漢字.
  const baseKanji = conv.lookup('かんじ')[0];
  for (let i = 0; i < 3; i++) { commitSeq(['難しい', '漢字']); }
  check('learned: 難しい then かんじ -> 漢字 (flips default)',
    convertTop('かんじ', ['難しい']) === '漢字',
    JSON.stringify(rerank(conv.lookup('かんじ').slice(), ['難しい']).slice(0, 3)));
  check('no context: かんじ keeps its own default', convertTop('かんじ', []) === baseKanji, baseKanji);

  // Another arbitrary pair with 2-word context: 「資料を作る」. Teach it, then
  // after 資料を, つくる -> 作る (default is already 作る, so instead teach a
  // non-default: 「ビルを建てる」... use きr? Use はかる: teach 距離をはかる->測る.
  NextWordPredictor.setLearned({});
  for (let i = 0; i < 3; i++) { commitSeq(['距離', 'を', '測る']); }
  check('bigram learned: 距離+を -> 測る beats default 計る',
    convertTop('はかる', ['距離', 'を']) === '測る',
    JSON.stringify(rerank(conv.lookup('はかる').slice(), ['距離', 'を']).slice(0, 3)));
  // unrelated context does not trigger the boost
  check('unrelated context leaves default', convertTop('はかる', ['天気']) === conv.lookup('はかる')[0]);

  // never reorders when the learned surface isn't among the candidates
  NextWordPredictor.setLearned({});
  commitSeq(['本', 'を', '読む']);
  check('learned surface absent from candidates -> no-op', convertTop('はかる', ['本', 'を']) === conv.lookup('はかる')[0]);

  console.log(`\n[LEARNED-CONTEXT] ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'}`);
  if (failures > 0) process.exit(1);
}

main();
