#!/usr/bin/env node
// Segment-level ("文節") learning test. The ordinary whole-sentence commit
// path (KeyboardController.commitCandidate / commitTopCandidate) learns each
// segment of an accepted multi-segment candidate individually, not just the
// entire reading→surface pair, so a homophone correction generalizes
// word-by-word to later sentences (correcting しゃしんをとった→写真を撮った
// teaches とった→撮った everywhere). This script ports updateCandidates'
// candidate[0] construction + learnCommit and asserts that teaching a word
// via one sentence changes a DIFFERENT sentence's top candidate.
//
// Usage: node tools/ime-eval/run_learning.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imelearn-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  // Faithful port of KeyboardController.updateCandidates(): returns the
  // candidate list plus the ComposeAlignment learnCommit would capture.
  const build1 = (composing) => {
    const fullKatakana = KanaKanjiConverter.toKatakana(composing);
    const segs = conv.segment(composing);
    let candidates;
    let alignment = undefined;
    if (segs.length <= 1) {
      candidates = conv.lookup(composing);
    } else {
      const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
      const hasSymbolPrefix = prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p));
      const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
      if (!hasSymbolPrefix) alignment = { segs, prefixSurfaces: prefixParts, prefixText };
      const fullCands = conv.lookup(composing);
      const fullFirst = fullCands[0];
      const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== composing) || KanaKanjiConverter.isDictionaryWord(composing);
      if (hasRealHit) {
        candidates = fullCands;
      } else {
        const lastSeg = segs[segs.length - 1];
        const lastCands = conv.lookup(lastSeg);
        const segCands = hasSymbolPrefix ? [] : lastCands.map((c) => prefixText + c);
        candidates = [];
        if (hasSymbolPrefix) candidates.push(composing);
        else if (segCands.length > 0) candidates.push(segCands[0]);
        if (!candidates.includes(fullKatakana)) candidates.push(fullKatakana);
        for (let i = 1; i < segCands.length; i++) if (!candidates.includes(segCands[i])) candidates.push(segCands[i]);
        if (!candidates.includes(composing)) candidates.push(composing);
      }
    }
    return { candidates, alignment };
  };
  const top = (c) => build1(c).candidates[0];
  // Port of KeyboardController.learnCommit.
  const commit = (composing, text) => {
    const a = build1(composing).alignment;
    if (a && text.length > a.prefixText.length && text.startsWith(a.prefixText)) {
      const lastSurface = text.slice(a.prefixText.length);
      const surfaces = a.prefixSurfaces.slice();
      surfaces.push(lastSurface);
      KanaKanjiConverter.recordSegmentedChoice(a.segs, surfaces);
    } else {
      KanaKanjiConverter.recordChoice(composing, text);
    }
  };

  // Each case: teach a word by committing `teachReading -> teachSurface`,
  // then assert a DIFFERENT sentence's top candidate now uses the learned
  // surface. `beforeNot` guards that the change is actually due to learning
  // (the generalize sentence did NOT already produce the surface by default).
  const cases = [
    { teachR: 'きれいにとった', teachS: 'きれいに撮った', genR: 'はやくとった', wantContains: '撮った', beforeNot: '撮った' },
    { teachR: 'よていをかえる', teachS: '予定を変える', genR: 'すぐにかえる', wantContains: '変える', beforeNot: '変える' },
  ];

  let pass = 0;
  for (const c of cases) {
    KanaKanjiConverter.setLearned({});
    const before = top(c.genR);
    const beforeOk = !before.includes(c.beforeNot); // must NOT already contain it
    commit(c.teachR, c.teachS);
    const after = top(c.genR);
    const afterOk = after.includes(c.wantContains);
    const ok = beforeOk && afterOk;
    if (ok) pass++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  teach "${c.teachR}"→"${c.teachS}"  then  ${c.genR}: ${before} → ${after}`);
    if (!beforeOk) console.log(`      (baseline already contained "${c.beforeNot}" — case no longer isolates learning)`);
  }
  console.log(`\n[LEARNING] ${pass}/${cases.length} segment-learning generalization cases pass`);
  if (pass !== cases.length) process.exit(1);
}

main();
