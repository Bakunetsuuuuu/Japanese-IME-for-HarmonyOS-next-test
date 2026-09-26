// PC 版の共通部分が使う表 (desktop/core/tables.h) を、Android 版の表 (android/app/src/main/assets/hmos_tables.json。
// それ自体が HarmonyOS 版の ArkTS から tools/gen_android_tables.mjs で作ったもの) から作る。
//   node desktop/tools/gen_core_tables.mjs
// 中身: ローマ字の表 (ROMAJI_TABLE) と、語をつないで差別語になった候補を弾く表 (SLURS。正規表現を、語と「後ろに来てはいけない語」の組に直す)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const t = JSON.parse(fs.readFileSync(path.join(root, 'android/app/src/main/assets/hmos_tables.json'), 'utf8'));

const q = (s) => 'u"' + [...s].map((c) => (c === '"' || c === '\\' ? '\\' + c : c)).join('') + '"';

// 最上位の | で分ける (括弧の中の | は分けない)
function splitTop(s) {
  const out = [];
  let depth = 0, cur = '';
  for (const c of s) {
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === '|' && depth === 0) { out.push(cur); cur = ''; } else cur += c;
  }
  out.push(cur);
  return out;
}

const slurs = splitTop(t.SLURS).map((alt) => {
  const m = alt.match(/^([^()|?*+.\[\]\\]+)(?:\(\?!([^()]+)\))?$/);
  if (!m) throw new Error('SLURS の形が想定外: ' + alt);
  return { word: m[1], not: m[2] ? m[2].split('|') : [] };
});

let o = '// 生成物: desktop/tools/gen_core_tables.mjs (Android 版の hmos_tables.json から)。手で直さない\n';
o += '#pragma once\n\nnamespace shunti {\n\n';
o += 'struct RomajiPair { const char16_t* key; const char16_t* kana; };\n';
o += '// ローマ字 → かな (HarmonyOS 版 ROMAJI_TABLE と同じ)\n';
o += 'constexpr RomajiPair ROMAJI_TABLE[] = {\n';
for (const [k, v] of Object.entries(t.ROMAJI_TABLE)) o += `    {${q(k)}, ${q(v)}},\n`;
o += '};\n\n';
o += 'struct SlurRule { const char16_t* word; const char16_t* not_after[6]; };\n';
o += '// 候補に含まれていたら弾く語 (not_after = その語の直後に来ていれば弾かない語。nullptr で終わる)\n';
o += 'constexpr SlurRule SLURS[] = {\n';
for (const s of slurs) {
  if (s.not.length > 5) throw new Error('not_after が多すぎる');
  o += `    {${q(s.word)}, {${[...s.not.map(q), 'nullptr'].join(', ')}}},\n`;
}
o += '};\n\n}  // namespace shunti\n';
fs.writeFileSync(path.join(root, 'desktop/core/tables.h'), o);
console.log('romaji', Object.keys(t.ROMAJI_TABLE).length, 'slurs', slurs.length);

// Windows 版に同梱するライセンスの文 (Android 版の licenses.txt の見出しと表の説明を PC 版に直したもの)
{
  let lic = fs.readFileSync(path.join(root, 'android/app/src/main/assets/licenses.txt'), 'utf8').replace(/\r\n/g, '\n');
  const before = lic;
  lic = lic.replace('shunti IME (Android 版)', 'shunti IME (Windows 版)');
  lic = lic.replace('■ キー配置・記号・絵文字・顔文字の表\nHarmonyOS 版 shunti IME と同じもの (MIT)。',
    '■ ローマ字の表・差別語の表\nHarmonyOS 版 shunti IME と同じもの (MIT)。\n\n■ 文節の区切りに使う品詞の分類\nmozc の品詞 ID の表 (id.def、BSD-3-Clause) から作ったもの。');
  if (lic === before || !lic.includes('Windows 版') || !lic.includes('品詞の分類')) throw new Error('licenses.txt の形が想定外');
  fs.writeFileSync(path.join(root, 'desktop/windows/LICENSE.txt'), lic.replace(/\n/g, '\r\n'));
  console.log('desktop/windows/LICENSE.txt', lic.length, '字');
}
