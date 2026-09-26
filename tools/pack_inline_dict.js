#!/usr/bin/env node
// 手書きの基本辞書 (KanaKanjiConverter.ets の buildInlineDictionary) を、
// アプリが読むバイナリ (rawfile/inline_dict.*) に書き出す。
//
// なぜ: 以前は const DICTIONARY としてモジュール読み込み時にそのまま JS の
// オブジェクトになっており、約 2.6 万読みでヒープを約 5MB 使っていた。
// dict.json / global_dict.json を tools/pack_dicts.py でバイナリにしたのと
// 同じ形式 (blob + uint8 長さ + 32件ごとの基点 + 読みごとの表記の範囲) に
// すると 1MB 弱で済み、文字列は触れたときに初めて作られる。
//
// ソースは .ets の中に残してある (コメント付きで手で直す辞書なので)。
// entry/hvigorfile.ts がビルドのたびにこれを呼ぶ。中身のハッシュが前回と
// 同じなら何もしないので、普段のビルドではほぼ時間を使わない。
//
// 使い方: node tools/pack_inline_dict.js [--force] [--quiet]
//
// どの版の Node でも動くよう、型除去などは使わずリテラルの部分だけを
// 切り出して評価する (DevEco の hvigor が同梱する Node からも呼ばれるため)。
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const RAWFILE = path.join(ROOT, 'entry/src/main/resources/rawfile');
const STAMP = path.join(ROOT, 'tools/dict_src/inline_dict.sha1');
const NAME = 'inline_dict';
const BLOCK = 32; // KanaKanjiConverter.ets の MOZC_STR_BLOCK と揃える
const HEAD = 'export function buildInlineDictionary(): Record<string, string[]> {\n  const dict: Record<string, string[]> = {';

const force = process.argv.includes('--force');
const quiet = process.argv.includes('--quiet');
const log = (...a) => { if (!quiet) console.log(...a); };

function extractLiteral(src) {
  const a = src.indexOf(HEAD);
  if (a < 0) throw new Error('buildInlineDictionary が見つからない (' + SRC + ')');
  const open = a + HEAD.length - 1;
  let depth = 0, q = null, j = open;
  for (; j < src.length; j++) {
    const c = src[j];
    if (q) { if (c === '\\') { j++; continue; } if (c === q) q = null; continue; }
    if (c === "'" || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && src[j + 1] === '/') { j = src.indexOf('\n', j); continue; }
    if (c === '/' && src[j + 1] === '*') { j = src.indexOf('*/', j) + 1; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) break; }
  }
  return src.slice(open, j + 1);
}

function writeTable(prefix, strings) {
  const enc = strings.map((x) => Buffer.from(x, 'utf8'));
  const lens = Buffer.alloc(enc.length);
  const bases = [];
  let pos = 0;
  enc.forEach((b, i) => {
    if (b.length > 255) throw new Error('uint8 の長さに入らない: ' + strings[i]);
    if (i % BLOCK === 0) bases.push(pos);
    lens[i] = b.length;
    pos += b.length;
  });
  const base = Buffer.alloc(bases.length * 4);
  bases.forEach((v, i) => base.writeUInt32LE(v, i * 4));
  fs.writeFileSync(path.join(RAWFILE, prefix + '.blob'), Buffer.concat(enc));
  fs.writeFileSync(path.join(RAWFILE, prefix + '.len'), lens);
  fs.writeFileSync(path.join(RAWFILE, prefix + '.base'), base);
  return pos + lens.length + base.length;
}

// 書き出したものを読み戻して、元のオブジェクトと 1 件ずつ一致するか確かめる。
function verify(dict) {
  const read = (p) => fs.readFileSync(path.join(RAWFILE, p));
  const table = (prefix) => {
    const blob = read(prefix + '.blob');
    const lens = read(prefix + '.len');
    const out = [];
    let pos = 0;
    for (let i = 0; i < lens.length; i++) { out.push(blob.toString('utf8', pos, pos + lens[i])); pos += lens[i]; }
    return out;
  };
  const keys = table(NAME + '.keys');
  const vals = table(NAME + '.vals');
  const idxBuf = read(NAME + '.idx.bin');
  const idx = [];
  for (let i = 0; i < idxBuf.length; i += 4) idx.push(idxBuf.readUInt32LE(i));
  const want = Object.keys(dict);
  if (keys.length !== want.length) throw new Error(`読みの件数が合わない ${keys.length} != ${want.length}`);
  for (let i = 0; i < keys.length; i++) {
    const got = vals.slice(idx[i], idx[i + 1]);
    const exp = dict[keys[i]];
    if (!exp || got.length !== exp.length || got.some((v, k) => v !== exp[k])) {
      throw new Error('中身が合わない: ' + keys[i]);
    }
    if (i > 0 && Buffer.compare(Buffer.from(keys[i - 1], 'utf8'), Buffer.from(keys[i], 'utf8')) >= 0) {
      throw new Error('並び順が UTF-8 のバイト順になっていない: ' + keys[i]);
    }
  }
}

function main() {
  // Windows で core.autocrlf=true だと作業ツリーは CRLF になる。HEAD の照合とハッシュが改行の違いでずれないよう LF に揃える
  const src = fs.readFileSync(SRC, 'utf8').replace(/\r\n/g, '\n');
  const literal = extractLiteral(src);
  const hash = crypto.createHash('sha1').update(literal).digest('hex');
  const outputs = ['.keys.blob', '.keys.len', '.keys.base', '.vals.blob', '.vals.len', '.vals.base', '.idx.bin']
    .map((x) => path.join(RAWFILE, NAME + x));
  const prev = fs.existsSync(STAMP) ? fs.readFileSync(STAMP, 'utf8').trim() : '';
  if (!force && prev === hash && outputs.every((p) => fs.existsSync(p))) {
    log('inline_dict: 変更なし');
    return;
  }
  // リテラルはデータだけ (型注釈も識別子参照も無い) なのでそのまま評価できる。
  const dict = new Function('return (' + literal + ');')();
  const keys = Object.keys(dict).sort((x, y) => Buffer.compare(Buffer.from(x, 'utf8'), Buffer.from(y, 'utf8')));
  const vals = [];
  const idx = [0];
  for (const k of keys) {
    const v = dict[k];
    if (!Array.isArray(v)) throw new Error('表記が配列でない: ' + k);
    vals.push(...v);
    idx.push(vals.length);
  }
  let total = writeTable(NAME + '.keys', keys);
  total += writeTable(NAME + '.vals', vals);
  const idxBuf = Buffer.alloc(idx.length * 4);
  idx.forEach((v, i) => idxBuf.writeUInt32LE(v, i * 4));
  fs.writeFileSync(path.join(RAWFILE, NAME + '.idx.bin'), idxBuf);
  total += idxBuf.length;
  verify(dict);
  fs.writeFileSync(STAMP, hash + '\n');
  log(`inline_dict: 読み ${keys.length} 件 / 表記 ${vals.length} 個 -> ${(total / 1024).toFixed(0)} KB (照合済み)`);
}

main();
