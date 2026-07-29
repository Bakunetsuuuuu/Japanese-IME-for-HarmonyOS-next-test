#!/usr/bin/env node
// DICTIONARY のキー重複を検出する。
//
// DICTIONARY は3万行近い1つのオブジェクトリテラルで、同じ読みを別の場所に
// 書いてしまっても JS/ArkTS はエラーにしない — 後に書いた方が黙って勝つ。
// 前の項目は読まれないまま残り、そこを直しても何も起きないので、原因を
// 探すのに時間を溶かすことになる。実際この検査を入れた時点で51件あった。
//
// Usage: node tools/check_dict_dups.js   (重複があれば exit 1)
const fs = require('fs');
const path = require('path');
const SRC = path.join(__dirname, '..', 'entry/src/main/ets/ime/KanaKanjiConverter.ets');

const src = fs.readFileSync(SRC, 'utf-8');
const start = src.indexOf('const DICTIONARY');
if (start < 0) { console.error('DICTIONARY not found'); process.exit(1); }
const lines = src.slice(start).split('\n');
const seen = new Map();
const dups = [];
for (let i = 0; i < lines.length; i++) {
  if (/^\};/.test(lines[i])) { break; }
  const m = /^\s{2}'([^']+)':/.exec(lines[i]);
  if (!m) { continue; }
  if (seen.has(m[1])) { dups.push([m[1], seen.get(m[1]), i]); } else { seen.set(m[1], i); }
}
const base = src.slice(0, start).split('\n').length - 1;
console.log(`DICTIONARY: ${seen.size} keys, ${dups.length} duplicates`);
for (const [k, a, b] of dups) {
  console.log(`  '${k}'  ${SRC}:${base + a + 1}  →  ${SRC}:${base + b + 1} (この行が勝つ)`);
}
process.exit(dups.length > 0 ? 1 : 0);
