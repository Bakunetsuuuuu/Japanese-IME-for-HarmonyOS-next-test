#!/usr/bin/env node
// Unit test for SuppressedCandidates (候補の削除) plus the forget() paths that
// stop a deleted candidate being resurrected by learning. Covers the filter
// never leaving a reading with nothing to commit, the as-typed-kana guard, the
// caps, and persistence.
//
// Usage: node tools/ime-eval/run_suppressed.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');

function build(names) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sc-'));
  const outs = [];
  for (const n of names) {
    const src = path.join(ROOT, `entry/src/main/ets/ime/${n}.ets`);
    const tsPath = path.join(tmp, `${n}.ts`);
    // The @ohos.* preferences import has no Node equivalent. Only load()/save()
    // touch it and those are the device-side persistence wrappers, not the pure
    // suppression logic under test here -- stub it so the rest can be exercised.
    const body = fs.readFileSync(src, 'utf-8')
      .replace(/^import\s+\w+\s+from\s+'@ohos[^']*';$/gm, 'const dataPreferences: any = undefined;');
    fs.writeFileSync(tsPath, '// @ts-nocheck\n' + body);
    outs.push(tsPath);
  }
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', ...outs], { stdio: 'inherit' });
  return names.map((n) => path.join(tmp, `${n}.js`));
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
  const [scPath, uwPath] = build(['SuppressedCandidates', 'UnknownWordLearner']);
  const { SuppressedCandidates: SC } = require(scPath);
  const { UnknownWordLearner: UW } = require(uwPath);

  // ---- basic suppression ----
  SC.setSuppressed({});
  const cands = ['橋', '箸', '端', 'はし'];
  check('unsuppressed list passes through unchanged',
    SC.filter('はし', cands).join(',') === '橋,箸,端,はし');

  check('suppress accepted', SC.suppress('はし', '箸') === true);
  check('suppressed surface is filtered out',
    SC.filter('はし', cands).join(',') === '橋,端,はし',
    SC.filter('はし', cands).join(','));
  check('other readings are untouched',
    SC.filter('はしら', ['柱', '箸']).join(',') === '柱,箸');

  // ---- the as-typed kana can never be deleted ----
  SC.setSuppressed({});
  check('suppressing the reading itself is refused',
    SC.suppress('はし', 'はし') === false);
  check('refusal leaves the list untouched',
    SC.filter('はし', cands).join(',') === '橋,箸,端,はし');

  // ---- filtering everything still leaves something committable ----
  SC.setSuppressed({});
  SC.suppress('はし', '橋');
  SC.suppress('はし', '箸');
  SC.suppress('はし', '端');
  check('a fully-suppressed reading falls back to its kana',
    SC.filter('はし', ['橋', '箸', '端']).join(',') === 'はし',
    SC.filter('はし', ['橋', '箸', '端']).join(','));
  check('the fallback does not resurrect a deleted surface',
    SC.filter('はし', ['橋', '箸', '端']).indexOf('橋') < 0);

  // ---- idempotence / caps ----
  SC.setSuppressed({});
  SC.suppress('あい', '愛');
  SC.suppress('あい', '愛');
  check('re-suppressing the same surface is idempotent',
    SC.getSuppressed()['あい'].length === 1,
    JSON.stringify(SC.getSuppressed()['あい']));

  SC.setSuppressed({});
  let accepted = 0;
  for (let i = 0; i < 40; i++) { if (SC.suppress('あい', `X${i}`)) { accepted++; } }
  check('per-reading cap holds', SC.getSuppressed()['あい'].length <= 20,
    `len=${SC.getSuppressed()['あい'].length}`);
  check('suppress reports refusal past the cap', accepted < 40, `accepted=${accepted}`);

  SC.setSuppressed({});
  for (let i = 0; i < 520; i++) { SC.suppress(`より${i}`, '亜'); }
  check('reading cap holds', SC.count() <= 500, `count=${SC.count()}`);

  // ---- count / clear drive the settings entry ----
  SC.setSuppressed({});
  check('count is 0 when nothing is deleted', SC.count() === 0);
  SC.suppress('はし', '箸');
  SC.suppress('あめ', '飴');
  check('count reflects distinct readings', SC.count() === 2, `count=${SC.count()}`);
  SC.clear();
  check('clear restores everything', SC.count() === 0 &&
    SC.filter('はし', cands).join(',') === '橋,箸,端,はし');

  // ---- persistence round-trip ----
  SC.setSuppressed({});
  SC.suppress('はし', '箸');
  const saved = JSON.parse(JSON.stringify(SC.getSuppressed()));
  SC.setSuppressed({});
  check('store empty after reset', SC.filter('はし', cands).indexOf('箸') >= 0);
  SC.setSuppressed(saved);
  check('deletions survive a save/load round-trip',
    SC.filter('はし', cands).indexOf('箸') < 0);

  // ---- restore(): the app screen's per-row 戻す ----
  let m = { 'はし': ['橋', '箸'], 'あめ': ['飴'] };
  m = SC.restore(m, 'はし', '箸');
  check('restore() removes just that surface',
    m['はし'].join(',') === '橋', JSON.stringify(m));
  check('restore() leaves other readings alone', m['あめ'].join(',') === '飴');
  m = SC.restore(m, 'はし', '橋');
  check('restore() drops a reading once its last surface is back',
    m['はし'] === undefined, JSON.stringify(m));
  check('restore() of an absent pair is a no-op',
    Object.keys(SC.restore(m, 'ない', '無い')).join(',') === 'あめ');

  // A restored surface must actually reappear once the map is reloaded.
  SC.setSuppressed({ 'はし': ['橋', '箸'] });
  check('deleted surfaces are filtered before restore',
    SC.filter('はし', cands).join(',') === '端,はし');
  SC.setSuppressed(SC.restore(SC.getSuppressed(), 'はし', '箸'));
  check('restored surface reappears in the candidate list',
    SC.filter('はし', cands).join(',') === '箸,端,はし',
    SC.filter('はし', cands).join(','));

  // ---- deleting an unknown-word candidate must not leave it re-offerable ----
  const NEVER_KNOWN = () => false;
  UW.setLearned({});
  for (let i = 0; i < 4; i++) {
    UW.observe('おと', '音', NEVER_KNOWN);
    UW.observe('まち', '街', NEVER_KNOWN);
    UW.observe('うな', 'ウナ', NEVER_KNOWN);
    UW.endRun(NEVER_KNOWN);
  }
  check('assembled word is offered before deletion',
    UW.candidates('おとまちうな').join(',') === '音街ウナ');
  UW.forget('おとまちうな', '音街ウナ');
  check('forget() removes the assembled word',
    UW.candidates('おとまちうな').length === 0,
    JSON.stringify(UW.candidates('おとまちうな')));
  check('forget() drops the now-empty reading entirely',
    UW.getLearned()['おとまちうな'] === undefined,
    JSON.stringify(UW.getLearned()));

  // forget() must not disturb the reading's other surfaces
  UW.setLearned({ 'おとまちうな': { '音街ウナ': 5, '音街うな': 4 } });
  UW.forget('おとまちうな', '音街ウナ');
  check('forget() keeps the reading\'s other surfaces',
    UW.candidates('おとまちうな').join(',') === '音街うな',
    JSON.stringify(UW.candidates('おとまちうな')));

  // forgetting something that was never learned is a no-op
  UW.setLearned({ 'あい': { '愛': 9 } });
  UW.forget('あい', '藍');
  UW.forget('ない', '無い');
  check('forget() of an unlearned pair is a no-op',
    UW.candidates('あい').join(',') === '愛');

  console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURE(S)`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
