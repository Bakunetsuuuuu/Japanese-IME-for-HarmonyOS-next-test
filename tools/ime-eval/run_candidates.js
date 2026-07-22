#!/usr/bin/env node
// 2nd/3rd-candidate usefulness test. The corpus scripts only grade candidate[0];
// this checks that positions 1+ actually offer the useful homophone/parse
// alternatives a user reaches for when position 0 isn't what they meant --
// 橋を渡る for はしをわたる (which leads 箸を渡る), 写真を取った for
// しゃしんをとった (leads 写真を撮った), etc. Ports KeyboardController.
// updateCandidates including the sentenceAlternatives injection.
//
// Usage: node tools/ime-eval/run_candidates.js [--show]
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets');
const DICT = path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json');
const GDICT = path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json');

function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'imecand-'));
  const tsPath = path.join(tmp, 'KKC.ts');
  fs.writeFileSync(tsPath, '// @ts-nocheck\n' + fs.readFileSync(SRC, 'utf-8'));
  execFileSync('npx', ['tsc', '--target', 'ES2020', '--module', 'CommonJS',
    '--skipLibCheck', tsPath], { stdio: 'inherit' });
  return path.join(tmp, 'KKC.js');
}

function main() {
  const show = process.argv.includes('--show');
  const { KanaKanjiConverter } = require(build());
  KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(DICT, 'utf-8')));
  KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(GDICT, 'utf-8')));
  KanaKanjiConverter.initConnectionMatrix();
  const conv = new KanaKanjiConverter();

  // Faithful port of KeyboardController.updateCandidates() (custom engine).
  const candidatesFor = (composing) => {
    const fullKatakana = KanaKanjiConverter.toKatakana(composing);
    const segs = conv.segment(composing);
    let candidates;
    if (segs.length <= 1) {
      candidates = conv.lookup(composing);
    } else {
      const fullCands = conv.lookup(composing);
      const fullFirst = fullCands[0];
      const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== composing) || KanaKanjiConverter.isDictionaryWord(composing);
      if (hasRealHit) {
        candidates = fullCands;
      } else {
        const prefixParts = segs.slice(0, -1).map((s, i) => conv.autoConvert(s, segs[i + 1], segs[i - 1]));
        const hasSymbolPrefix = prefixParts.some((p) => KanaKanjiConverter.isSymbolOnly(p));
        const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
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
    const alts = conv.sentenceAlternatives(composing);
    let insertAt = 1;
    for (const a of alts) { if (!candidates.includes(a)) { candidates.splice(insertAt, 0, a); insertAt++; } }
    const altSeg = conv.findAlternateSegmentation(composing);
    if (altSeg !== null && !candidates.includes(altSeg)) candidates.splice(insertAt, 0, altSeg);
    return candidates;
  };

  // Each case: `want` must appear somewhere in positions 1..topN (NOT at 0 --
  // it's the *alternative*, position 0 is something else). topN=5 = the row of
  // candidates a user sees before scrolling.
  const TOP_N = 6;
  const cases = [
    { reading: 'はしをわたる', want: '橋を渡る' },
    { reading: 'しゃしんをとった', want: '写真を取った' },
    { reading: 'あめがふってきた', want: '飴が降ってきた' },
    { reading: 'せんせいにあう', want: '先生に合う' },
    { reading: 'かれとはなす', want: '彼と離す' },
  ];

  let pass = 0;
  for (const c of cases) {
    const list = candidatesFor(c.reading);
    const idx = list.indexOf(c.want);
    const ok = idx >= 1 && idx < TOP_N;
    if (ok) pass++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.reading}: "${c.want}" @${idx < 0 ? '(absent)' : idx}`);
    if (show || !ok) console.log(`      [${list.slice(0, TOP_N).join(' | ')}]`);
  }
  console.log(`\n[CANDIDATES] ${pass}/${cases.length} useful-alternative cases pass`);
  if (pass !== cases.length) process.exit(1);
}

main();
