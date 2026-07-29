#!/usr/bin/env node
// Turn the fetched Tatoeba data into [reading, goldSurface] pairs -- the same
// shape as the hand-written corpus*.js files, but from real sentences written
// by real people instead of authored for this repo.
//
// The hard part is recovering the KANA the user would type. jpn_indices.csv
// annotates each token as  headword(reading)[sense]{written}, but the reading
// is only given ~20% of the time, so it is reconstructed like this:
//
//   written is all kana          -> the reading is the written form itself
//   explicit (reading) present   -> use it, after checking it fits `written`
//   otherwise                    -> invert the bundled dict.json (reading ->
//                                   surfaces) and accept ONLY when the written
//                                   form has exactly one reading
//
// and for inflected tokens the headword's reading has its kana tail swapped for
// the written form's (愛する/あいする + 愛してる -> あいしてる).
//
// Everything that cannot be resolved with confidence is dropped, because a
// wrong gold is worse than a missing one: it invents bugs and sends you fixing
// things that were already right. Two guards do most of that work:
//
//   * The reconstruction is compared against the OFFICIAL sentence text. The
//     annotation sometimes omits tokens, which silently produced golds like
//     「ページの英語を訳すのに時間以上もかかりました」(a missing 一). ~5k
//     sentences fail this and are dropped.
//   * Anything built on 来る is dropped outright. It is カ変 (来る=くる but
//     来て=きて), so the kana-tail swap above produces くて/くられ -- which then
//     showed up as spurious "bugs" (来て→湫, に来られ→肉られ) that were purely
//     artifacts of this script.
//
// Usage: node tools/ime-eval/build_real_corpus.js
//        (writes cache_real/real_corpus.json)
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const CACHE = path.join(__dirname, 'cache_real');
const OUT = path.join(CACHE, 'real_corpus.json');

const MIN_LEN = 4;
const MAX_LEN = 28;

function main() {
  const dict = JSON.parse(fs.readFileSync(path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json'), 'utf-8'));
  const inverse = new Map();
  for (const reading of Object.keys(dict)) {
    if (!/^[ぁ-んー]+$/.test(reading)) { continue; }
    for (const surface of dict[reading]) {
      let set = inverse.get(surface);
      if (!set) { set = new Set(); inverse.set(surface, set); }
      set.add(reading);
    }
  }
  const isKana = (s) => /^[ぁ-んァ-ヶーっ]+$/.test(s);
  const kanaTail = (w) => { const m = /[ぁ-んァ-ヶー]+$/.exec(w); return m ? m[0] : ''; };
  const uniqueReading = (w) => { const v = inverse.get(w); return (v && v.size === 1) ? [...v][0] : null; };

  // 来る family: see the header. Never reconstructable by tail-swapping.
  const resolve = (head, explicit, written) => {
    if (isKana(written)) { return written; }
    if (/^来/.test(written)) { return null; }
    const headReading = explicit || uniqueReading(head);
    if (!headReading) { return null; }
    const tail = kanaTail(head);
    if (tail && !headReading.endsWith(tail)) { return null; }
    const stem = tail ? headReading.slice(0, headReading.length - tail.length) : headReading;
    const kanjiPart = tail ? head.slice(0, head.length - tail.length) : head;
    if (!written.startsWith(kanjiPart)) { return null; }
    const wTail = written.slice(kanjiPart.length);
    if (wTail && !isKana(wTail)) { return null; }
    const out = stem + wTail;
    return /^[ぁ-んァ-ヶー]+$/.test(out) ? out : null;
  };

  const official = new Map();
  for (const line of fs.readFileSync(path.join(CACHE, 'jpn_sentences.tsv'), 'utf-8').split('\n')) {
    const p = line.split('\t');
    if (p.length >= 3) { official.set(p[0], p[2]); }
  }
  const strip = (t) => t.replace(/[。、！？!?,.\s「」『』（）()・…ー~〜]/g, '');
  const TOKEN = /^([^(\[{~|]+)(?:\(([^)]*)\))?(?:\[[^\]]*\])?(?:\{([^}]*)\})?~?$/;

  const rows = [];
  const seen = new Set();
  let unresolved = 0, mismatch = 0;
  for (const line of fs.readFileSync(path.join(CACHE, 'jpn_indices.csv'), 'utf-8').split('\n')) {
    const parts = line.split('\t');
    const annotated = parts[2];
    if (!annotated) { continue; }
    const sentence = official.get(parts[0]);
    if (!sentence) { continue; }
    let reading = '', surface = '', ok = true;
    for (const tok of annotated.split(' ')) {
      if (!tok) { continue; }
      const m = TOKEN.exec(tok);
      if (!m) { ok = false; break; }
      const written = m[3] !== undefined ? m[3] : m[1];
      const r = resolve(m[1], m[2], written);
      if (r === null) { ok = false; break; }
      reading += r; surface += written;
    }
    if (!ok) { unresolved++; continue; }
    if (reading.length < MIN_LEN || reading.length > MAX_LEN) { continue; }
    if (!/^[ぁ-んァ-ヶー]+$/.test(reading)) { continue; }
    if (strip(surface) !== strip(sentence)) { mismatch++; continue; }
    // A katakana word is typed in hiragana, so that is the real input.
    reading = reading.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));
    const key = reading + '|' + surface;
    if (seen.has(key)) { continue; }
    seen.add(key);
    rows.push([reading, surface]);
  }
  fs.writeFileSync(OUT, JSON.stringify(rows));
  console.log(`usable ${rows.length}  (dropped: ${unresolved} unresolvable, ${mismatch} not matching the official sentence)`);
  console.log(`wrote ${path.relative(ROOT, OUT)}`);
}

main();
