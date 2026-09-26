// HarmonyOS 版の、端末の機能を使わないロジック (NumberFormatter / DateTimePredictor / JapaneseConverter) を Node でそのまま動かして、
// 答え合わせ用の正解を android/app/src/test/resources/golden.json に書く。Kotlin 版はテスト (GoldenTest) でこれと一致を確かめる。
//
//   node tools/gen_android_golden.mjs
//
// ArkTS のファイルを .ts として一時フォルダに写し、Node の型の読み飛ばし (Node 22.18 以降) で読み込む。
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const tmp = mkdtempSync(join(tmpdir(), 'shunti-golden-'));
async function load(name) {
  const dst = join(tmp, `${name}.ts`);
  writeFileSync(dst, readFileSync(join(root, 'entry/src/main/ets/ime', `${name}.ets`), 'utf8'));
  return import(pathToFileURL(dst).href);
}
const { NumberFormatter } = await load('NumberFormatter');
const { DateTimePredictor } = await load('DateTimePredictor');
const { JapaneseConverter } = await load('JapaneseConverter');

const numbers = ['1', '123', '999', '1000', '1001', '10000', '12345', '100000', '1000000', '12345678', '100000000',
  '1234567890', '10000000000000000', '99999999999999999999', '123456789012345678901', '0123', '１２３４５',
  '２０２６', '1000１', 'abc', '12a4', '', '10010', '20000000', '100010001', '11111111'];
const readings = ['きょう', 'ほんじつ', 'あした', 'あす', 'みょうにち', 'きのう', 'さくじつ', 'あさって', 'みょうごにち',
  'おととい', 'いっさくじつ', 'ことし', 'こんねん', 'らいねん', 'みょうねん', 'きょねん', 'さくねん', 'さらいねん',
  'いま', 'げんざい', 'ただいま', 'かな', ''];
// [年, 月(1始まり), 日, 時, 分]: 月末・年末・うるう年・令和の境目・午前0時・正午など
const nows = [[2026, 9, 26, 17, 5], [2026, 12, 31, 23, 59], [2027, 1, 1, 0, 0], [2024, 2, 28, 12, 0], [2024, 2, 29, 9, 9],
  [2019, 4, 30, 11, 30], [2019, 5, 1, 12, 1], [2018, 12, 31, 0, 30], [2020, 3, 1, 1, 0]];

// ローマ字: 1 字ずつ打ったときの、各打鍵の [確定したかな, 残りのローマ字]
const romaji = ['konnnichiha', 'kyouhaiitenkidesu', 'gakkou', 'shinbun', 'kanji', 'nyaa', 'onna', 'tsukue', 'xtu', 'ltsu',
  'wwwww', 'kk', 'n', 'nn', 'nyn', 'sanpo', 'chotto', 'fairu', 'vaiorin', 'tyotto', 'q', 'qa', 'xyz', 'k-ki-', 'hon.',
  'thi', 'dhu', 'jja', 'ccha', 'mmm', 'aiueo', 'KAtakana', 'ssshi'];
const out = {
  numbers: numbers.map((s) => [s, NumberFormatter.predict(s)]),
  dates: [],
  romaji: romaji.map((w) => {
    const c = new JapaneseConverter();
    return [w, [...w].map((ch) => { const r = c.processKey(ch); return [r.committed, r.pending]; })];
  }),
};
for (const [y, m, d, hh, mm] of nows) {
  const now = new Date(y, m - 1, d, hh, mm);
  for (const r of readings) out.dates.push([[y, m, d, hh, mm], r, DateTimePredictor.predict(r, now)]);
}
const dir = join(root, 'android/app/src/test/resources');
mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, 'golden.json'), JSON.stringify(out, null, 1));
console.log(`numbers ${out.numbers.length}, dates ${out.dates.length}, romaji ${out.romaji.length}`);
