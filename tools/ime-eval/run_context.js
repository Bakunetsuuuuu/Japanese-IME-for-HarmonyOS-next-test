#!/usr/bin/env node
// Context-disambiguation test (文脈依存変換). Each case is
// [contextText, reading, want]: after committing `contextText` (fed to
// addContext, the same buffer contextRerank reads), converting `reading`
// should yield `want` as candidate[0] because the context disambiguates the
// homophone. Measures how often the right kanji is chosen given context --
// the core of writing natural sentences, where 写真をとる wants 撮る but
// メモをとる wants 取る.
//
// Usage: node tools/ime-eval/run_context.js [--show]
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ctx-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

// [context sentence already written, reading being typed now, desired kanji].
const CASES = [
  // とる: 撮る / 取る / 採る / 捕る
  ['カメラで写真を', 'とる', '撮る'],
  ['会議のメモを', 'とる', '取る'],
  ['資格を', 'とる', '取る'],
  ['川で魚を', 'とる', '捕る'],
  // みる: 見る / 診る
  ['映画館で映画を', 'みる', '見る'],
  ['医者が患者を', 'みる', '診る'],
  // きく: 聞く / 効く
  ['音楽を', 'きく', '聞く'],
  ['この薬はよく', 'きく', '効く'],
  // かく: 書く / 描く
  ['ノートに文章を', 'かく', '書く'],
  ['画用紙に絵を', 'かく', '描く'],
  // あう: 会う / 合う / 遭う
  ['駅で友達に', 'あう', '会う'],
  ['事故に', 'あう', '遭う'],
  ['サイズが', 'あう', '合う'],
  // はかる: 測る / 計る / 量る
  ['定規で長さを', 'はかる', '測る'],
  ['ストップウォッチで時間を', 'はかる', '計る'],
  ['はかりで重さを', 'はかる', '量る'],
  // あつい: 暑い / 熱い / 厚い
  ['夏はとても', 'あつい', '暑い'],
  ['この本はとても', 'あつい', '厚い'],
  ['お茶が', 'あつい', '熱い'],
  // かたい: 硬い / 固い / 堅い
  ['この石はとても', 'かたい', '硬い'],
  // つくる: 作る / 造る / 創る
  ['夕飯を', 'つくる', '作る'],
  ['船を', 'つくる', '造る'],
  // しめる: 閉める / 締める / 占める
  ['窓を', 'しめる', '閉める'],
  ['ネクタイを', 'しめる', '締める'],
  // なく: 泣く / 鳴く
  ['赤ちゃんが', 'なく', '泣く'],
  ['鳥が', 'なく', '鳴く'],
  // のぼる: 登る / 上る / 昇る
  ['山に', 'のぼる', '登る'],
  ['太陽が', 'のぼる', '昇る'],
  // さます: 冷ます / 覚ます
  ['熱いスープを', 'さます', '冷ます'],
  ['目を', 'さます', '覚ます'],
  // existing coverage sanity (should already pass)
  ['きれいな花が', 'はな', '花'],
  ['電車に', 'のる', '乗る'],
  ['雑誌に', 'のる', '載る'],
];

function main() {
  const show = process.argv.includes('--show');
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  let pass = 0;
  const fails = [];
  for (const [ctx, reading, want] of CASES) {
    KanaKanjiConverter.clearContext();
    KanaKanjiConverter.addContext(ctx);
    const got = conv.lookup(reading)[0];
    const ok = got === want;
    if (ok) pass++; else fails.push(`ctx=「${ctx}」 ${reading} -> got「${got}」want「${want}」  [${conv.lookup(reading).slice(0, 4).join(' | ')}]`);
  }
  for (const f of fails) console.log('  MISS ' + f);
  if (show) console.log('');
  console.log(`\n[CONTEXT] ${pass}/${CASES.length} context-disambiguation cases`);
}

main();
