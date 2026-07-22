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
    const kIdx = candidates.indexOf(fullKatakana), cIdx = candidates.indexOf(composing);
    let insertAt;
    if (kIdx < 0 && cIdx < 0) insertAt = candidates.length;
    else if (kIdx < 0) insertAt = cIdx; else if (cIdx < 0) insertAt = kIdx; else insertAt = Math.min(kIdx, cIdx);
    for (const a of alts) { if (!candidates.includes(a)) { candidates.splice(insertAt, 0, a); insertAt++; } }
    const altSeg = conv.findAlternateSegmentation(composing);
    if (altSeg !== null && !candidates.includes(altSeg)) candidates.splice(insertAt, 0, altSeg);
    return candidates;
  };

  // Each case: `want` (the intended reading when candidate[0] is something
  // else) must appear within the TOP_N candidates a user sees before
  // scrolling, at position >= 1 (it's the *alternative*). TOP_N=4 = positions
  // 0-3, i.e. the desired word must be reachable in the first two or three
  // taps -- the practical bar: "if the first guess is wrong, the word I want
  // is right there." Round-robin per-segment alternatives make this hold
  // whichever single word is ambiguous.
  const TOP_N = 4;
  const cases = [
    { reading: 'はしをわたる', want: '橋を渡る' },
    { reading: 'しゃしんをとった', want: '写真を取った' },
    { reading: 'あめがふってきた', want: '飴が降ってきた' },
    { reading: 'せんせいにあう', want: '先生に合う' },
    { reading: 'かれとはなす', want: '彼と離す' },
    { reading: 'きをつかう', want: '気を遣う' },
    { reading: 'じかんをとる', want: '時間を取る' },
    { reading: 'はなをみる', want: '花を見る' },
    { reading: 'はやくなおす', want: '早く治す' },
    // Content verbs the base parse keeps as kana (でる/かつ/くる/うむ) must still
    // surface their kanji as an alternative -- these were ABSENT entirely before
    // the isCitationFormAlt path let a kana-kept segment contribute its
    // plain-form verb kanji (出る/勝つ/来る/産む) without leaking particle
    // homographs (は→歯, なら→成ら).
    { reading: 'しあいにでる', want: '試合に出る' },
    { reading: 'あいてにかつ', want: '相手に勝つ' },
    { reading: 'よあけがくる', want: '夜明けが来る' },
    { reading: 'たまごをうむ', want: '卵を産む' },
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
