#!/usr/bin/env node
// Unit test for NumberFormatter (数値変換): comma / 万-mixed / 漢数字 forms,
// full-width digits, and the guards (too short, leading zero, non-digit).
//
// Usage: node tools/ime-eval/run_number.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/NumberFormatter.ets');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'nf-'));
  const tsPath = path.join(tmp, 'NF.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'NF.js');
}

let failures = 0;
function eq(label, got, want) {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}\n        got  ${g}\n        want ${w}`); failures++; }
}
function has(label, arr, item) {
  if (arr.includes(item)) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}  -- ${JSON.stringify(arr)} missing ${item}`); failures++; }
}

function main() {
  const { NumberFormatter: NF } = require(build());

  eq('1000000', NF.predict('1000000'), ['1,000,000', '100万', '百万']);
  eq('1000', NF.predict('1000'), ['1,000', '千']);
  eq('12345', NF.predict('12345'), ['12,345', '1万2345', '一万二千三百四十五']);
  has('12345678 comma', NF.predict('12345678'), '12,345,678');
  has('12345678 man', NF.predict('12345678'), '1234万5678');
  has('100000000 -> 1億', NF.predict('100000000'), '1億');
  has('100000000 -> 億 kanji', NF.predict('100000000'), '一億');

  // lowest group zero-padded when it isn't the highest (100000056 = 1億0056)
  has('100000056 man pads low group', NF.predict('100000056'), '1億0056');
  // an all-zero middle group is dropped entirely (100005600 = 1億5600)
  has('100005600 drops zero middle group', NF.predict('100005600'), '1億5600');

  // full-width digits
  has('full-width １０００００ handled', NF.predict('１００００'), '10,000');

  // guards
  eq('3 digits: no format', NF.predict('100'), []);
  eq('leading zero (zip/id): no format', NF.predict('0120'), []);
  eq('non-digit: []', NF.predict('あ12'), []);
  eq('empty: []', NF.predict(''), []);

  // kanji spot checks
  eq('10000 kanji is 一万', NF.predict('10000')[2], '一万');
  eq('2000 kanji is 二千', NF.predict('2000')[1], '二千');

  console.log(`\n[NUMBER] ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'}`);
  if (failures > 0) process.exit(1);
}

main();
