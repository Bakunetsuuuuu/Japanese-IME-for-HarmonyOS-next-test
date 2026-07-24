#!/usr/bin/env node
// Unit test for EmojiSuggest (絵文字サジェスト): surface→emoji lookups, kana vs
// kanji spellings, and that ordinary nouns with no conventional emoji return
// nothing (the strip must stay relevant).
//
// Usage: node tools/ime-eval/run_emoji.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/EmojiSuggest.ets');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'em-'));
  const tsPath = path.join(tmp, 'EM.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'EM.js');
}

let failures = 0;
function has(label, arr, item) {
  if (arr.includes(item)) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}  -- ${JSON.stringify(arr)} missing ${item}`); failures++; }
}
function empty(label, arr) {
  if (Array.isArray(arr) && arr.length === 0) { console.log(`PASS  ${label}`); }
  else { console.log(`FAIL  ${label}  -- expected [] got ${JSON.stringify(arr)}`); failures++; }
}

function main() {
  const { EmojiSuggest: ES } = require(build());

  has('嬉しい -> 😊', ES.forSurface('嬉しい'), '😊');
  has('うれしい (kana) -> 😊', ES.forSurface('うれしい'), '😊');
  has('猫 -> 🐱', ES.forSurface('猫'), '🐱');
  has('ねこ (kana) -> 🐱', ES.forSurface('ねこ'), '🐱');
  has('ありがとう -> 🙏', ES.forSurface('ありがとう'), '🙏');
  has('おめでとう -> 🎉', ES.forSurface('おめでとう'), '🎉');
  has('誕生日 -> 🎂', ES.forSurface('誕生日'), '🎂');
  has('桜 -> 🌸', ES.forSurface('桜'), '🌸');
  has('most-apt first (嬉しい[0]=😊)', [ES.forSurface('嬉しい')[0]], '😊');

  // ordinary nouns with no conventional emoji -> nothing
  empty('会社 -> []', ES.forSurface('会社'));
  empty('問題 -> []', ES.forSurface('問題'));
  empty('明日 -> []', ES.forSurface('明日'));
  empty('empty -> []', ES.forSurface(''));

  console.log(`\n[EMOJI] ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'}`);
  if (failures > 0) process.exit(1);
}

main();
