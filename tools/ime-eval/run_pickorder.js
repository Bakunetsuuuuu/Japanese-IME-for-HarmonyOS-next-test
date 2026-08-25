#!/usr/bin/env node
// "Pick a candidate repeatedly and it moves to the top" test.
//
// run_learning.js covers the other half of conversion learning (a correction
// GENERALIZING to a different sentence). This one covers the half users
// actually notice: picking a candidate for a reading should promote it the
// next time that same reading is typed.
//
// The interesting cases are the candidates updateCandidates INJECTS after
// lookup() has returned -- per-segment sentence alternatives, the alternate
// segmentation, learned unknown words. Learning used to be applied only inside
// lookup(), so those entries could never be promoted no matter how often they
// were picked, which is exactly when a user reaches past candidate 0. The
// promotion now happens over the finished list (applyLearnedOrder), so this
// script ports updateCandidates' full candidate construction, not just [0].
//
// Usage: node tools/ime-eval/run_pickorder.js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');
const MODULES = ['KanaKanjiConverter', 'PredictivePhrases', 'PredictiveConversion',
  'DateTimePredictor', 'NumberFormatter'];

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pickorder-'));
  const outs = [];
  for (const m of MODULES) {
    const ts = path.join(tmp, `${m}.ts`);
    fs.writeFileSync(ts, '// @ts-nocheck\n' +
      fs.readFileSync(path.join(ROOT, `entry/src/main/ets/ime/${m}.ets`), 'utf-8'));
    outs.push(ts);
  }
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', ...outs], { stdio: 'inherit', shell: true });
  return (m) => require(path.join(tmp, `${m}.js`));
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
  const load = build();
  const { KanaKanjiConverter } = load('KanaKanjiConverter');
  const { findPredictiveCompletion } = load('PredictivePhrases');
  const { PredictiveConversion } = load('PredictiveConversion');
  const { DateTimePredictor } = load('DateTimePredictor');
  const { NumberFormatter } = load('NumberFormatter');
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  let lastAlignment;
  // Faithful port of KeyboardController.updateCandidates' candidate list.
  const updateCandidates = (target) => {
    lastAlignment = undefined;
    const fullKatakana = KanaKanjiConverter.toKatakana(target);
    const segs = conv.segment(target);
    let candidates;
    if (segs.length <= 1) {
      candidates = conv.lookup(target);
    } else {
      const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
      const hasSymbolPrefix = prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p));
      const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
      if (!hasSymbolPrefix) lastAlignment = { segs, prefixSurfaces: prefixParts, prefixText };
      const fullCands = conv.lookup(target);
      const fullFirst = fullCands[0];
      const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== target) ||
        KanaKanjiConverter.isDictionaryWord(target);
      if (hasRealHit) {
        candidates = fullCands;
      } else {
        const lastSeg = segs[segs.length - 1];
        let lastCands = conv.lookup(lastSeg);
        const forcedLead = KanaKanjiConverter.contextLead(lastSeg, prefixText);
        if (forcedLead !== null && lastCands.length > 0 && lastCands[0] !== forcedLead) {
          lastCands = [forcedLead, ...lastCands.filter((c) => c !== forcedLead)];
        }
        const segCands = hasSymbolPrefix ? [] : lastCands.map((c) => prefixText + c);
        candidates = [];
        if (hasSymbolPrefix) candidates.push(target);
        else if (segCands.length > 0) candidates.push(segCands[0]);
        if (!candidates.includes(fullKatakana)) candidates.push(fullKatakana);
        for (let i = 1; i < segCands.length; i++) {
          if (!candidates.includes(segCands[i])) candidates.push(segCands[i]);
        }
        if (!candidates.includes(target)) candidates.push(target);
      }
    }
    const alts = conv.sentenceAlternatives(target);
    const kIdx = candidates.indexOf(fullKatakana);
    const cIdx = candidates.indexOf(target);
    let insertAt;
    if (kIdx < 0 && cIdx < 0) insertAt = candidates.length;
    else if (kIdx < 0) insertAt = cIdx;
    else if (cIdx < 0) insertAt = kIdx;
    else insertAt = Math.min(kIdx, cIdx);
    for (const a of alts) if (!candidates.includes(a)) { candidates.splice(insertAt, 0, a); insertAt++; }
    const altSeg = conv.findAlternateSegmentation(target);
    if (altSeg !== null && !candidates.includes(altSeg)) candidates.splice(insertAt, 0, altSeg);
    const predictive = findPredictiveCompletion(target);
    if (predictive !== null && !candidates.includes(predictive)) candidates = [predictive, ...candidates];
    let insAt = candidates.length > 0 ? 1 : 0;
    for (const d of DateTimePredictor.predict(target, new Date())) {
      if (!candidates.includes(d)) { candidates.splice(insAt, 0, d); insAt++; }
    }
    for (const c of PredictiveConversion.predict(target, KanaKanjiConverter.getLearned())) {
      if (!candidates.includes(c)) { candidates.splice(insAt, 0, c); insAt++; }
    }
    for (const nf of NumberFormatter.predict(target)) {
      if (!candidates.includes(nf)) { candidates.splice(insAt, 0, nf); insAt++; }
    }
    return KanaKanjiConverter.applyLearnedOrder(target, candidates);
  };

  // Port of KeyboardController.learnCommit.
  const MAX_WHOLE_LEARN_LEN = 12;
  const learnCommit = (reading, text) => {
    const a = lastAlignment;
    if (a !== undefined && text.length > a.prefixText.length && text.startsWith(a.prefixText)) {
      const surfaces = a.prefixSurfaces.slice();
      surfaces.push(text.slice(a.prefixText.length));
      KanaKanjiConverter.recordSegmentedChoice(a.segs, surfaces);
      if (reading.length <= MAX_WHOLE_LEARN_LEN) KanaKanjiConverter.recordChoice(reading, text);
    } else {
      KanaKanjiConverter.recordChoice(reading, text);
    }
  };

  // Pick `pick` once for `reading`, then report where it sits next time.
  const pickOnce = (reading, pick) => {
    const before = updateCandidates(reading);
    const startIdx = before.indexOf(pick);
    if (startIdx < 0) return { startIdx, afterIdx: -1 };
    learnCommit(reading, pick);
    return { startIdx, afterIdx: updateCandidates(reading).indexOf(pick) };
  };

  const promotes = (label, reading, pick) => {
    KanaKanjiConverter.setLearned({});
    const r = pickOnce(reading, pick);
    check(`${label}: ${reading} 「${pick}」`, r.startIdx > 0 && r.afterIdx === 0,
      `offered at ${r.startIdx}, after one pick at ${r.afterIdx}`);
  };

  // --- a plain lookup() candidate (this always worked) ---
  // かみ の既定は 紙 になったので、既定でない候補を選ぶ形に直した。
  promotes('lookup候補', 'かみ', '髪');
  promotes('lookup候補', 'きかい', '機会');
  promotes('lookup候補(下位)', 'こうしん', '行進');

  // --- candidates INJECTED after lookup(): the case that used to never work ---
  // 写真を取った is produced by sentenceAlternatives, not by
  // lookup('しゃしんをとった'), so learning had nothing to reorder.
  promotes('文内代替候補', 'しゃしんをとった', '写真を取った');
  promotes('文内代替候補', 'はなをみる', '花を見る');
  // 返還制度 comes from findAlternateSegmentation.
  promotes('別分割候補', 'へんかんせいど', '返還制度');

  // --- a promoted pick must stay promoted, not decay ---
  KanaKanjiConverter.setLearned({});
  pickOnce('しゃしんをとった', '写真を取った');
  let stable = true;
  for (let i = 0; i < 5; i++) {
    if (updateCandidates('しゃしんをとった')[0] !== '写真を取った') stable = false;
  }
  check('一度上がった候補は繰り返し表示しても先頭のまま', stable);

  // --- learning must not disturb a reading it knows nothing about ---
  KanaKanjiConverter.setLearned({});
  const untouched = updateCandidates('あめがふる').join('|');
  KanaKanjiConverter.recordChoice('しゃしんをとった', '写真を取った');
  check('無関係な読みの候補順は変わらない',
    updateCandidates('あめがふる').join('|') === untouched);

  // --- the store must keep learning once it is full ---
  KanaKanjiConverter.setLearned({});
  for (let i = 0; i < 500; i++) KanaKanjiConverter.recordChoice(`よみ${i}`, `語${i}`);
  const atCap = Object.keys(KanaKanjiConverter.getLearned()).length;
  KanaKanjiConverter.recordChoice('あたらしいよみ', '新しい語');
  const learned = KanaKanjiConverter.getLearned();
  check('上限に達しても新しい語を学習できる',
    learned['あたらしいよみ'] !== undefined,
    `at cap: ${atCap}, after: ${Object.keys(learned).length}`);
  check('上限を超えて増え続けない', Object.keys(learned).length <= 500,
    `${Object.keys(learned).length}`);

  console.log(failures === 0 ? '\n[PICKORDER] ALL PASS' : `\n[PICKORDER] ${failures} FAILURE(S)`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
