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
  const { UnknownWordLearner: UW } = require(build());

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
  buildUna();
  check('piecewise: not offered after 1 assembly',
    UW.candidates('おとまちうな').length === 0);
  buildUna(); buildUna();
  check('piecewise: not offered after 3 assemblies',
    UW.candidates('おとまちうな').length === 0);
  buildUna();
  check('piecewise: offered after 4 assemblies',
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
  for (let i = 0; i < 4; i++) { buildSho(); }
  check('truncated: single trimmed commit is learned under the typed reading',
    UW.candidates('かける').join(',') === '翔',
    JSON.stringify(UW.candidates('かける')));

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
  for (let i = 0; i < 4; i++) {
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
  for (let i = 0; i < 5; i++) {
    UW.observe('あいうえお', '亜衣宇江男', NEVER_KNOWN);
    UW.observe('かきくけ', '下記句家', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  }
  check('over-long assemblies are rejected',
    UW.candidates('あいうえおかきくけ').length === 0,
    JSON.stringify(UW.candidates('あいうえおかきくけ')));

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
  for (let i = 0; i < 5; i++) {
    for (const f of [['あ','亜'],['い','衣'],['う','宇'],['え','江'],['お','雄'],['か','火'],['き','木']]) {
      UW.observe(f[0], f[1], NEVER_KNOWN);
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
  // Fill well past the 300-key cap with distinct 2-fragment assemblies.
  const kana = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ';
  let made = 0;
  for (let a = 0; a < kana.length && made < 320; a++) {
    for (let b = 0; b < kana.length && made < 320; b++) {
      UW.observe(kana[a], '亜', NEVER_KNOWN);
      UW.observe(kana[b], '衣', NEVER_KNOWN);
      UW.endRun(NEVER_KNOWN);
      made++;
    }
  }
  const keyCount = Object.keys(UW.getLearned()).length;
  check('store stays at or under the key cap', keyCount <= 300, `keys=${keyCount}`);
  check('store keeps learning past the cap', keyCount > 0, `keys=${keyCount}`);

  console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURE(S)`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
