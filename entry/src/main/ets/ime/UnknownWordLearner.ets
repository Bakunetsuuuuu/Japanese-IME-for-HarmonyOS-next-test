// 未知語学習 (unknown-word learning): notice when the user is assembling a word
// the converter cannot produce on its own, and after enough repetitions offer
// the assembled word as an ordinary conversion candidate.
//
// The two behaviours this watches for are the ones people actually fall back on
// when a word is missing from the dictionary:
//
//   1. PIECEWISE  - converting the word one fragment at a time (音 + 街 + ウナ)
//                   because the whole reading converts to nothing useful.
//   2. TRUNCATED  - converting a longer word that merely CONTAINS the wanted
//                   surface, then backspacing the extra characters off
//                   (かける → 翔ける → ⌫⌫ → 翔).
//
// Both leave the same trace: a run of consecutive commits, ending in a surface
// made only of content characters, whose joined reading the converter does not
// already map to the joined surface. That pair is counted, and once it has been
// re-assembled LEARN_THRESHOLD times it starts appearing as a candidate for its
// reading -- so a name/term the user keeps hand-building becomes a single tap
// from roughly the fifth time onward.
//
// Deliberately NOT linguistic: the reading learned is whatever the user actually
// typed to build the surface, not a dictionary-correct yomi. That is the point --
// it only ever has to match what the same user types the next time, so it stays
// self-consistent even for the truncated case (かける→翔), where no principled
// reading→surface split exists.
//
// Dependency-free (the dictionary check arrives as a callback, same idiom as
// PredictiveConversion taking the learning store as a parameter) so this module
// stays independently testable.

// Counted assemblies needed before a word is offered. The count reaches this on
// the Nth assembly, so the word first appears as a candidate on the N+1th time
// the reading is typed.
const LEARN_THRESHOLD = 4;

// Word-shape bounds for the joined result. A single-character surface is
// allowed on purpose: trimming a longer conversion down to one kanji (かける →
// 翔ける → 翔) is exactly the 単漢字 case this exists for, and such a run only
// reaches here when it was actually assembled (see `assembled` in flush), so an
// ordinary one-word commit still can't slip through. Above 8 chars the run is a
// phrase rather than a term.
const MIN_SURFACE_LEN = 1;
const MAX_SURFACE_LEN = 8;
// A one-kana reading is too ambiguous to hang a learned surface off.
const MIN_READING_LEN = 2;
const MAX_READING_LEN = 16;

// A run longer than this is someone typing a sentence in content fragments, not
// building one word -- discarded rather than learned.
const MAX_RUN_FRAGMENTS = 6;

const MAX_KEYS = 300;
const MAX_SURFACES_PER_KEY = 3;

// Resolves whether the converter can ALREADY produce `surface` for `reading`.
// Anything it can is by definition not an unknown word.
export type KnownWordFn = (reading: string, surface: string) => boolean;

interface Ranked {
  surface: string;
  count: number;
}

// [DEBUG-LOG] Notified when a run is judged to be an unknown word. Injected as
// a callback rather than imported so this module keeps its zero-dependency,
// independently-testable shape (tools/ime-eval/run_unknownword.js compiles it
// on its own) -- and so removing the debug build's collection means deleting
// the two [DEBUG-LOG] lines here, nothing else.
export type LearnedWordFn = (reading: string, surface: string) => void; // [DEBUG-LOG]

export class UnknownWordLearner {
  static onLearn: LearnedWordFn | undefined = undefined; // [DEBUG-LOG]

  // reading -> (surface -> times assembled)
  private static counts: Record<string, Record<string, number>> = {};

  // The run being accumulated: parallel readings/surfaces of the consecutive
  // commits seen so far, newest last.
  private static runReadings: string[] = [];
  private static runSurfaces: string[] = [];
  // Whether any fragment in the current run was backspace-truncated. A run of a
  // single fragment only qualifies when it was (signal 2 above); an untouched
  // one-word commit is just ordinary typing.
  private static runTruncated: boolean = false;

  static setLearned(data: Record<string, Record<string, number>>): void {
    UnknownWordLearner.counts = (data === undefined || data === null) ? {} : data;
  }

  static getLearned(): Record<string, Record<string, number>> {
    return UnknownWordLearner.counts;
  }

  // Kanji, katakana (incl. ー) and 々 -- the characters a word gets built out
  // of. Hiragana is excluded on purpose: an okurigana tail or a particle is
  // what separates words, so its presence means the fragment is not (yet)
  // word-building material.
  private static isContentOnly(s: string): boolean {
    if (s.length === 0) { return false; }
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      const kanji = c >= 0x4e00 && c <= 0x9fff;
      const katakana = c >= 0x30a1 && c <= 0x30fc;
      const iteration = c === 0x3005;
      if (!kanji && !katakana && !iteration) { return false; }
    }
    return true;
  }

  private static isAllHiragana(s: string): boolean {
    if (s.length === 0) { return false; }
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      const hira = c >= 0x3041 && c <= 0x309f;
      const choon = c === 0x30fc;
      if (!hira && !choon) { return false; }
    }
    return true;
  }

  private static clearRun(): void {
    UnknownWordLearner.runReadings = [];
    UnknownWordLearner.runSurfaces = [];
    UnknownWordLearner.runTruncated = false;
  }

  // Evaluate the accumulated run and count it if it looks like a word the
  // converter cannot already produce. Always leaves the run empty.
  private static flush(isKnown: KnownWordFn): void {
    const surfaces = UnknownWordLearner.runSurfaces;
    const readings = UnknownWordLearner.runReadings;
    const assembled = surfaces.length >= 2 || UnknownWordLearner.runTruncated;
    if (!assembled || surfaces.length === 0) {
      UnknownWordLearner.clearRun();
      return;
    }
    const surface = surfaces.join('');
    const reading = readings.join('');
    UnknownWordLearner.clearRun();

    if (surface.length < MIN_SURFACE_LEN || surface.length > MAX_SURFACE_LEN) { return; }
    if (reading.length < MIN_READING_LEN || reading.length > MAX_READING_LEN) { return; }
    if (!UnknownWordLearner.isAllHiragana(reading)) { return; }
    if (!UnknownWordLearner.isContentOnly(surface)) { return; }
    if (isKnown(reading, surface)) { return; }
    if (UnknownWordLearner.onLearn !== undefined) { UnknownWordLearner.onLearn(reading, surface); } // [DEBUG-LOG]
    UnknownWordLearner.bump(reading, surface);
  }

  private static bump(reading: string, surface: string): void {
    let entry = UnknownWordLearner.counts[reading];
    if (entry === undefined) {
      if (Object.keys(UnknownWordLearner.counts).length >= MAX_KEYS) {
        UnknownWordLearner.evictWeakestKey();
      }
      entry = {};
      UnknownWordLearner.counts[reading] = entry;
    }
    if (entry[surface] === undefined && Object.keys(entry).length >= MAX_SURFACES_PER_KEY) {
      // Keep the established spellings for this reading rather than letting a
      // one-off typo displace them.
      return;
    }
    entry[surface] = (entry[surface] ?? 0) + 1;
  }

  // Drop the reading whose best surface has been assembled least often, so a
  // full store keeps learning instead of freezing at the cap.
  private static evictWeakestKey(): void {
    const keys = Object.keys(UnknownWordLearner.counts);
    if (keys.length === 0) { return; }
    let weakest = keys[0];
    let weakestScore = Number.MAX_SAFE_INTEGER;
    for (const k of keys) {
      const entry = UnknownWordLearner.counts[k];
      let best = 0;
      for (const s of Object.keys(entry)) { if (entry[s] > best) { best = entry[s]; } }
      if (best < weakestScore) { weakestScore = best; weakest = k; }
    }
    const next: Record<string, Record<string, number>> = {};
    for (const k of keys) { if (k !== weakest) { next[k] = UnknownWordLearner.counts[k]; } }
    UnknownWordLearner.counts = next;
  }

  // Record one committed conversion. Fragments accumulate into the current run;
  // the run is only judged once the NEXT commit (or an explicit boundary)
  // proves no further backspace is going to truncate its tail -- without that
  // delay the truncated case (翔ける, still hiragana-tailed at commit time)
  // would be rejected before its ⌫ ever arrived.
  static observe(reading: string, surface: string, isKnown: KnownWordFn): void {
    if (reading.length === 0 || surface.length === 0) {
      UnknownWordLearner.flush(isKnown);
      return;
    }
    UnknownWordLearner.settleTail(isKnown);
    UnknownWordLearner.runReadings.push(reading);
    UnknownWordLearner.runSurfaces.push(surface);
    if (UnknownWordLearner.runSurfaces.length > MAX_RUN_FRAGMENTS) {
      UnknownWordLearner.clearRun();
    }
  }

  // Judge the settled tail: a fragment that still carries hiragana is a word
  // boundary, so the run up to it is flushed and the tail itself discarded.
  private static settleTail(isKnown: KnownWordFn): void {
    const surfaces = UnknownWordLearner.runSurfaces;
    if (surfaces.length === 0) { return; }
    if (UnknownWordLearner.isContentOnly(surfaces[surfaces.length - 1])) { return; }
    UnknownWordLearner.runSurfaces = surfaces.slice(0, -1);
    UnknownWordLearner.runReadings = UnknownWordLearner.runReadings.slice(0, -1);
    UnknownWordLearner.flush(isKnown);
  }

  // A backspace deleted one character of already-committed text. While that
  // text is still the tail of the current run, shorten the run's tail to match
  // -- this is what turns 翔ける into the 翔 the user actually wanted. Returns
  // false (and drops the run) once the deletion eats past the run itself, since
  // the text being edited is then no longer what was just built.
  static truncate(): boolean {
    const surfaces = UnknownWordLearner.runSurfaces;
    if (surfaces.length === 0) { return false; }
    const tail = surfaces[surfaces.length - 1];
    if (tail.length <= 1) {
      // The whole fragment is gone: the run can't describe the text any more.
      UnknownWordLearner.clearRun();
      return false;
    }
    UnknownWordLearner.runSurfaces = surfaces.slice(0, -1);
    UnknownWordLearner.runSurfaces.push(tail.slice(0, -1));
    UnknownWordLearner.runTruncated = true;
    return true;
  }

  // Explicit run boundary (sentence end, field change, non-conversion commit).
  static endRun(isKnown: KnownWordFn): void {
    UnknownWordLearner.settleTail(isKnown);
    UnknownWordLearner.flush(isKnown);
  }

  // Erase an assembled word. Used when the user deletes the candidate: without
  // this the assembly count would survive the deletion and re-offer the word
  // immediately. Rebuilds rather than using `delete`, matching the codebase.
  static forget(reading: string, surface: string): void {
    const entry = UnknownWordLearner.counts[reading];
    if (entry === undefined || entry[surface] === undefined) { return; }
    const next: Record<string, number> = {};
    for (const s of Object.keys(entry)) {
      if (s !== surface) { next[s] = entry[s]; }
    }
    if (Object.keys(next).length > 0) {
      UnknownWordLearner.counts[reading] = next;
      return;
    }
    const remaining: Record<string, Record<string, number>> = {};
    for (const r of Object.keys(UnknownWordLearner.counts)) {
      if (r !== reading) { remaining[r] = UnknownWordLearner.counts[r]; }
    }
    UnknownWordLearner.counts = remaining;
  }

  // Learned words for exactly this reading, most-assembled first. Empty until a
  // word has cleared LEARN_THRESHOLD.
  static candidates(reading: string): string[] {
    const entry = UnknownWordLearner.counts[reading];
    if (entry === undefined) { return []; }
    const ranked: Ranked[] = [];
    for (const s of Object.keys(entry)) {
      if (entry[s] >= LEARN_THRESHOLD) { ranked.push({ surface: s, count: entry[s] }); }
    }
    ranked.sort((a: Ranked, b: Ranked) => b.count - a.count);
    return ranked.map((r: Ranked) => r.surface);
  }
}
