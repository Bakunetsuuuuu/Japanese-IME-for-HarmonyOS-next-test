#!/usr/bin/env node
// 実機の入力ログ (tools/.inputlog/*.jsonl) を採点用コーパスとして再生する。
//
// 手書きコーパスや Tatoeba は「誰かの文」だが、こちらは実際にこの IME で
// 打って候補から選んだもの (読み → 選んだ表記)。辞書や並べ方を変えたとき
// 「実際の使い方で 1 位率が何ポイント動くか」を、変更を入れる前に測るための
// もの。
//
// 使い方 (リポジトリのルートで):
//   node tools/ime-eval/run_inputlog.js                  # 採点して集計を出す
//   node tools/ime-eval/run_inputlog.js --save base      # 結果を保存 (変更前に)
//   node tools/ime-eval/run_inputlog.js --compare base   # 保存した結果と比べる (変更後に)
//   node tools/ime-eval/run_inputlog.js --diag           # 分割の自信 (q 欄) と正解率の関係
//   node tools/ime-eval/run_inputlog.js --show           # 外れた例を 1 件ずつ出す (打った文が出る)
//   node tools/ime-eval/run_inputlog.js --log <file>     # 読むログを指定 (既定: .inputlog の全ファイル)
//   node tools/ime-eval/run_inputlog.js --set UNSURE_PARSE_COST_PER_KANA=1400  # static 設定を上書き
//
// 何を採点しているか:
//   端末のログにある「確定 (commit)」1 件ごとに、今のコードの変換器で同じ
//   読みの候補列を作り直し、選ばれた表記が何番目に来るかを見る。候補列は
//   run_candidates.js と同じ KeyboardController.updateCandidates の移植
//   (custom エンジン)。端末側の学習・文脈・予測補完は入らないので、数字は
//   「学習前の素の変換器の実力」になる。端末ログの順位 (学習込み) も並べて出す。
//
// 注意: ログには実際に打った文が入っている。ここの出力 (--show) や保存
// ファイルは tools/.inputlog/ に置き、git には入れない (.gitignore 済み)。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');
const LOGDIR = path.join(ROOT, 'tools/.inputlog');
const CACHE = path.join(LOGDIR, '.kkc_cache.mjs');

const argv = process.argv.slice(2);
const opt = (name) => { const i = argv.indexOf(name); return i >= 0 ? (argv[i + 1] ?? '') : null; };
const flag = (name) => argv.includes(name);

// 変換器の読み込み。typescript はこの環境に無いので、Node 22.13+ 内蔵の
// 型除去 (module.stripTypeScriptTypes) で .ets をそのまま JS にする。
async function loadConverter() {
  const mod = require('node:module');
  if (typeof mod.stripTypeScriptTypes !== 'function') {
    console.error('Node 22.13 以降が必要です (module.stripTypeScriptTypes を使うため)');
    process.exit(1);
  }
  const src = fs.readFileSync(SRC, 'utf-8');
  const stamp = `// src-size=${src.length} mtime=${fs.statSync(SRC).mtimeMs}\n`;
  if (!fs.existsSync(CACHE) || !fs.readFileSync(CACHE, 'utf-8').startsWith(stamp)) {
    const origEmit = process.emitWarning;
    process.emitWarning = () => {};  // ExperimentalWarning を黙らせる
    const js = mod.stripTypeScriptTypes(src, { mode: 'transform' });
    process.emitWarning = origEmit;
    fs.writeFileSync(CACHE, stamp + js);
  }
  const { KanaKanjiConverter } = await import('file://' + CACHE.replace(/\\/g, '/'));
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  KanaKanjiConverter.collectSegDiag = true;
  // --set NAME=VALUE: 変換器の static な数値設定を上書きして試す
  // (例: --set UNSURE_PARSE_COST_PER_KANA=1400)。しきい値を振るとき用。
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] !== '--set') continue;
    const [name, value] = (argv[i + 1] ?? '').split('=');
    if (!(name in KanaKanjiConverter)) { console.error(`不明な設定: ${name}`); process.exit(1); }
    KanaKanjiConverter[name] = Number(value);
  }
  return KanaKanjiConverter;
}

// KeyboardController.updateCandidates の移植 (run_candidates.js と同じ)。
function makeCandidatesFor(K, conv) {
  return (composing) => {
    const fullKatakana = K.toKatakana(composing);
    const segs = conv.segment(composing);
    const segCostPerKana = conv.segCostPerKanaFor(composing);
    let candidates;
    if (segs.length <= 1) {
      candidates = conv.lookup(composing);
    } else {
      const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
      const hasSymbolPrefix = prefixParts.some((p) => K.isSymbolOnly(p));
      const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
      const fullCands = conv.lookup(composing);
      const fullFirst = fullCands[0];
      const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== composing) || K.isDictionaryWord(composing);
      if (hasRealHit) {
        candidates = fullCands;
      } else {
        const lastSeg = segs[segs.length - 1];
        let lastCands = conv.lookup(lastSeg);
        const forcedLead = K.contextLead(lastSeg, prefixText);
        if (forcedLead !== null && lastCands.length > 0 && lastCands[0] !== forcedLead) {
          lastCands = [forcedLead, ...lastCands.filter((c) => c !== forcedLead)];
        }
        const segCands = hasSymbolPrefix ? [] : lastCands.map((c) => prefixText + c);
        candidates = [];
        if (hasSymbolPrefix) candidates.push(composing);
        else if (segCands.length > 0) candidates.push(segCands[0]);
        if (!candidates.includes(fullKatakana)) candidates.push(fullKatakana);
        for (let i = 1; i < segCands.length; i++) if (!candidates.includes(segCands[i])) candidates.push(segCands[i]);
        if (!candidates.includes(composing)) candidates.push(composing);
      }
    }
    const alts = conv.sentenceAlternatives(composing);
    const kIdx = candidates.indexOf(fullKatakana), cIdx = candidates.indexOf(composing);
    let insertAt;
    if (kIdx < 0 && cIdx < 0) insertAt = candidates.length;
    else if (kIdx < 0) insertAt = cIdx; else if (cIdx < 0) insertAt = kIdx; else insertAt = Math.min(kIdx, cIdx);
    if (insertAt === 0 && candidates.length > 0 && candidates[0] !== composing) insertAt = 1;
    for (const a of alts) { if (!candidates.includes(a)) { candidates.splice(insertAt, 0, a); insertAt++; } }
    const altSeg = conv.findAlternateSegmentation(composing);
    if (altSeg !== null && !candidates.includes(altSeg)) {
      const kanaCount = (t) => (t.match(/[ぁ-ゟ]/g) || []).length;
      const lifts = candidates.length > 0 && kanaCount(altSeg) < kanaCount(candidates[0]);
      candidates.splice(lifts ? 1 : insertAt, 0, altSeg);
    }
    return K.promoteKatakanaIfUnsure(composing, candidates, segCostPerKana);
  };
}

function readLogs() {
  const files = opt('--log') !== null ? [opt('--log')]
    : fs.readdirSync(LOGDIR).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(LOGDIR, f));
  const seen = new Set();
  const out = [];
  for (const f of files) {
    for (const line of fs.readFileSync(f, 'utf-8').split('\n')) {
      if (!line.trim()) continue;
      let r;
      try { r = JSON.parse(line); } catch (_e) { continue; }
      const key = `${r.t}|${r.k}|${r.r}|${r.s}`;
      if (seen.has(key)) continue;  // 取り出しを重ねたログの重複
      seen.add(key);
      out.push(r);
    }
  }
  out.sort((a, b) => a.t - b.t);
  return out;
}

// 採点対象から外す確定: 変換器の外で作られる候補 (予測補完・日付・数字整形・
// 定型句・未知語学習・準候補) を選んだもの。o 欄の無い古いログでは判定
// できないので対象に残す。
const NON_CONVERTER = new Set(['pred', 'date', 'num', 'phrase', 'unk', 'quasi']);

function pct(a, b) { return b === 0 ? '-' : (100 * a / b).toFixed(1) + '%'; }

(async () => {
  const K = await loadConverter();
  const conv = new K();
  const candidatesFor = makeCandidatesFor(K, conv);
  const rows = readLogs();
  const commits = rows.filter((r) => r.k === 'commit' && r.i >= 0 && r.r && r.s);
  const cases = [];
  let skippedOrigin = 0;
  for (const r of commits) {
    const origins = r.o ? r.o.split(',') : null;
    const org = origins && origins[r.i] ? origins[r.i].split('^')[0] : '';
    if (NON_CONVERTER.has(org)) { skippedOrigin++; continue; }
    cases.push({ t: r.t, reading: r.r, want: r.s, deviceRank: r.i + 1, origin: org, q: r.q || '' });
  }
  if (cases.length === 0) { console.log('採点できる確定がありません'); return; }

  const t0 = Date.now();
  for (const c of cases) {
    const list = candidatesFor(c.reading);
    const idx = list.indexOf(c.want);
    c.rank = idx >= 0 ? idx + 1 : 0;  // 0 = 候補列に無い
    c.kind = K.explainSources(c.reading, c.want).split('+').map((x) => x.split('#')[0].split('=')[0]).filter(Boolean);
    c.kind = [...new Set(c.kind)].sort().join('+');
    if (!c.q) c.q = conv.segDiagFor(c.reading);
  }
  const ms = Date.now() - t0;

  const summarize = (label, list, rankOf) => {
    const n = list.length;
    const top = (k) => list.filter((c) => { const r = rankOf(c); return r >= 1 && r <= k; }).length;
    const miss = list.filter((c) => rankOf(c) === 0).length;
    const mrr = list.reduce((a, c) => a + (rankOf(c) > 0 ? 1 / rankOf(c) : 0), 0) / n;
    console.log(`${label.padEnd(22)} n=${String(n).padStart(4)}  1位 ${pct(top(1), n).padStart(6)}  3位内 ${pct(top(3), n).padStart(6)}  10位内 ${pct(top(10), n).padStart(6)}  列に無し ${String(miss).padStart(3)}  MRR ${mrr.toFixed(3)}`);
  };

  console.log(`ログ ${rows.length} 件 / 確定 ${commits.length} 件 / 採点 ${cases.length} 件 (変換器の外の候補 ${skippedOrigin} 件を除外)  ${ms}ms`);
  console.log('');
  summarize('今のコード (学習なし)', cases, (c) => c.rank);
  summarize('端末 (学習込み)', cases, (c) => c.deviceRank);
  console.log('');
  console.log('読みの長さ別 (今のコード):');
  const byLen = new Map();
  for (const c of cases) {
    const L = c.reading.length >= 8 ? '8+' : String(c.reading.length);
    if (!byLen.has(L)) byLen.set(L, []);
    byLen.get(L).push(c);
  }
  for (const L of [...byLen.keys()].sort((a, b) => parseInt(a) - parseInt(b))) summarize(`  ${L} かな`, byLen.get(L), (c) => c.rank);
  console.log('');
  console.log('選んだ表記の出どころ別 (今のコード):');
  const byKind = new Map();
  for (const c of cases) {
    if (!byKind.has(c.kind)) byKind.set(c.kind, []);
    byKind.get(c.kind).push(c);
  }
  for (const [k, list] of [...byKind.entries()].sort((a, b) => b[1].length - a[1].length).slice(0, 10)) {
    summarize(`  ${k || '?'}`, list, (c) => c.rank);
  }

  if (flag('--diag')) {
    // 分割の自信と正解率。c/かな数 (1かなあたりの経路コスト) と m (次善との差)
    // で区切って、今のコードの 1 位率を見る。未知語 (カタカナ語など) は
    // 経路コストが高く出るはずで、その閾値を決めるための表。
    console.log('');
    console.log('分割の自信と 1 位率 (q 欄 / 端末ログに無ければその場で計算):');
    const parsed = cases.map((c) => {
      const m = /c=(-?\d+) m=(-?\d+|-) s=(.*)$/.exec(c.q);
      if (!m) return null;
      const segs = m[3].split('/');
      return { c, perKana: parseInt(m[1]) / c.reading.length, margin: m[2] === '-' ? null : parseInt(m[2]), segs: segs.length, unknown: segs.filter((s) => s.endsWith('u')).length };
    }).filter(Boolean);
    const buckets = [[-Infinity, 300], [300, 600], [600, 900], [900, 1200], [1200, 1600], [1600, Infinity]];
    for (const [lo, hi] of buckets) {
      const list = parsed.filter((p) => p.perKana >= lo && p.perKana < hi).map((p) => p.c);
      if (list.length === 0) continue;
      const kata = list.filter((c) => c.kind === 'kata').length;
      summarize(`  コスト/かな ${lo === -Infinity ? '' : lo}〜${hi === Infinity ? '' : hi}`, list, (c) => c.rank);
      console.log(`${''.padEnd(26)}うちカタカナを選んだ ${kata} 件`);
    }
    const mb = [[null, null], [-Infinity, 500], [500, 1500], [1500, 3000], [3000, Infinity]];
    for (const [lo, hi] of mb) {
      const list = parsed.filter((p) => lo === null ? p.margin === null : (p.margin !== null && p.margin >= lo && p.margin < hi)).map((p) => p.c);
      if (list.length === 0) continue;
      summarize(lo === null ? '  次善なし' : `  次善との差 ${lo === -Infinity ? '' : lo}〜${hi === Infinity ? '' : hi}`, list, (c) => c.rank);
    }
  }

  const saveName = opt('--save');
  if (saveName) {
    const file = path.join(LOGDIR, `eval_${saveName}.json`);
    fs.writeFileSync(file, JSON.stringify(cases.map((c) => ({ t: c.t, reading: c.reading, want: c.want, rank: c.rank }))));
    console.log(`\n保存しました: ${file}`);
  }
  const cmpName = opt('--compare');
  if (cmpName) {
    const file = path.join(LOGDIR, `eval_${cmpName}.json`);
    const base = new Map(JSON.parse(fs.readFileSync(file, 'utf-8')).map((b) => [`${b.t}|${b.reading}|${b.want}`, b.rank]));
    const norm = (r) => (r === 0 ? 1000 : r);
    let better = 0, worse = 0, same = 0;
    const changed = [];
    for (const c of cases) {
      const b = base.get(`${c.t}|${c.reading}|${c.want}`);
      if (b === undefined) continue;
      if (norm(c.rank) < norm(b)) better++; else if (norm(c.rank) > norm(b)) worse++; else same++;
      if (norm(c.rank) !== norm(b)) changed.push({ c, b });
    }
    console.log(`\n比較 (${cmpName} → 今): 良くなった ${better} / 悪くなった ${worse} / 同じ ${same}`);
    if (flag('--show')) {
      for (const { c, b } of changed) console.log(`  ${b || '無'} → ${c.rank || '無'}  ${c.reading} → ${c.want}`);
    }
  } else if (flag('--show')) {
    console.log('\n1 位を外した確定 (今のコード):');
    for (const c of cases.filter((x) => x.rank !== 1)) {
      console.log(`  ${String(c.rank || '無').padStart(3)}位 (端末 ${c.deviceRank}位)  ${c.reading} → ${c.want}  [${c.kind}]`);
    }
  }
})();
