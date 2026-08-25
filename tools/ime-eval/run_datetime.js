#!/usr/bin/env node
// Unit test for DateTimePredictor (日付・時刻変換). A fixed injected `now`
// (2026-07-23 15:05, a Thursday) makes every expected value deterministic.
//
// Usage: node tools/ime-eval/run_datetime.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/DateTimePredictor.ets');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dt-'));
  const tsPath = path.join(tmp, 'DT.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit', shell: true });
  return path.join(tmp, 'DT.js');
}

let failures = 0;
function check(label, cond, detail) {
  if (cond) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}${detail ? '  -- ' + detail : ''}`); failures++; }
}

function main() {
  const { DateTimePredictor: DT } = require(build());
  // Thursday 2026-07-23 15:05 local time.
  const now = new Date(2026, 6, 23, 15, 5, 0);

  const today = DT.predict('きょう', now);
  check('きょう -> 2026年7月23日', today.includes('2026年7月23日'), JSON.stringify(today));
  check('きょう -> 曜日付き(木)', today.includes('2026年7月23日(木)'), JSON.stringify(today));
  check('きょう -> 7月23日', today.includes('7月23日'), JSON.stringify(today));
  check('きょう -> 2026/7/23', today.includes('2026/7/23'), JSON.stringify(today));
  check('きょう -> 令和8年7月23日', today.includes('令和8年7月23日'), JSON.stringify(today));

  check('あした -> 2026年7月24日', DT.predict('あした', now).includes('2026年7月24日'), JSON.stringify(DT.predict('あした', now)));
  check('あす -> 7月24日', DT.predict('あす', now).includes('7月24日'), JSON.stringify(DT.predict('あす', now)));
  check('きのう -> 2026年7月22日', DT.predict('きのう', now).includes('2026年7月22日'));
  check('あさって -> 2026年7月25日', DT.predict('あさって', now).includes('2026年7月25日'));
  check('おととい -> 2026年7月21日', DT.predict('おととい', now).includes('2026年7月21日'));

  // month rollover
  const eom = new Date(2026, 6, 31, 9, 0, 0); // 2026-07-31
  check('7/31 の あした -> 2026年8月1日', DT.predict('あした', eom).includes('2026年8月1日'), JSON.stringify(DT.predict('あした', eom)));

  // years
  check('ことし -> 2026年', DT.predict('ことし', now).includes('2026年'));
  check('ことし -> 令和8年', DT.predict('ことし', now).includes('令和8年'));
  check('らいねん -> 2027年', DT.predict('らいねん', now).includes('2027年'));
  check('きょねん -> 2025年', DT.predict('きょねん', now).includes('2025年'));

  // time
  const t = DT.predict('いま', now);
  check('いま -> 15:05', t.includes('15:05'), JSON.stringify(t));
  check('いま -> 15時5分', t.includes('15時5分'), JSON.stringify(t));
  check('いま -> 午後3時5分', t.includes('午後3時5分'), JSON.stringify(t));

  // non-trigger reading returns nothing
  check('かいしゃ -> [] (not a date/time word)', DT.predict('かいしゃ', now).length === 0);
  check('empty -> []', DT.predict('', now).length === 0);

  console.log(`\n[DATETIME] ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'}`);
  if (failures > 0) process.exit(1);
}

main();
