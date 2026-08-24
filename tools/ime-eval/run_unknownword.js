#!/usr/bin/env node
// Unit test for UnknownWordLearner (未知語学習). Compiles the .ets module and
// exercises the two assembly signals it exists to catch (piecewise single-kanji
// building, and backspace-truncation of a longer conversion), the boundary
// rules that stop ordinary typing from being mistaken for word building, the
// LEARN_THRESHOLD gate, and the store caps.
//
// Usage: node tools/ime-eval/run_unknownword.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/UnknownWordLearner.ets');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'uw-'));
  const tsPath = path.join(tmp, 'UW.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  // bun なら TypeScript をそのまま require できるので tsc を挟まない。
  if (typeof Bun !== 'undefined') { return tsPath; }
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'UW.js');
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

// Nothing is in the dictionary unless a test says so.
const NEVER_KNOWN = () => false;

function main() {
  const { UnknownWordLearner: UW, LEARN_THRESHOLD, MAX_SURFACE_LEN,
    MAX_RUN_FRAGMENTS, MAX_KEYS } = require(build());

  // ---- signal 1: piecewise assembly (音 + 街 + ウナ) ----
  // Four assemblies should be needed before the word is offered, so the user
  // sees it from roughly the fifth time they type the reading.
  UW.setLearned({});
  const buildUna = () => {
    UW.observe('おと', '音', NEVER_KNOWN);
    UW.observe('まち', '街', NEVER_KNOWN);
    UW.observe('うな', 'ウナ', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  };
  // 回数は LEARN_THRESHOLD から決める。閾値を動かしてもテストが追従する。
  for (let i = 0; i < LEARN_THRESHOLD - 1; i++) { buildUna(); }
  check('piecewise: not offered before the threshold',
    UW.candidates('おとまちうな').length === 0);
  buildUna();
  check('piecewise: offered once the threshold is reached',
    UW.candidates('おとまちうな').join(',') === '音街ウナ',
    JSON.stringify(UW.candidates('おとまちうな')));

  // ---- signal 2: backspace truncation (かける -> 翔ける -> 翔) ----
  UW.setLearned({});
  const buildSho = () => {
    UW.observe('かける', '翔ける', NEVER_KNOWN);
    UW.truncate(); // deletes る
    UW.truncate(); // deletes け
    UW.endRun(NEVER_KNOWN);
  };
  for (let i = 0; i < LEARN_THRESHOLD; i++) { buildSho(); }
  check('truncated: single trimmed commit is learned under the typed reading',
    UW.candidates('かける').join(',') === '翔',
    JSON.stringify(UW.candidates('かける')));

  // ---- signal 2b: extracting one kanji out of a jukugo (熟語), not just a
  // conjugated verb stem -- 学校 -> ⌫ -> 学 ----
  UW.setLearned({});
  const buildGaku = () => {
    UW.observe('がっこう', '学校', NEVER_KNOWN);
    UW.truncate(); // deletes 校, leaving 学 (still content-only: kanji)
    UW.endRun(NEVER_KNOWN);
  };
  for (let i = 0; i < LEARN_THRESHOLD; i++) { buildGaku(); }
  check('truncated: one kanji trimmed out of a jukugo is learned under the full reading',
    UW.candidates('がっこう').join(',') === '学',
    JSON.stringify(UW.candidates('がっこう')));

  // truncate() refuses (returns false, run left untouched) once the tail is
  // ALL hiragana -- no kanji anchor left to trust the character-count
  // correspondence, exactly the historical "〜して" bug (see truncate()'s
  // own comment). KeyboardController falls back to abandonRun() in that case.
  UW.setLearned({});
  UW.observe('して', 'して', NEVER_KNOWN); // raw kana commit, no kanji
  check('truncate() refuses an all-hiragana tail',
    UW.truncate() === false);
  // the run is intentionally left as-is for the caller to decide; simulate
  // KeyboardController's fallback and confirm nothing bogus gets learned.
  UW.abandonRun();
  UW.observe('がっこう', '学校', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN);
  check('no bogus reading/surface pair survives an all-hiragana truncation attempt',
    UW.candidates('して').length === 0 && UW.candidates('してがっこう').length === 0,
    JSON.stringify(UW.getLearned()));

  // A mixed kanji+hiragana tail (翔ける) is safe to truncate through even
  // though it contains hiragana, as long as a kanji anchor remains --
  // confirms the guard is "not ALL hiragana", not "no hiragana at all".
  UW.setLearned({});
  UW.observe('かける', '翔ける', NEVER_KNOWN);
  check('truncate() accepts a mixed kanji+hiragana tail (kanji anchor present)',
    UW.truncate() === true);

  // A single UNtrimmed commit is just ordinary typing, never a learned word.
  UW.setLearned({});
  for (let i = 0; i < 6; i++) {
    UW.observe('でんわ', '電話', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  }
  check('single untouched commit is not learned',
    UW.candidates('でんわ').length === 0,
    JSON.stringify(UW.candidates('でんわ')));

  // ---- a fragment carrying hiragana ends the run ----
  // 音 + 街 then は: the particle closes the run, and 音街 (not 音街は) is what
  // gets counted.
  UW.setLearned({});
  for (let i = 0; i < LEARN_THRESHOLD; i++) {
    UW.observe('おと', '音', NEVER_KNOWN);
    UW.observe('まち', '街', NEVER_KNOWN);
    UW.observe('は', 'は', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  }
  check('hiragana fragment closes the run before itself',
    UW.candidates('おとまち').join(',') === '音街',
    JSON.stringify(UW.candidates('おとまち')));
  check('hiragana fragment is not folded into the learned word',
    UW.candidates('おとまちは').length === 0);

  // ---- already-convertible words are never learned ----
  UW.setLearned({});
  const KNOWN = (r, s) => r === 'おとまちうな' && s === '音街ウナ';
  for (let i = 0; i < 6; i++) {
    UW.observe('おと', '音', KNOWN);
    UW.observe('まち', '街', KNOWN);
    UW.observe('うな', 'ウナ', KNOWN);
    UW.endRun(KNOWN);
  }
  check('a conversion the engine already produces is not learned',
    UW.candidates('おとまちうな').length === 0,
    JSON.stringify(UW.candidates('おとまちうな')));

  // ---- shape guards ----
  // Too long to be a term (9 chars of surface).
  UW.setLearned({});
  // 上限をちょうど1文字超える表記を2断片で組み立てる (定数に追従)。
  const longSurface = '亜'.repeat(MAX_SURFACE_LEN + 1);
  const longReading = 'あ'.repeat(MAX_SURFACE_LEN + 1);
  for (let i = 0; i < LEARN_THRESHOLD + 1; i++) {
    UW.observe(longReading.slice(0, 2), longSurface.slice(0, 2), NEVER_KNOWN);
    UW.observe(longReading.slice(2), longSurface.slice(2), NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  }
  check('over-long assemblies are rejected',
    UW.candidates(longReading).length === 0,
    JSON.stringify(UW.candidates(longReading)));

  // A run made only of kana surfaces has no conversion to remember.
  UW.setLearned({});
  for (let i = 0; i < 5; i++) {
    UW.observe('そう', 'そう', NEVER_KNOWN);
    UW.observe('だね', 'だね', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  }
  check('all-kana assemblies are rejected',
    UW.candidates('そうだね').length === 0,
    JSON.stringify(UW.candidates('そうだね')));

  // ---- truncation that eats a whole fragment abandons the run ----
  UW.setLearned({});
  for (let i = 0; i < 5; i++) {
    UW.observe('おと', '音', NEVER_KNOWN);
    UW.observe('まち', '街', NEVER_KNOWN);
    UW.truncate(); // 街 is 1 char -> whole fragment gone, run no longer describes the text
    UW.endRun(NEVER_KNOWN);
  }
  check('deleting past the run abandons it',
    UW.candidates('おとまち').length === 0 && UW.candidates('おと').length === 0,
    JSON.stringify(UW.candidates('おとまち')));

  // ---- a run longer than the fragment cap is discarded ----
  UW.setLearned({});
  // 断片の上限をちょうど1つ超える run を作る (定数に追従)。
  const frags = [['あ','亜'],['い','衣'],['う','宇'],['え','江'],['お','雄'],
    ['か','火'],['き','木'],['く','区'],['け','家'],['こ','古']];
  for (let i = 0; i < LEARN_THRESHOLD + 1; i++) {
    for (let f = 0; f < MAX_RUN_FRAGMENTS + 1; f++) {
      UW.observe(frags[f][0], frags[f][1], NEVER_KNOWN);
    }
    UW.endRun(NEVER_KNOWN);
  }
  check('runs past the fragment cap are discarded',
    Object.keys(UW.getLearned()).length === 0,
    JSON.stringify(UW.getLearned()));

  // ---- persistence round-trip ----
  UW.setLearned({});
  buildUna(); buildUna(); buildUna(); buildUna();
  const saved = JSON.parse(JSON.stringify(UW.getLearned()));
  UW.setLearned({});
  check('store is empty after reset', UW.candidates('おとまちうな').length === 0);
  UW.setLearned(saved);
  check('learned words survive a save/load round-trip',
    UW.candidates('おとまちうな').join(',') === '音街ウナ');

  // ---- key cap evicts the weakest reading rather than freezing ----
  UW.setLearned({});
  // 上限を少し超えるところまで、2断片の別々の組み立てで埋める (定数に追従)。
  const kana = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ';
  const target = MAX_KEYS + 20;
  let made = 0;
  for (let a = 0; a < kana.length && made < target; a++) {
    for (let b = 0; b < kana.length && made < target; b++) {
      UW.observe(kana[a], '亜', NEVER_KNOWN);
      UW.observe(kana[b], '衣', NEVER_KNOWN);
      UW.endRun(NEVER_KNOWN);
      made++;
    }
  }
  const keyCount = Object.keys(UW.getLearned()).length;
  check('store stays at or under the key cap', keyCount <= MAX_KEYS, `keys=${keyCount}`);
  check('store keeps learning past the cap', keyCount > 0, `keys=${keyCount}`);

  // ---- signal 3: ABANDONED - typed reading in full, deleted it without
  // converting, then immediately hand-assembled the same reading piecewise.
  // Even though this is a strong signal, it must NOT jump straight to a real
  // candidate on the very first rebuild -- a wrong guess promoted straight to
  // a prominent candidate slot would be worse than an ordinary miss. It lands
  // as a quasi-candidate, same as any other first-time assembly; only an
  // explicit follow-up pick (confirmQuasi) promotes it from there.
  UW.setLearned({});
  UW.noteAbandonedReading('しょうがっこう');
  UW.observe('しょう', '小', NEVER_KNOWN);
  UW.observe('がっこう', '学校', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN);
  check('abandon-confirmed: quasi (not yet a real candidate) after a single rebuild',
    UW.candidates('しょうがっこう').length === 0
      && UW.quasiCandidates('しょうがっこう').join(',') === '小学校',
    JSON.stringify({ real: UW.candidates('しょうがっこう'), quasi: UW.quasiCandidates('しょうがっこう') }));

  // Explicitly picking that quasi-candidate (confirmQuasi, mirrors tapping it
  // in the candidate bar) promotes it -- "押されたら昇進".
  UW.confirmQuasi('しょうがっこう', '小学校');
  check('confirmQuasi: promoted to a real candidate after being picked',
    UW.candidates('しょうがっこう').join(',') === '小学校',
    JSON.stringify(UW.candidates('しょうがっこう')));

  // The signal is one-shot: a second unrelated flush must not still be "confirmed".
  UW.setLearned({});
  UW.noteAbandonedReading('あんまり');
  // an unrelated flush consumes (and clears) the abandoned-reading signal
  UW.observe('おと', '音', NEVER_KNOWN);
  UW.observe('まち', '街', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN);
  check('abandon signal is consumed by the next flush regardless of match',
    UW.candidates('おとまち').length === 0, // one occurrence, not fast-tracked
    JSON.stringify(UW.candidates('おとまち')));
  // and the original reading now needs the normal number of repeats again
  const buildAnmari = () => {
    UW.observe('あん', '安', NEVER_KNOWN);
    UW.observe('まり', '余り', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  };
  for (let i = 0; i < LEARN_THRESHOLD - 1; i++) { buildAnmari(); }
  check('a consumed (non-matching) abandon signal does not fast-track later rebuilds',
    UW.candidates('あんまり').length === 0,
    JSON.stringify(UW.candidates('あんまり')));

  // Garbage input to noteAbandonedReading (too short / not hiragana) is ignored
  // rather than remembered as a bogus signal. confirmed no longer changes the
  // bump amount (see above), so the only observable trace is the onLearn
  // callback's confirmed flag -- hook it to check.
  UW.setLearned({});
  let lastConfirmed = undefined;
  UW.onLearn = (r, s, confirmed) => { lastConfirmed = confirmed; };
  UW.noteAbandonedReading('A'); // too short, not hiragana
  UW.observe('しょう', '小', NEVER_KNOWN);
  UW.observe('がっこう', '学校', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN);
  check('invalid abandoned reading is not remembered (confirmed=false)',
    lastConfirmed === false, `lastConfirmed=${lastConfirmed}`);

  // A genuinely matching abandon signal does flag confirmed=true.
  UW.setLearned({});
  lastConfirmed = undefined;
  UW.noteAbandonedReading('しょうがっこう');
  UW.observe('しょう', '小', NEVER_KNOWN);
  UW.observe('がっこう', '学校', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN);
  check('matching abandon signal flags confirmed=true',
    lastConfirmed === true, `lastConfirmed=${lastConfirmed}`);
  UW.onLearn = undefined;

  // ---- quasiCandidates: sub-threshold assemblies are visible but not
  // promoted into candidates() ----
  UW.setLearned({});
  UW.observe('おと', '音', NEVER_KNOWN);
  UW.observe('まち', '街', NEVER_KNOWN);
  UW.observe('うな', 'ウナ', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN); // 1st assembly only, threshold not reached
  check('quasi: visible after just one assembly (threshold not reached)',
    UW.quasiCandidates('おとまちうな').join(',') === '音街ウナ',
    JSON.stringify(UW.quasiCandidates('おとまちうな')));

  // Tapping the quasi-candidate as shown in the candidate bar is a single
  // whole-word commit, not a piecewise assembly -- observe()/endRun() alone
  // would never count it (flush's assembled check needs >=2 fragments or a
  // truncation). confirmQuasi is the separate path KeyboardController calls
  // for exactly this tap, and it alone must be enough to promote.
  UW.observe('おとまちうな', '音街ウナ', NEVER_KNOWN); // the tap's own commit
  UW.endRun(NEVER_KNOWN); // proves this alone does NOT promote it
  check('a single quasi-candidate tap, observed only as a run, does not promote by itself',
    UW.candidates('おとまちうな').length === 0,
    JSON.stringify(UW.candidates('おとまちうな')));
  UW.confirmQuasi('おとまちうな', '音街ウナ');
  check('confirmQuasi promotes a tapped quasi-candidate to a real candidate',
    UW.candidates('おとまちうな').join(',') === '音街ウナ',
    JSON.stringify(UW.candidates('おとまちうな')));

  UW.setLearned({});
  UW.observe('おと', '音', NEVER_KNOWN);
  UW.observe('まち', '街', NEVER_KNOWN);
  UW.observe('うな', 'ウナ', NEVER_KNOWN);
  UW.endRun(NEVER_KNOWN); // back to a fresh single quasi assembly for the checks below
  check('quasi: not yet a real candidate',
    UW.candidates('おとまちうな').length === 0);
  buildUna(); // crosses LEARN_THRESHOLD
  check('quasi: promoted out of quasiCandidates once real (repeat piecewise assembly)',
    UW.quasiCandidates('おとまちうな').length === 0,
    JSON.stringify(UW.quasiCandidates('おとまちうな')));
  check('quasi: now a real candidate',
    UW.candidates('おとまちうな').join(',') === '音街ウナ');

  console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURE(S)`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
