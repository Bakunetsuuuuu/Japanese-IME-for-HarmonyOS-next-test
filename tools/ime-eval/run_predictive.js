#!/usr/bin/env node
// Unit test for PredictiveConversion (予測変換 / prefix completion): curated
// completions, learned-store completions, learned-outranks-curated, the
// min-prefix guard, and dedup/cap.
//
// Usage: node tools/ime-eval/run_predictive.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/PredictiveConversion.ets');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pc-'));
  const tsPath = path.join(tmp, 'PC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'PC.js');
}

let failures = 0;
function check(label, cond, detail) {
  if (cond) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}${detail ? '  -- ' + detail : ''}`); failures++; }
}

function main() {
  const { PredictiveConversion: PC } = require(build());

  // curated prefix completion
  check('かいし -> 会社', PC.predict('かいし', {}).includes('会社'), JSON.stringify(PC.predict('かいし', {})));
  // completion only offers words LONGER than the prefix: にほん (=日本, the exact
  // conversion) is excluded, its longer extensions 日本語/日本人 are offered.
  check('にほん -> 日本語/日本人 (not 日本 itself)',
    PC.predict('にほん', {}).includes('日本語') && !PC.predict('にほん', {}).includes('日本'),
    JSON.stringify(PC.predict('にほん', {})));
  // a fully-typed word has no longer curated extension -> no completion
  check('にほんご -> [] (full word, exact conversion handles it)',
    PC.predict('にほんご', {}).length === 0, JSON.stringify(PC.predict('にほんご', {})));
  check('だいじ -> 大丈夫', PC.predict('だいじ', {}).includes('大丈夫'), JSON.stringify(PC.predict('だいじ', {})));

  // min-prefix guard: single kana returns nothing
  check('single kana あ -> []', PC.predict('あ', {}).length === 0, JSON.stringify(PC.predict('あ', {})));

  // exact-length reading (nothing longer) returns nothing from curated for that word
  check('exact にほん does not complete to itself', !PC.predict('にほん', {}).includes('にほん'));

  // cap at 3
  check('capped at 3', PC.predict('か', {}).length <= 3);
  check('さい -> up to 3 (最近/最初/最後/最高 exist)', PC.predict('さい', {}).length === 3, JSON.stringify(PC.predict('さい', {})));

  // learned store: user's own word extends prefix and outranks curated
  const learned = {
    'かいしゃいん': { '会社員': 5 },
    'かいしゅう': { '回収': 2 },
  };
  const r = PC.predict('かいし', learned);
  check('learned 会社員 surfaces for かいし', r.includes('会社員'), JSON.stringify(r));
  check('learned (count 5) outranks curated 会社', r.indexOf('会社員') < r.indexOf('会社'), JSON.stringify(r));

  // learned reading equal to prefix is not a completion (must be longer)
  check('equal-length learned reading excluded',
    !PC.predict('かいしゃ', { 'かいしゃ': { '会社': 9 } }).includes('会社'),
    JSON.stringify(PC.predict('かいしゃ', { 'かいしゃ': { '会社': 9 } })));

  console.log(`\n[PREDICTIVE] ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'}`);
  if (failures > 0) process.exit(1);
}

main();
