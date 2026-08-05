#!/usr/bin/env node
// 4000-key random-dictionary sweep: compare old (HEAD) vs new (working tree)
// lookup()[0] for every sampled reading; report any kanji-losing regressions.
// Builds the converter twice (once from committed HEAD, once from the
// current working tree) so it also catches uncommitted changes.
//
// BLIND SPOT: every sampled key is drawn from Object.keys(dict.json) union
// Object.keys(global_dict.json), so every sample already has a direct
// dictionary entry. This never exercises lookupCore()'s "not in any dict"
// branch and therefore never calls segmentJoinFallback()/joinSegs() -- it
// cannot validate a joinSegs change on its own. Use sweep_join.js for that.
//
// Usage:
//   node tools/ime-eval/sweep.js
const fs = require('fs'), path = require('path'), os = require('os');
const { execFileSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..', '..');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

function buildFrom(srcText) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sw-'));
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
const keys = [...new Set([...Object.keys(dict), ...Object.keys(gdict)])];
// mulberry32 PRNG for reproducibility
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
const rand = mulberry32(12345);
const sample = [];
for (let i = 0; i < 4000; i++) sample.push(keys[Math.floor(rand() * keys.length)]);
const hasKanji = (s) => /[一-龯々]/.test(s);
let changed = 0, kanjiLoss = 0, kanjiGain = 0;
const losses = [];
for (const k of sample) {
  const a = convOld.lookup(k)[0], b = convNew.lookup(k)[0];
  if (a === b) continue;
  changed++;
  if (hasKanji(a) && !hasKanji(b)) { kanjiLoss++; if (losses.length < 40) losses.push(`${k}: ${a} -> ${b}`); }
  if (!hasKanji(a) && hasKanji(b)) kanjiGain++;
}
console.log(`sampled 4000; changed ${changed}; kanji-loss ${kanjiLoss}; kanji-gain ${kanjiGain}`);
if (losses.length) console.log('LOSSES:\n' + losses.join('\n'));
