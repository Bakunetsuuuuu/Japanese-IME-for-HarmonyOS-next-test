#!/usr/bin/env node
// Unit test for NextWordPredictor (次単語予測). Compiles the .ets module and
// exercises the three prediction sources (learned / seed / generic particles),
// dedup/cap behaviour, learning caps, and the "sentences don't become bigram
// keys" guard.
//
// Usage: node tools/ime-eval/run_nextword.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/NextWordPredictor.ets');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'nw-'));
  const tsPath = path.join(tmp, 'NW.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit', shell: true });
  return path.join(tmp, 'NW.js');
}

let failures = 0;
function check(label, cond, detail) {
  if (cond) {
    console.log(`PASS  ${label}`);
  } else {
    console.log(`FAIL  ${label}${detail ? '  -- ' + detail : ''}`);
    failures++;
  }
}

function main() {
  const { NextWordPredictor: NW } = require(build());

  // --- generic particle fallback after a content (kanji) word NOT in the seed ---
  NW.setLearned({});
  let p = NW.predict('図書館'); // not in SEED_NEXT -> pure generic-particle fallback
  check('generic particles after 図書館 lead with は', p[0] === 'は', JSON.stringify(p));
  check('図書館 particle predictions present', p.includes('を') && p.includes('に'), JSON.stringify(p));
  check('predictions capped at 6', p.length <= 6, `len=${p.length}`);
  // a seeded noun uses its curated particle order (会社に行く -> に leads)
  check('会社 seed leads with に', NW.predict('会社')[0] === 'に', JSON.stringify(NW.predict('会社')));

  // katakana tail also counts as a content word
  check('カタカナ tail gets particles', NW.predict('パソコン').includes('を'), JSON.stringify(NW.predict('パソコン')));

  // a bare particle is NOT a content tail -> no generic particles
  check('particle は yields no generic particles', NW.predict('は').length === 0, JSON.stringify(NW.predict('は')));

  // --- seed continuations ---
  check('ありがとう -> ございます', NW.predict('ありがとう')[0] === 'ございます', JSON.stringify(NW.predict('ありがとう')));
  check('よろしく -> お願いします', NW.predict('よろしく').includes('お願いします'), JSON.stringify(NW.predict('よろしく')));
  check('私 seed leads は', NW.predict('私')[0] === 'は', JSON.stringify(NW.predict('私')));

  // --- 1-word learned outranks seed/generic (record(prev2, prev1, next)) ---
  NW.setLearned({});
  for (let i = 0; i < 3; i++) { NW.record('', '明日', '会議'); }
  NW.record('', '明日', 'は');
  p = NW.predict('明日');
  check('learned 会議 outranks seed after repeats', p[0] === '会議', JSON.stringify(p));
  check('learned + seed merged & deduped', new Set(p).size === p.length, JSON.stringify(p));

  // --- learning does not record sentence-length keys ---
  NW.setLearned({});
  NW.record('', '今日はいい天気ですね', 'そうですね');
  check('long sentence prev is not learned', Object.keys(NW.getLearned().uni).length === 0);
  NW.record('', '駅', 'に行って改札を出た');
  check('long next value is not learned', Object.keys(NW.getLearned().uni).length === 0);

  // --- prev===next guard ---
  NW.setLearned({});
  NW.record('', '本', '本');
  check('self-transition not learned', Object.keys(NW.getLearned().uni).length === 0);

  // --- value cap per key ---
  NW.setLearned({});
  for (let i = 0; i < 20; i++) { NW.record('', 'あ', 'x' + i); }
  check('per-key value set capped', Object.keys(NW.getLearned().uni['あ']).length <= 12,
    `size=${Object.keys(NW.getLearned().uni['あ'] || {}).length}`);

  // --- predict never includes prev itself ---
  NW.setLearned({});
  NW.record('', '猫', '猫'); // ignored anyway
  check('predict excludes prev', !NW.predict('会社').includes('会社'));

  // --- empty / edge ---
  check('empty prev -> []', NW.predict('').length === 0);

  // --- 2-word (bigram) context outranks the 1-word guess. Teach two different
  // continuations of を depending on the word before it: 映画を→見る, 水を→飲む.
  // With only 1-word context both would compete under を; the bigram keeps them
  // apart. ---
  NW.setLearned({});
  for (let i = 0; i < 2; i++) {
    NW.record('映画', 'を', '見る');
    NW.record('水', 'を', '飲む');
  }
  check('bigram 映画+を -> 見る', NW.predict('を', '映画')[0] === '見る', JSON.stringify(NW.predict('を', '映画')));
  check('bigram 水+を -> 飲む', NW.predict('を', '水')[0] === '飲む', JSON.stringify(NW.predict('を', '水')));
  check('no-context を falls back (still returns something)', NW.predict('を').length >= 0);

  // v2 store round-trips uni + bi through get/setLearned
  const snap = NW.getLearned();
  check('getLearned is v2 with uni+bi', snap.v === 2 && !!snap.uni && !!snap.bi, JSON.stringify(Object.keys(snap)));
  NW.setLearned(snap);
  check('bigram survives get/setLearned round-trip', NW.predict('を', '映画')[0] === '見る', JSON.stringify(NW.predict('を', '映画')));

  // legacy flat map (pre-bigram save) migrates as unigram
  NW.setLearned({ '私': { 'は': 5 } });
  check('legacy flat map migrates to unigram', NW.predict('私')[0] === 'は', JSON.stringify(NW.predict('私')));

  // --- realistic controller flow with 2-word context. Simulate writing
  // 「私は映画を見る」a few times; then after 映画を the strip leads with 見る. ---
  NW.setLearned({});
  const sim = (words) => {
    let w1 = '', w2 = '';
    for (const w of words) {
      NW.record(w1, w2, w);
      w1 = w2; w2 = w;
    }
  };
  for (let i = 0; i < 3; i++) { sim(['私', 'は', '映画', 'を', '見る']); }
  check('flow: 私 -> は on top', NW.predict('私')[0] === 'は', JSON.stringify(NW.predict('私')));
  check('flow: 映画を -> 見る (bigram)', NW.predict('を', '映画')[0] === '見る', JSON.stringify(NW.predict('を', '映画')));

  // --- phraseCompletion: personal habitual multi-word sequences (口癖/定型文),
  // e.g. a signature sign-off "了解しました！", surfaced as one chip once the
  // user has repeated it enough. ---
  NW.setLearned({});
  for (let i = 0; i < 4; i++) { sim(['了解', 'しました', '！']); }
  check('phrase: 了解 -> しました！ (2-word chain)',
    JSON.stringify(NW.phraseCompletion('了解', '')) === JSON.stringify(['しました', '！']),
    JSON.stringify(NW.phraseCompletion('了解', '')));

  // needs the minimum repeat count -- a single occurrence isn't a habit yet
  NW.setLearned({});
  sim(['マジで', '助かる']);
  check('phrase: single occurrence is not yet a habit', NW.phraseCompletion('マジで', '').length === 0,
    JSON.stringify(NW.phraseCompletion('マジで', '')));

  // ambiguous continuation (two roughly-equally-common next words) never
  // becomes "the" habit -- 割と and マジで both follow お疲れ equally often, so
  // neither should be forced as a one-tap phrase.
  NW.setLearned({});
  for (let i = 0; i < 3; i++) { sim(['お疲れ', '割と', 'いい', '感じ']); }
  for (let i = 0; i < 3; i++) { sim(['お疲れ', 'マジで', 'いい', '感じ']); }
  check('phrase: ambiguous first step yields no chain', NW.phraseCompletion('お疲れ', '').length === 0,
    JSON.stringify(NW.phraseCompletion('お疲れ', '')));

  // one clearly-dominant habit (マジで said 4x, たしかに only 1x after お疲れ)
  // DOES chain, and stops before the point where it would loop/repeat.
  NW.setLearned({});
  for (let i = 0; i < 4; i++) { sim(['お疲れ', 'マジで', '助かる', 'わ']); }
  sim(['お疲れ', 'たしかに']);
  const chain = NW.phraseCompletion('お疲れ', '');
  check('phrase: dominant habit chains multiple words', chain[0] === 'マジで' && chain.length >= 2, JSON.stringify(chain));
  check('phrase: capped by maxWords param', NW.phraseCompletion('お疲れ', '', 1).length <= 1, JSON.stringify(NW.phraseCompletion('お疲れ', '', 1)));

  // --- sentence openers (口癖 openers): learned starters lead, seed backs them up ---
  NW.setLearned({});
  check('isSentenceEnd true for 。！？/./\\n', NW.isSentenceEnd('です。') && NW.isSentenceEnd('マジ！') && NW.isSentenceEnd('ok?') && !NW.isSentenceEnd('です'));
  // cold start: seed openers only
  check('openers cold-start uses seed', NW.openers()[0] === 'とりあえず', JSON.stringify(NW.openers()));
  // a learned opener (recorded 3x) leads ahead of the seed
  for (let i = 0; i < 3; i++) { NW.recordOpener('てか'); }
  NW.recordOpener('なんか');
  check('learned opener てか leads', NW.openers()[0] === 'てか', JSON.stringify(NW.openers()));
  check('openers still include seed after learned', NW.openers().includes('とりあえず'), JSON.stringify(NW.openers()));
  // a punctuation-tailed word is never learned as an opener
  NW.recordOpener('です。');
  check('punctuation tail not learned as opener', !NW.openers().includes('です。'), JSON.stringify(NW.openers()));
  // openers live under a reserved key, invisible to ordinary word prediction
  check('opener key does not leak into predict', !NW.predict('てか').includes('なんか') || NW.getLearned().uni['てか'] !== undefined);
  check('openers survive get/setLearned round-trip', (() => { const s = NW.getLearned(); NW.setLearned(s); return NW.openers()[0] === 'てか'; })(), JSON.stringify(NW.openers()));

  console.log(`\n[NEXTWORD] ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'}`);
  if (failures > 0) process.exit(1);
}

main();
