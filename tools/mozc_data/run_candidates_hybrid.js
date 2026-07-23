#!/usr/bin/env node
// Homophone-reachability test for track B (mozc) and the third track (hybrid),
// the track-B analogue of tools/ime-eval/run_candidates.js. The corpus scripts
// only grade candidate[0]; this checks that when candidate[0] is NOT the
// intended word, the homophone the user reaches for shows up within the first
// few candidates (positions 1..TOP_N-1) they see before scrolling.
//
// It also asserts the hard invariant that candidate[0] is byte-identical
// between mozc and hybrid: hybrid must only ever REORDER/ADD at positions 1+,
// never change the statistically-chosen top candidate (composeMozcCandidates'
// `base`). A single [0] divergence fails the run.
//
// Usage: node tools/mozc_data/run_candidates_hybrid.js [--show]
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const { loadMozcArgs } = require('./load_mozc');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const RAW = path.join(ROOT, 'entry/src/main/resources/rawfile');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'candhy-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

// Reading -> intended surface. `want` is the homophone a user reaches for when
// the statistical top pick is the other reading; it must be reachable in the
// first few candidates. Natural everyday sentences, verbs/nouns whose reading
// has a common homograph.
const CASES = [
  ['あめをたべる', '飴を食べる'], ['いえにかえる', '家に帰る'],
  ['ほんをよむ', '本を読む'], ['たいじゅうをはかる', '体重を計る'],
  ['もんだいをとく', '問題を解く'], ['ふくをきる', '服を着る'],
  ['てがみをかく', '手紙を書く'], ['あせをかく', '汗をかく'],
  ['みずをのむ', '水を飲む'], ['おんがくをきく', '音楽を聴く'],
  ['ドアをあける', 'ドアを開ける'], ['よあけがくる', '夜明けが来る'],
  ['めをさます', '目を覚ます'], ['ボールをなげる', 'ボールを投げる'],
  ['しあいにでる', '試合に出る'], ['あいてにかつ', '相手に勝つ'],
  ['いえをたてる', '家を建てる'], ['たまごをうむ', '卵を産む'],
  ['ふねにのる', '船に乗る'], ['やくそくをまもる', '約束を守る'],
  ['こどもをみる', '子供を見る'], ['おかねをかりる', 'お金を借りる'],
];

// The intended word must be reachable within the top-N candidates (0-indexed
// position < TOP_N). Track B's per-reading lists are noisier than track A's, so
// TOP_N here is a little more generous than run_candidates.js's 4.
const TOP_N = 6;
// Hybrid must clear this many; it is the whole point of the third track, so it
// is expected to land well above pure mozc (which sits around 19/22).
const HYBRID_MIN = 21;

function main() {
  const show = process.argv.includes('--show');
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(path.join(RAW, 'dict.json'), 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(path.join(RAW, 'global_dict.json'), 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  KanaKanjiConverter.loadMozcEngine(...loadMozcArgs());
  const conv = new KanaKanjiConverter();

  // On-device path: segment() first (sets mozcLastSegs/Input), then lookup()
  // composes the candidate list via composeMozcCandidates.
  const cands = (reading) => { conv.segment(reading); return conv.lookup(reading); };

  const score = (engine) => {
    KanaKanjiConverter.setEngine(engine);
    let reach = 0;
    const rows = [];
    for (const [reading, want] of CASES) {
      const list = cands(reading);
      const idx = list.indexOf(want);
      const ok = idx >= 0 && idx < TOP_N;
      if (ok) reach++;
      rows.push({ reading, want, idx, ok });
    }
    return { reach, rows };
  };

  const mozc = score('mozc');
  const hybrid = score('hybrid');

  // candidate[0] invariant: hybrid never changes the statistical top pick.
  KanaKanjiConverter.setEngine('mozc');
  const base0 = CASES.map(([r]) => cands(r)[0]);
  KanaKanjiConverter.setEngine('hybrid');
  const hy0 = CASES.map(([r]) => cands(r)[0]);
  const zeroDiffs = [];
  for (let i = 0; i < CASES.length; i++) {
    if (base0[i] !== hy0[i]) zeroDiffs.push(`${CASES[i][0]}: mozc="${base0[i]}" hybrid="${hy0[i]}"`);
  }

  const dump = (label, res) => {
    console.log(`\n===== ${label}: ${res.reach}/${CASES.length} reachable (top-${TOP_N}) =====`);
    for (const row of res.rows) {
      if (show || !row.ok) {
        console.log(`  ${row.ok ? 'ok  ' : 'MISS'} ${row.reading} -> "${row.want}" @${row.idx}`);
      }
    }
  };
  dump('mozc', mozc);
  dump('hybrid', hybrid);

  let failed = false;
  if (zeroDiffs.length > 0) {
    console.log(`\n[FAIL] candidate[0] differs between mozc and hybrid (${zeroDiffs.length}):`);
    for (const d of zeroDiffs) console.log('  ' + d);
    failed = true;
  } else {
    console.log('\n[OK] candidate[0] identical for mozc and hybrid across all cases.');
  }
  if (hybrid.reach < HYBRID_MIN) {
    console.log(`\n[FAIL] hybrid reachability ${hybrid.reach} < required ${HYBRID_MIN}`);
    failed = true;
  }
  if (hybrid.reach < mozc.reach) {
    console.log(`\n[FAIL] hybrid (${hybrid.reach}) must not regress below mozc (${mozc.reach})`);
    failed = true;
  }
  console.log(`\n[SUMMARY] mozc ${mozc.reach}/${CASES.length}  hybrid ${hybrid.reach}/${CASES.length}  (hybrid>=mozc, [0] locked)`);
  if (failed) process.exit(1);
}

main();
