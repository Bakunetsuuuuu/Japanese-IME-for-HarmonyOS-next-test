#!/usr/bin/env node
// Concatenated-pair sweep: samples PAIRS of existing dict keys and joins
// their readings together (e.g. keys "とけい" + "をみる" -> "とけいをみる").
// A concatenated reading usually is NOT itself a dict key, which forces
// lookupCore() down its "not in any dict" branch into
// segmentJoinFallback()/joinSegs() -- the exact path sweep.js's sampling
// (single existing keys only) never reaches. Use this alongside sweep.js
// for any change that touches joinSegs()/segmentJoinFallback()/lookupCore's
// no-dict-entry branch.
//
// Same old(HEAD)-vs-new(working tree) methodology as sweep.js: build the
// converter twice and diff lookup()[0] for every sampled concatenated
// reading, flagging kanji-losing regressions.
//
// Usage:
//   node tools/ime-eval/sweep_join.js
const fs = require('fs'), path = require('path'), os = require('os');
const { execFileSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..', '..');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

function buildFrom(srcText) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'swj-'));
  const ts = path.join(tmp, 'K.ts');
  fs.writeFileSync(ts, '// @ts-nocheck\n' + srcText);
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS', '--skipLibCheck', ts], { stdio: 'inherit' });
  return path.join(tmp, 'K.js');
}
function load(mod) {
  delete require.cache[require.resolve(mod)];
  const { KanaKanjiConverter } = require(mod);
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  return new KanaKanjiConverter();
}
const SRCPATH = 'entry/src/main/ets/ime/KanaKanjiConverter.ets';
const newSrc = fs.readFileSync(path.join(ROOT, SRCPATH), 'utf-8');
const oldSrc = execFileSync('git', ['show', 'HEAD:' + SRCPATH], { cwd: ROOT, maxBuffer: 1e9 }).toString();
const convNew = load(buildFrom(newSrc));
const convOld = load(buildFrom(oldSrc));

const dict = JSON.parse(fs.readFileSync(DICT, 'utf-8'));
const gdict = JSON.parse(fs.readFileSync(GDICT, 'utf-8'));
const isPureHiragana = (s) => /^[ぁ-ゖー]+$/.test(s);
// Only pure-hiragana keys make sense to concatenate into a synthetic sentence
// fragment; katakana/mixed keys would produce nonsense readings.
const keys = [...new Set([...Object.keys(dict), ...Object.keys(gdict)])].filter(isPureHiragana);

function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
const rand = mulberry32(67890);
const pairs = [];
const dictSet = new Set(keys);
for (let i = 0; i < 4000; i++) {
  const a = keys[Math.floor(rand() * keys.length)];
  const b = keys[Math.floor(rand() * keys.length)];
  const joined = a + b;
  if (joined.length > 20) continue; // segment() ignores spans > MAX_LEN=10 anyway; keep sentences reasonable
  if (dictSet.has(joined)) continue; // only care about readings NOT already a direct dict hit
  pairs.push(joined);
}
const hasKanji = (s) => /[一-龯々]/.test(s);
let changed = 0, kanjiLoss = 0, kanjiGain = 0;
const losses = [];
for (const k of pairs) {
  const a = convOld.lookup(k)[0], b = convNew.lookup(k)[0];
  if (a === b) continue;
  changed++;
  if (hasKanji(a) && !hasKanji(b)) { kanjiLoss++; if (losses.length < 40) losses.push(`${k}: ${a} -> ${b}`); }
  if (!hasKanji(a) && hasKanji(b)) kanjiGain++;
}
console.log(`sampled ${pairs.length} concatenated pairs; changed ${changed}; kanji-loss ${kanjiLoss}; kanji-gain ${kanjiGain}`);
if (losses.length) console.log('LOSSES:\n' + losses.join('\n'));
