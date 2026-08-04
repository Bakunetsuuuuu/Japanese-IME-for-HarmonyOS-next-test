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
const DICT = path.join(ROOT, 'tools/dict_src/dict.json');
const GDICT = path.join(ROOT, 'tools/dict_src/global_dict.json');

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
    // 区切り違いの候補は、先頭よりかなが少ないとき(区切りを直すと漢字に
    // できるとき)だけ候補1に入れる。KeyboardController と同じ規則。
    const altSeg = conv.findAlternateSegmentation(composing);
    if (altSeg !== null && !candidates.includes(altSeg)) {
      const kanaCount = (t) => (t.match(/[\u3041-\u309F]/g) || []).length;
      const lifts = candidates.length > 0 && kanaCount(altSeg) < kanaCount(candidates[0]);
      candidates.splice(lifts ? 1 : insertAt, 0, altSeg);
    }
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
    // はしをわたる was here asserting 橋を渡る as the ALTERNATIVE, back when
    // candidate[0] was 箸を渡る. applyInSentenceHints now resolves はし with
    // the rest of the phrase (渡 is a listed trigger for はし|橋), so 橋を渡る
    // is the DEFAULT and there is no alternative left to test -- 箸を渡る isn't
    // even offered (the 箸 branch degenerates to 箸を亘/箸を亙). Dropped rather
    // than re-pointed: the case now belongs to the corpus scripts, which grade
    // candidate[0], not to this position-1+ test.
    // 送り仮名を持たない裸漢字の後退(demoteOkuriganaLessKanji)で初めて上位に
    // 来た候補。以前の のる は 乗る|乗|乘|培|宣|搭|載|駕|騎 と、読みを表せない
    // 裸漢字が並んで 載る が候補列に存在すらしなかった。
    { reading: 'のる', want: '載る' },
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
    // しあいにでる は「格助詞の直後の でる は 出る」という規則が入って候補0に
    // なったので、候補0を採点する corpus3 側へ移した。
    { reading: 'あいてにかつ', want: '相手に勝つ' },
    { reading: 'よあけがくる', want: '夜明けが来る' },
    { reading: 'たまごをうむ', want: '卵を産む' },
    // Real dictionary-coverage gaps: dict.json had these surfaces buried past a
    // wall of obscure single-kanji entries (帰す/推す/傷む/務める were present
    // but at position 10+), so they never reached the in-code DICTIONARY's
    // curated list at all -- adding them there (candidate[0] unchanged, they
    // were appended after the existing head) makes them reachable.
    { reading: 'こどもをかえす', want: '子供を帰す' },
    { reading: 'こうほをおす', want: '候補を推す' },
    { reading: 'やさいがいたむ', want: '野菜が傷む' },
    // はる's DICTIONARY entry was just ['春'] -- 張る/貼る (extremely common verbs,
    // "貼り紙を貼る"/"ポスターを貼る") were unreachable at any position. Added as
    // alternatives (candidate[0]='春' kept: はる alone, out of context, is a
    // genuine toss-up between the season and the verb, unlike あたる/与える which
    // was an outright reading bug -- see corpus.js's TRAIN addition for that one).
    { reading: 'ポスターをはる', want: 'ポスターを貼る' },
    // 務める itself was added too (see DICTIONARY['つとめる']) and is a real
    // improvement (ぎむをつとめる went from fully ABSENT to reachable), but not
    // locked here: the OTHER segment (ぎむ) has its own rare-homophone
    // alternative (蟻夢) that consumes a round-robin slot ahead of it, landing
    // 義務を務める at position 4 rather than within this file's strict top-4 --
    // a separate round-robin-dilution issue, not a dictionary gap.
    // Verb-sense entries whose common readings were buried under obscure single
    // kanji (税金を乂/乱 was the alternative!) -- added the okurigana senses to
    // DICTIONARY (candidate[0] kept: 修める/変わる stay the default), surfacing
    // the intended sense as a reachable alternative.
    { reading: 'ぜいきんをおさめる', want: '税金を納める' },
    { reading: 'やくいんがかわる', want: '役員が代わる' },
    // 区切り違いの候補(自動区切り変更)は候補1に出す。はいじんじゃ は
    // 廃人じゃ の同音語が先に並んで 廃神社 が5番目に埋もれていた。
    { reading: 'はいじんじゃ', want: '廃神社' },
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
