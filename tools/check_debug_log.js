#!/usr/bin/env node
// デバッグ専用の入力ログ収集コードを全部列挙する。
//
// 収集機構は ime/InputLog.ets に閉じてあり、外から呼ぶ箇所は必ず行末に
// `// [DEBUG-LOG]` を付ける約束になっている。約束が守られている限り、
// 「リリース前に何を消せばいいか」はこのスクリプトの出力が答えになる。
//
// 逆に、印の無い InputLog / DEBUG_INPUT_LOG の参照が1つでもあると、その行は
// 消し忘れる。それを検出するのがこのスクリプトの本題で、単なる grep との違い。
//
// Usage:
//   node tools/check_debug_log.js          収集地点の一覧
//   node tools/check_debug_log.js --strict  1件でもあれば exit 1 (リリース確認用)
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const MARK = '[DEBUG-LOG]';
// 中身が丸ごとデバッグ専用のファイル。行ではなくファイルごと消す。
const DEBUG_ONLY_FILES = [
  'entry/src/main/ets/ime/InputLog.ets',
  'entry/src/main/ets/pages/InputLogPage.ets',
  'tools/ime-eval/run_inputlog.js',
  'tools/check_debug_log.js',   // これ自体も収集機構の一部。最後に消す。
];
// 収集機構に触れている名前。これが印の無い行に出てきたら消し忘れ候補。
const SYMBOLS = /\bInputLog\b|\bDEBUG_INPUT_LOG\b|\bINPUT_LOG_FILE\b|\bLearnedWordFn\b|\bonLearn\b/;

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    if (name === 'node_modules' || name === '.git' || name === 'oh_modules' || name === 'build') { continue; }
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) { walk(p, out); }
    else if (/\.(ets|ts|json|json5)$/.test(name)) { out.push(p); }
  }
  return out;
}

function main() {
  const files = walk(path.join(ROOT, 'entry'), []);
  const debugOnly = DEBUG_ONLY_FILES.map((f) => path.join(ROOT, f));

  const marked = [];   // 印付きの行 (消す対象)
  const unmarked = []; // 印の無い参照 (消し忘れになる)
  let flagValue = null;

  for (const file of files) {
    const rel = path.relative(ROOT, file);
    const isDebugOnly = debugOnly.indexOf(file) >= 0;
    const lines = fs.readFileSync(file, 'utf-8').split('\n');
    lines.forEach((line, i) => {
      const m = /const DEBUG_INPUT_LOG:\s*boolean\s*=\s*(true|false)/.exec(line);
      if (m) { flagValue = m[1] === 'true'; }
      if (line.indexOf(MARK) >= 0) { marked.push([rel, i + 1, line.trim()]); return; }
      if (isDebugOnly) { return; }         // ファイルごと消すので行単位では数えない
      if (SYMBOLS.test(line)) { unmarked.push([rel, i + 1, line.trim()]); }
    });
  }

  // main_pages.json への登録もリリース時には消す対象。
  const pagesFile = path.join(ROOT, 'entry/src/main/resources/base/profile/main_pages.json');
  const pagesRegistered = fs.existsSync(pagesFile) &&
    fs.readFileSync(pagesFile, 'utf-8').indexOf('pages/InputLogPage') >= 0;

  const present = fs.existsSync(debugOnly[0]) || fs.existsSync(debugOnly[1]);

  if (!present && marked.length === 0 && unmarked.length === 0 && !pagesRegistered) {
    console.log('[DEBUG-LOG] 収集コードはありません（リリース可）');
    return;
  }

  console.log(`[DEBUG-LOG] DEBUG_INPUT_LOG = ${flagValue}`);
  console.log('\n■ ファイルごと削除するもの');
  for (const f of DEBUG_ONLY_FILES) {
    console.log(`   ${fs.existsSync(path.join(ROOT, f)) ? '' : '(なし) '}${f}`);
  }
  if (pagesRegistered) {
    console.log('   entry/src/main/resources/base/profile/main_pages.json の "pages/InputLogPage" 行');
  }

  console.log(`\n■ 行ごと削除するもの (${marked.length} 行)`);
  let last = '';
  for (const [rel, ln, text] of marked) {
    if (rel !== last) { console.log(`   ${rel}`); last = rel; }
    console.log(`     ${String(ln).padStart(5)}  ${text.length > 100 ? text.slice(0, 97) + '...' : text}`);
  }

  if (unmarked.length > 0) {
    console.log(`\n■ ★印が無いのに収集機構を参照している行 (${unmarked.length} 行)`);
    console.log('   ここに出た行は消し忘れる。行末に // [DEBUG-LOG] を付けること。');
    for (const [rel, ln, text] of unmarked) {
      console.log(`   ${rel}:${ln}  ${text}`);
    }
  }

  console.log(`\n合計: ファイル ${DEBUG_ONLY_FILES.length} + 行 ${marked.length}` +
    (unmarked.length > 0 ? ` (未マーク ${unmarked.length} ★要対応)` : ''));

  if (unmarked.length > 0) { process.exit(1); }
  if (process.argv.includes('--strict')) { process.exit(1); }
}

main();
