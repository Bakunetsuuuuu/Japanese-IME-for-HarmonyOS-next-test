#!/usr/bin/env node
// "単語が出ない" coverage check: for each [reading, surface] in
// reading_variants.js, does `surface` appear ANYWHERE in the candidate list the
// keyboard would show (not just at position 0)? A word totally absent is the
// worst usability problem — unreachable even by scrolling. Reproduces
// KeyboardController.updateCandidates() so multi-segment phrases are checked
// the same way the real keyboard builds them.
//
// Usage:
//   node tools/ime-eval/run_coverage.js            # summary + missing list
//   node tools/ime-eval/run_coverage.js --rank     # also flag rank>0 (present but not first)
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json');
const GDICT = path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cov-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const showRank = process.argv.includes('--rank');
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  // Faithful port of KeyboardController.updateCandidates() candidate list.
  const candidatesFor = (composing) => {
    const fullKatakana = KanaKanjiConverter.toKatakana(composing);
    const segs = conv.segment(composing);
    let candidates;
    if (segs.length <= 1) {
      candidates = conv.lookup(composing);
    } else {
      const fullCands = conv.lookup(composing);
      const fullFirst = fullCands[0];
      const hasRealHit = fullFirst !== fullKatakana && fullFirst !== composing;
      if (hasRealHit) {
        candidates = fullCands;
      } else {
        const prefixParts = segs.slice(0, -1).map((s) => conv.autoConvert(s));
        const hasSymbolPrefix = prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p));
        const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
        const lastSeg = segs[segs.length - 1];
        const lastCands = conv.lookup(lastSeg);
        const segCands = hasSymbolPrefix ? [] : lastCands.map((c) => prefixText + c);
        candidates = [];
        if (hasSymbolPrefix) candidates.push(composing);
        else if (segCands.length > 0) candidates.push(segCands[0]);
        if (!candidates.includes(fullKatakana)) candidates.push(fullKatakana);
        for (let i = 1; i < segCands.length; i++) {
          if (!candidates.includes(segCands[i])) candidates.push(segCands[i]);
        }
        if (!candidates.includes(composing)) candidates.push(composing);
      }
    }
    return candidates;
  };

  const words = require('./reading_variants.js');
  const missing = [];
  const notFirst = [];
  for (const [reading, surface] of words) {
    const cands = candidatesFor(reading);
    const idx = cands.indexOf(surface);
    if (idx < 0) missing.push([reading, surface, cands.slice(0, 4)]);
    else if (idx > 0) notFirst.push([reading, surface, idx]);
  }
  const n = words.length;
  const present = n - missing.length;
  console.log(`[RVARIANT] present in candidates: ${present}/${n} (${(100 * present / n).toFixed(1)}%)`);
  console.log(`[RVARIANT] of those, at position 0: ${present - notFirst.length}/${present}`);
  if (missing.length) {
    console.log(`\n=== MISSING (word never appears — worst UX) ===`);
    for (const [r, s, top] of missing) {
      console.log(`  ${r} -> ${s}   [got: ${top.join(', ')}]`);
    }
  }
  if (showRank && notFirst.length) {
    console.log(`\n=== present but not first (rank shown) ===`);
    for (const [r, s, i] of notFirst) console.log(`  ${r} -> ${s}  @${i}`);
  }
}

main();
