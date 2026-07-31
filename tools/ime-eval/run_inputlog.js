#!/usr/bin/env node
// ★ デバッグ専用 / DEBUG-ONLY: ime/InputLog.ets の単体テスト。
//   収集機構を消すときはこのファイルも一緒に消す (tools/check_debug_log.js 参照)。
//
// 実機を出さずに確かめたいのは4点:
//   1. secure field (パスワード欄) では1件も記録されないこと
//   2. カタカナ/英数/かな確定に正しく印が付くこと(精度の集計から外すため)
//   3. JSONL が新しい順に読み戻せて、壊れた行を落とすこと
//   4. 上限を超えたら古い方だけ捨てて収集が続くこと
//
// @ohos.file.fs はここに無いので、メモリ上の偽ファイルシステムを差し込む。
// InputLog.ets 本体は書き換えず、import 先だけ差し替える。
//
// Usage: node tools/ime-eval/run_inputlog.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/InputLog.ets');

// InputLog.ets が使う fs API だけを持つ最小の偽物。ファイルは1本しか無いので
// 中身は文字列1つで足りる。
const FAKE_FS = `
// __esModule を立てないと tsc の __importDefault が exports ごと default に
// 包み直してしまい、fs.OpenMode が undefined になる。
Object.defineProperty(exports, '__esModule', { value: true });
const store = { data: null };
exports.__store = store;
const OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
let pending = null;
exports.default = {
  OpenMode,
  openSync(p, mode) {
    if (mode & OpenMode.TRUNC) { store.data = ''; }
    else if (store.data === null && (mode & OpenMode.CREATE)) { store.data = ''; }
    pending = p;
    return { fd: 1 };
  },
  writeSync(fd, text) { store.data = (store.data || '') + text; return text.length; },
  closeSync() { pending = null; },
  readTextSync() { if (store.data === null) { throw new Error('ENOENT'); } return store.data; },
  accessSync() { return store.data !== null; },
  statSync() { if (store.data === null) { throw new Error('ENOENT'); } return { size: store.data.length }; },
  unlinkSync() { store.data = null; },
};
`;

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'inputlog-'));
  fs.writeFileSync(path.join(tmp, 'fakefs.js'), FAKE_FS);
  const tsPath = path.join(tmp, 'IL.ts');
  const src = fs.readFileSync(SRC, 'utf-8').replace("from '@ohos.file.fs'", "from './fakefs'");
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + src);
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return tmp;
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
  const tmp = build();
  const { InputLog, LF_KATAKANA, LF_ALNUM, LF_KANA, LK_COMMIT, LK_DELCAND } =
    require(path.join(tmp, 'IL.js'));
  const fake = require(path.join(tmp, 'fakefs.js'));
  const DIR = '/files';
  const reset = () => { fake.__store.data = null; InputLog.clear(DIR); };

  InputLog.setFilesDir(DIR);

  // ---- 1. secure field ------------------------------------------------
  reset();
  InputLog.beginField();                 // 属性が届くまでは記録しない
  InputLog.recordCommit('ぱすわーど', 'パスワード', 0, 3);
  InputLog.flush();
  check('属性が届く前は記録しない', InputLog.readRaw(DIR).length === 0,
    JSON.stringify(InputLog.readRaw(DIR)));

  InputLog.setFieldPattern(7);           // PASSWORD
  InputLog.recordCommit('ひみつ', '秘密', 0, 2);
  InputLog.flush();
  check('パスワード欄は記録しない', InputLog.readRaw(DIR).length === 0);

  InputLog.setFieldPattern(0);           // 通常のテキスト欄
  InputLog.recordCommit('ひみつ', '秘密', 0, 2);
  InputLog.flush();
  check('通常の欄は記録する', InputLog.countLines(InputLog.readRaw(DIR)) === 1);

  // ---- 2. 確定の性質の印 ----------------------------------------------
  reset();
  InputLog.setFieldPattern(0);
  InputLog.recordCommit('こーひー', 'コーヒー', 1, 5);   // カタカナ
  InputLog.recordCommit('abc', 'abc', 0, 2);            // 読みと同じ
  InputLog.recordCommit('えー', 'A', 2, 4);             // 英数
  InputLog.recordCommit('かんじ', '漢字', 0, 6);         // 通常の変換
  InputLog.flush();
  const rows = InputLog.parse(InputLog.readRaw(DIR), 100);
  check('新しい順に読み戻る', rows.length === 4 && rows[0].s === '漢字' && rows[3].s === 'コーヒー',
    rows.map((r) => r.s).join(','));
  const flagOf = (surface) => rows.filter((r) => r.s === surface)[0].x;
  check('カタカナ確定に印が付く', flagOf('コーヒー') === LF_KATAKANA, flagOf('コーヒー'));
  check('かな確定に印が付く', flagOf('abc') === LF_KANA, flagOf('abc'));
  check('英数確定に印が付く', flagOf('A') === LF_ALNUM, flagOf('A'));
  check('通常の変換には印が付かない', flagOf('漢字') === '', flagOf('漢字'));
  check('候補の番号と総数が残る',
    rows.filter((r) => r.s === 'コーヒー')[0].i === 1 &&
    rows.filter((r) => r.s === 'コーヒー')[0].n === 5);
  check('種別は commit', rows[0].k === LK_COMMIT, rows[0].k);

  // ---- 3. 壊れた行を落とす --------------------------------------------
  fake.__store.data += '{"t":1,"k":"commit"';   // 書き込み中に切れた末尾
  const rows2 = InputLog.parse(InputLog.readRaw(DIR), 100);
  check('壊れた行は捨てる', rows2.length === 4, String(rows2.length));

  // ---- 4. 溜めてから書く / 明示 flush ---------------------------------
  reset();
  InputLog.setFieldPattern(0);
  InputLog.recordDeleteCandidate('はいじんじゃ', '廃神社', 4);
  check('flush 前はまだ書かれていない', InputLog.readRaw(DIR).length === 0);
  InputLog.flush();
  const del = InputLog.parse(InputLog.readRaw(DIR), 10)[0];
  check('候補削除が記録される', del !== undefined && del.k === LK_DELCAND && del.s === '廃神社');

  // 16件でしきい値 flush が走る(明示 flush なしで書かれている)。
  reset();
  InputLog.setFieldPattern(0);
  for (let i = 0; i < 16; i++) { InputLog.recordCommit('あ', '亜', 0, 1); }
  check('16件で自動的に書き出される', InputLog.countLines(InputLog.readRaw(DIR)) === 16,
    String(InputLog.countLines(InputLog.readRaw(DIR))));

  // ---- 5. 上限超過で古い方だけ捨てる ----------------------------------
  reset();
  InputLog.setFieldPattern(0);
  fake.__store.data = 'x\n'.repeat(2 * 1024 * 1024);   // 上限超え
  InputLog.recordCommit('しんきろく', '新記録', 0, 1);
  InputLog.flush();
  const after = InputLog.readRaw(DIR);
  check('上限を超えたら縮む', after.length < 2 * 1024 * 1024, String(after.length));
  check('直近の記録は残る', after.indexOf('新記録') >= 0);

  // ---- 6. 消去 ---------------------------------------------------------
  InputLog.clear(DIR);
  check('消去すると空になる', InputLog.readRaw(DIR).length === 0 && InputLog.sizeBytes(DIR) === 0);

  console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
