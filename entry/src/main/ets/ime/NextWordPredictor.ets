// Next-word prediction (次単語予測): after a word is committed, offer the
// words most likely to come next so the user can tap instead of typing --
// the always-full suggestion strip a modern IME (Gboard等) shows the moment
// you finish a word. Three sources, merged in priority order:
//
//   1. LEARNED   - the user's own word→word transitions, recorded on every
//                  consecutive commit. Highest priority: it's the most direct
//                  signal of how THIS user actually writes. Capped, persisted
//                  alongside the conversion learning store.
//   2. SEED      - a curated table of high-value fixed continuations
//                  (ありがとう→ございます, よろしく→お願いします, 私→は…) so the
//                  feature is useful from the very first use, before any
//                  learning has accumulated (cold start).
//   3. PARTICLES - a universal fallback: after ANY content word (one ending in
//                  kanji or katakana, i.e. a noun/verb-stem, never a particle
//                  or okurigana tail) the case particles は/を/が/に/… are the
//                  overwhelmingly likely next tap in Japanese. This is what
//                  gives coverage over the long tail of nouns the seed can't
//                  enumerate.
//
// Deliberately keyed on plain committed surfaces (no POS tagging, no model):
// cheap, fully on-device, and it personalises with use. Only word-length
// commits (<= MAX_KEY_LEN) are learned/keyed, so a whole committed sentence
// never becomes a junk bigram key.

const MAX_KEY_LEN = 8;
const MAX_LEARNED_KEYS = 800;
const MAX_LEARNED_VALS_PER_KEY = 12;
const MAX_PREDICTIONS = 6;

// Case/topic particles offered after any content word, in rough
// everyday-frequency order. These are the universal-fallback predictions.
const GENERIC_PARTICLES: string[] = ['は', 'を', 'が', 'に', 'の', 'で', 'と', 'も'];

// Curated fixed continuations. Keyed on the exact committed surface. Kept to
// genuinely high-frequency, unambiguous next words -- greeting/set-phrase
// tails and the most common particle preferences for very common words. The
// generic-particle fallback already covers "noun → particle" broadly, so this
// table is for cases where a SPECIFIC word (not a bare particle) is the likely
// next tap, or where a word's preferred particle order differs from generic.
const SEED_NEXT: Record<string, string[]> = {
  // greeting / set-phrase continuations (you've committed the head, tap the tail)
  'ありがとう': ['ございます', 'ございました'],
  'おはよう': ['ございます'],
  'よろしく': ['お願いします', 'お願いいたします'],
  'お疲れ': ['様です', '様でした'],
  'おつかれ': ['様です', '様でした'],
  'お世話': ['になっております', 'になります'],
  'こんにち': ['は'],
  'こんばん': ['は'],
  'すみません': ['が', 'でした'],
  '申し訳': ['ございません', 'ありません'],
  'もうしわけ': ['ございません', 'ありません'],
  'いただき': ['ます', 'ました'],
  'よろしくお願い': ['します', 'いたします', '申し上げます'],
  // pronouns / very common nouns → preferred particles
  '私': ['は', 'が', 'の', 'も'],
  '僕': ['は', 'が', 'の', 'も'],
  '俺': ['は', 'が', 'も'],
  'あなた': ['は', 'が', 'の', 'も'],
  '彼': ['は', 'が', 'と', 'の'],
  '彼女': ['は', 'が', 'と', 'の'],
  'これ': ['は', 'を', 'が', 'で'],
  'それ': ['は', 'を', 'が', 'で'],
  'あれ': ['は', 'を', 'が'],
  'ここ': ['に', 'で', 'は', 'から'],
  'そこ': ['に', 'で', 'は'],
  // time nouns → topic は leads
  '今日': ['は', 'の', 'も', 'から'],
  '明日': ['は', 'の', 'から', 'まで'],
  '昨日': ['は', 'の', 'から'],
  '今': ['は', 'から', 'まで', 'すぐ'],
  '来週': ['は', 'の', 'から', 'まで'],
  '先週': ['は', 'の', 'から'],
  '今週': ['は', 'の', 'から', 'まで'],
  '来月': ['は', 'の', 'から', 'まで'],
  '今年': ['は', 'の', 'も'],
  // common everyday nouns
  '会社': ['に', 'で', 'は', 'の'],
  '学校': ['に', 'で', 'は', 'の'],
  '仕事': ['が', 'は', 'を', 'で'],
  '会議': ['は', 'が', 'を', 'で'],
  '電車': ['に', 'で', 'が', 'は'],
  '天気': ['が', 'は', 'も'],
  '時間': ['が', 'は', 'を', 'に'],
  '問題': ['が', 'は', 'を', 'も'],
  'ご飯': ['を', 'は', 'が'],
  // common verb renyou-stems → continuations
  '食べ': ['たい', 'ます', 'て', 'ました'],
  '行き': ['たい', 'ます', 'ました', 'ましょう'],
  '見': ['て', 'たい', 'ます', 'ました'],
  '帰り': ['ます', 'たい', 'ました'],
  '買い': ['たい', 'ます', 'に'],
  '飲み': ['たい', 'ます', 'に'],
  'し': ['て', 'ます', 'ました', 'たい'],
  // frequent adverb/連体詞 openers
  'ちょっと': ['待って', 'だけ'],
  'もう': ['少し', 'すぐ', 'いい'],
  'とても': ['いい', '良い'],
};

interface Scored {
  word: string;
  count: number;
}

export class NextWordPredictor {
  // prev-surface -> (next-surface -> count). Persisted via get/setLearned.
  private static learned: Record<string, Record<string, number>> = {};

  static setLearned(data: Record<string, Record<string, number>>): void {
    NextWordPredictor.learned = data ?? {};
  }

  static getLearned(): Record<string, Record<string, number>> {
    return NextWordPredictor.learned;
  }

  private static isContentTail(surface: string): boolean {
    if (surface.length === 0) { return false; }
    const code = surface.charCodeAt(surface.length - 1);
    // CJK unified ideographs (kanji) or katakana -- a noun/verb-stem tail, not
    // a hiragana particle/okurigana. Case particles are the natural next tap.
    if (code >= 0x4e00 && code <= 0x9fff) { return true; }
    if (code >= 0x30a0 && code <= 0x30ff) { return true; }
    return false;
  }

  // Record that `next` was committed immediately after `prev`. Only short,
  // word-sized surfaces are kept as keys/values so a whole committed sentence
  // never becomes a junk transition that can't recur.
  static record(prev: string, next: string): void {
    if (prev.length === 0 || next.length === 0) { return; }
    if (prev.length > MAX_KEY_LEN || next.length > MAX_KEY_LEN) { return; }
    if (prev === next) { return; }
    let entry = NextWordPredictor.learned[prev];
    if (entry === undefined) {
      if (Object.keys(NextWordPredictor.learned).length >= MAX_LEARNED_KEYS) { return; }
      entry = {};
      NextWordPredictor.learned[prev] = entry;
    }
    entry[next] = (entry[next] ?? 0) + 1;
    // Cap a key's value set: when it overflows, drop the least-used entry so
    // the store can't grow without bound for a very active prev word.
    const keys = Object.keys(entry);
    if (keys.length > MAX_LEARNED_VALS_PER_KEY) {
      let minWord = keys[0];
      for (const k of keys) { if (entry[k] < entry[minWord]) { minWord = k; } }
      delete entry[minWord];
    }
  }

  // Predicted next words after committing `prev`, best first, deduped, capped.
  static predict(prev: string): string[] {
    if (prev.length === 0) { return []; }
    const out: string[] = [];
    const push = (w: string): void => {
      if (w.length > 0 && w !== prev && out.indexOf(w) < 0 && out.length < MAX_PREDICTIONS) {
        out.push(w);
      }
    };
    // 1. learned, by descending count
    const entry = NextWordPredictor.learned[prev];
    if (entry !== undefined) {
      const scored: Scored[] = [];
      for (const w of Object.keys(entry)) { scored.push({ word: w, count: entry[w] }); }
      scored.sort((a: Scored, b: Scored) => b.count - a.count);
      for (const s of scored) { push(s.word); }
    }
    // 2. curated seed
    const seed = SEED_NEXT[prev];
    if (seed !== undefined) { for (const w of seed) { push(w); } }
    // 3. universal particle fallback after a content word
    if (NextWordPredictor.isContentTail(prev)) {
      for (const p of GENERIC_PARTICLES) { push(p); }
    }
    return out;
  }
}
