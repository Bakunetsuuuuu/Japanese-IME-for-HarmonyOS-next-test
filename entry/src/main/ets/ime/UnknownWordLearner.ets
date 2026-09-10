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
// 2 にしてある (以前は 4)。手で組み立て直している時点でユーザーはもう
// 「変換できない語」だと分かっていて、5回目まで待たされるのは長い。誤って
// 覚えた場合は候補の長押しで消せる (SuppressedCandidates) ので、早めに出して
// 外れを消してもらう方が体感が良い。テストが追従できるよう公開している。
export const LEARN_THRESHOLD = 2;

// Word-shape bounds for the joined result. A single-character surface is
// allowed on purpose: trimming a longer conversion down to one kanji (かける →
// 翔ける → 翔) is exactly the 単漢字 case this exists for, and such a run only
// reaches here when it was actually assembled (see `assembled` in flush), so an
// ordinary one-word commit still can't slip through. Above 8 chars the run is a
// phrase rather than a term.
const MIN_SURFACE_LEN = 1;
export const MAX_SURFACE_LEN = 12;
// A one-kana reading is too ambiguous to hang a learned surface off.
const MIN_READING_LEN = 2;
const MAX_READING_LEN = 16;

// A run longer than this is someone typing a sentence in content fragments, not
// building one word -- discarded rather than learned.
export const MAX_RUN_FRAGMENTS = 8;

export const MAX_KEYS = 2000;
const MAX_SURFACES_PER_KEY = 4;

// Resolves whether the converter can ALREADY produce `surface` for `reading`.
// Anything it can is by definition not an unknown word.
export type KnownWordFn = (reading: string, surface: string) => boolean;

interface Ranked {
  surface: string;
  count: number;
}


// 組み立てた語が isKnown() 的には「もう変換できる」語だった (辞書のどこかに
// ある) ときに呼ばれる。呼び出し側 (KeyboardController) はこれを
// KanaKanjiConverter.recordChoice(reading, surface) に繋いで、通常の
// 学習ブーストにかける。
//
// 「志岐」(しき) のような、辞書には存在するが読み全体で一発では出てこない
// くらい埋もれている語がここに当てはまる。この語を「し」「き」で分けて
// 単漢字ずつ組み立てる打ち方を続けている限り、UnknownWordLearner は
// isKnown()=true で毎回黙って捨て (「もう変換できるので未知語ではない」
// という判定自体は正しい)、かつ recordChoice も「しき」をひとつの読みと
// して一度も打っていないので一切呼ばれず、埋もれたままいつまでも学習
// されない、という穴があった。
export type KnownAssemblyFn = (reading: string, surface: string) => void;

export class UnknownWordLearner {
  static onKnownAssembly: KnownAssemblyFn | undefined = undefined;

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

  // 3つ目の信号: ABANDONED - ひらがなで読みを最後まで打って、変換候補を見た
  // (リアルタイム候補表示は常時出ているので、これは打っている間ずっと起きて
  // いる)のに、変換せず全部消して諦めた読み。この直後に同じ読みが手作業で
  // 組み立て直されたら、「辞書にこの語がないと分かって、自分で組み立てた」
  // という一番強い合図なので、1回の再現だけで即しきい値まで進める。
  // 一度きりの合図なので、次に flush() が起きたら (一致してもしなくても)
  // 必ず消す。
  private static abandonedReading: string = '';

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
    if (isKnown(reading, surface)) {
      // 未知語ではないが、単漢字ずつ組み立て直しているという行動自体が
      // 「読み全体で一発では出てこないくらい埋もれている」ことの合図。
      // 通常の学習ブースト (KanaKanjiConverter.recordChoice) に回す。
      if (UnknownWordLearner.onKnownAssembly !== undefined) {
        UnknownWordLearner.onKnownAssembly(reading, surface);
      }
      return;
    }
    // ABANDONED との一致判定。一度きりの合図なので判定した時点で必ず消す
    // (一致しなかった場合も、もう別の語に対する古い合図でしかないため)。
    // 強い合図ではあるが、いきなり本採用まで飛ばすと外れたときに目立つ位置に
    // 出てしまう。1回目は他の組み立てと同じ扱いで準候補どまりにし、本人が
    // 準候補欄からもう一度タップして初めて本採用にする (confirmQuasi 参照)。
    // confirmed はログ用にだけ残す。
    const confirmed = reading === UnknownWordLearner.abandonedReading && UnknownWordLearner.abandonedReading.length > 0;
    UnknownWordLearner.abandonedReading = '';
    UnknownWordLearner.bump(reading, surface, 1);
  }

  // 準候補として出ていた表記が、確定前にタップされて選ばれた。単体でタップ
  // された commit は runSurfaces に1件積むだけで assembled 判定を満たさず
  // (flush の assembled = surfaces.length>=2 || runTruncated) 通常の run
  // 経路では絶対にカウントされないため、別経路として直接1つ進める。
  // これでしきい値に達すれば次から本採用の候補として出る (押されたら昇進)。
  static confirmQuasi(reading: string, surface: string): void {
    UnknownWordLearner.bump(reading, surface, 1);
  }

  // ひらがなで打った読みを、変換せず全部消して諦めた。次にこの読みが手作業で
  // 組み立て直されたときの確認信号として1回だけ覚えておく。
  static noteAbandonedReading(reading: string): void {
    if (reading.length < MIN_READING_LEN || reading.length > MAX_READING_LEN
        || !UnknownWordLearner.isAllHiragana(reading)) {
      UnknownWordLearner.abandonedReading = '';
      return;
    }
    UnknownWordLearner.abandonedReading = reading;
  }

  private static bump(reading: string, surface: string, amount: number): void {
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
    entry[surface] = (entry[surface] ?? 0) + amount;
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
    // 末尾が全部ひらがな (生のかな確定・助詞など、漢字の手がかりが一切無い)
    // なら、1回のbackspaceが表記の何文字に対応するか保証できない。実機で
    // 大量発生した「〜して」のバグはまさにこれで、読みは削られないまま
    // 表記だけ削れて対応が壊れていた。
    // 翔ける (漢字+送り仮名) のようにひらがなが混じっていても、漢字が
    // 1文字でも残っていれば手がかりがあるので安全に末尾から削れる --
    // まさにこの関数が存在する理由 (かける→翔ける→⌫⌫→翔)。危険なのは
    // 「全部ひらがな」の場合だけなので、そこだけ呼び出し側
    // (KeyboardController) が代わりに abandonRun() へ回せるよう false を
    // 返す (run はそのまま残す -- まだ捨てるべきと決まったわけではない)。
    if (UnknownWordLearner.isAllHiragana(tail)) { return false; }
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

  // 組み立て途中の run を、学習せずに捨てる。
  //
  // 削除が入った時点で「打った読み」と「画面に残っている表記」の対応が失われる。
  // truncate() は表記の末尾を1文字削るだけで読みには触らないので、例えば
  // 「〜して」まで打って「して」を消すと、読みには して が残ったまま表記だけが
  // 漢字になり、読み=〜して 表記=漢字 という実在しない対応が学習されてしまう
  // (実機で大量に発生していた)。どこまでの読みが消えた表記に対応するかは
  // 復元できないため、推測せず run ごと捨てる。
  static abandonRun(): void {
    UnknownWordLearner.clearRun();
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

  // 準候補 (quasi-candidates): まだ LEARN_THRESHOLD に達していない、組み立て
  // 途中の語。candidates() と違い正式な変換候補には混ぜず、「これ、覚えかけて
  // ます」を見せるためだけに使う (呼び出し側でうっすら区別して表示する)。
  static quasiCandidates(reading: string): string[] {
    const entry = UnknownWordLearner.counts[reading];
    if (entry === undefined) { return []; }
    const ranked: Ranked[] = [];
    for (const s of Object.keys(entry)) {
      if (entry[s] > 0 && entry[s] < LEARN_THRESHOLD) { ranked.push({ surface: s, count: entry[s] }); }
    }
    ranked.sort((a: Ranked, b: Ranked) => b.count - a.count);
    return ranked.map((r: Ranked) => r.surface);
  }
}
