// Predictive conversion (予測変換): while a reading is still being typed, offer
// the full common words whose reading STARTS WITH what's typed so far, so the
// user can pick 会社 after typing かいし instead of finishing かいしゃ. The
// keystroke-saving half of modern-IME typing (the other half, next-word, lives
// in NextWordPredictor). Sources, learned first:
//
//   1. LEARNED     - scan the conversion learning store (reading→{surface:count})
//                     for readings that extend the typed prefix; the user's own
//                     previously-committed words, ranked by how often they picked
//                     them. Personalises with zero configuration.
//   1.5 SHORT-TERM  - ShortTermMemory: words picked a couple of times THIS
//                     session, before long-term learning has caught up
//                     (Gboard has a similar "recently used" boost). Not
//                     persisted; see ShortTermMemory.ets.
//   2. CURATED      - a table of high-frequency everyday words so completion
//                     works from the first use, before anything is learned.
//                     Every entry's reading→surface is an ordinary correct
//                     conversion (all present in dict.json); this table only
//                     makes them reachable from a prefix, it never invents a
//                     spelling.
//
// Distinct from PredictivePhrases (fixed long set-phrases like greetings): this
// is ordinary vocabulary, and it is inserted as an ALTERNATIVE (never candidate
// [0], which stays the exact conversion of exactly what was typed).

import type { ShortTermHit } from './ShortTermMemory';

interface Completion {
  reading: string;
  surface: string;
}

// Minimum typed length before predictive completion fires. One kana is far too
// ambiguous (typing あ must not spray 明日/ありがとう/…); two is the practical
// floor where a prefix starts to be discriminating.
const MIN_PREFIX = 2;
const MAX_COMPLETIONS = 3;
// dictHits (辞書全体からの前方一致) は CURATED と違って中身が玉石混淆で、
// 「レーニン主義」のようなマイナー語も含まれている。短い prefix では
// たまたま辞書に他の候補が無いだけで pool.size===1 になり、頻度を無視した
// 語がいきなり一発候補として出てしまっていた(「れ→レーニン主義」)。
// CURATED (少数の厳選語) はそのまま MIN_PREFIX で許可するが、dictHits に
// しか無い一致は、もう少し長く打って絞られてから初めて許可する。
const DICT_ONLY_MIN_PREFIX = 4;

// High-frequency everyday words, roughly most-common-first (ties broken by
// generality). Kept to words a user types constantly, so a 2-3 kana prefix
// lands them fast. Curated, not scraped -- every surface is the standard
// spelling of its reading.
const CURATED: Completion[] = [
  { reading: 'にほん', surface: '日本' },
  { reading: 'にほんご', surface: '日本語' },
  { reading: 'にほんじん', surface: '日本人' },
  { reading: 'かいしゃ', surface: '会社' },
  { reading: 'かいぎ', surface: '会議' },
  { reading: 'かいわ', surface: '会話' },
  { reading: 'がっこう', surface: '学校' },
  { reading: 'がくせい', surface: '学生' },
  { reading: 'だいがく', surface: '大学' },
  { reading: 'でんわ', surface: '電話' },
  { reading: 'でんしゃ', surface: '電車' },
  { reading: 'でんき', surface: '電気' },
  { reading: 'じかん', surface: '時間' },
  { reading: 'とけい', surface: '時計' },
  { reading: 'もんだい', surface: '問題' },
  { reading: 'しつもん', surface: '質問' },
  { reading: 'ばしょ', surface: '場所' },
  { reading: 'ばあい', surface: '場合' },
  { reading: 'じょうほう', surface: '情報' },
  { reading: 'じょうきょう', surface: '状況' },
  { reading: 'よてい', surface: '予定' },
  { reading: 'よやく', surface: '予約' },
  { reading: 'れんらく', surface: '連絡' },
  { reading: 'かくにん', surface: '確認' },
  { reading: 'じゅんび', surface: '準備' },
  { reading: 'だいじょうぶ', surface: '大丈夫' },
  { reading: 'たいせつ', surface: '大切' },
  { reading: 'たいへん', surface: '大変' },
  { reading: 'きもち', surface: '気持ち' },
  { reading: 'きぶん', surface: '気分' },
  { reading: 'いっしょ', surface: '一緒' },
  { reading: 'いちばん', surface: '一番' },
  { reading: 'いちど', surface: '一度' },
  { reading: 'きょう', surface: '今日' },
  { reading: 'あした', surface: '明日' },
  { reading: 'きのう', surface: '昨日' },
  { reading: 'こんど', surface: '今度' },
  { reading: 'ぜんぶ', surface: '全部' },
  { reading: 'ぜんぜん', surface: '全然' },
  { reading: 'ほんとう', surface: '本当' },
  { reading: 'ほんとうに', surface: '本当に' },
  { reading: 'おねがい', surface: 'お願い' },
  { reading: 'びょういん', surface: '病院' },
  { reading: 'ぎんこう', surface: '銀行' },
  { reading: 'けいたい', surface: '携帯' },
  { reading: 'ばんごう', surface: '番号' },
  { reading: 'じゅうしょ', surface: '住所' },
  { reading: 'なまえ', surface: '名前' },
  { reading: 'りょうり', surface: '料理' },
  { reading: 'りょうきん', surface: '料金' },
  { reading: 'せつめい', surface: '説明' },
  { reading: 'そうだん', surface: '相談' },
  { reading: 'ほうこく', surface: '報告' },
  { reading: 'さんか', surface: '参加' },
  { reading: 'さんこう', surface: '参考' },
  { reading: 'ひつよう', surface: '必要' },
  { reading: 'じゅうよう', surface: '重要' },
  { reading: 'かんたん', surface: '簡単' },
  { reading: 'さいきん', surface: '最近' },
  { reading: 'さいしょ', surface: '最初' },
  { reading: 'さいご', surface: '最後' },
  { reading: 'さいこう', surface: '最高' },
  { reading: 'ふつう', surface: '普通' },
  { reading: 'ふだん', surface: '普段' },
  { reading: 'じぶん', surface: '自分' },
  { reading: 'じてんしゃ', surface: '自転車' },
  { reading: 'かぞく', surface: '家族' },
  { reading: 'ともだち', surface: '友達' },
  { reading: 'かのじょ', surface: '彼女' },
  { reading: 'しごと', surface: '仕事' },
  { reading: 'しゅっちょう', surface: '出張' },
  { reading: 'ごぜん', surface: '午前' },
  { reading: 'ごご', surface: '午後' },
  { reading: 'げんき', surface: '元気' },
  { reading: 'てんき', surface: '天気' },
  { reading: 'せんせい', surface: '先生' },
  { reading: 'がくせいしょう', surface: '学生証' },
  { reading: 'きょういく', surface: '教育' },
  { reading: 'けんきゅう', surface: '研究' },
  { reading: 'せいかつ', surface: '生活' },
  { reading: 'しゃかい', surface: '社会' },
  { reading: 'けいざい', surface: '経済' },
  { reading: 'せいじ', surface: '政治' },
  { reading: 'かんきょう', surface: '環境' },
  { reading: 'もくてき', surface: '目的' },
  { reading: 'けっか', surface: '結果' },
  { reading: 'げんいん', surface: '原因' },
  { reading: 'えいきょう', surface: '影響' },
  { reading: 'かのうせい', surface: '可能性' },
];

// learned 側の「ここまで打てば確実」判定に使う最低ピック数。1回選んだだけの
// 語をここで確実扱いするとノイズに逆戻りするので、複数回選んだ語だけ通す。
const LEARNED_CONFIDENT_MIN = 2;

// 短期記憶 (ShortTermMemory) がこの回数以上選ばれていれば「強い」とみなし、
// learned と同じ扱い (決まり字を無視して許可) にする。ShortTermMemory.
// STRONG_MIN と同じ値。型だけ import している (実処理は依然として
// 引数で受け取る値だけを見ており、ShortTermMemory の状態には触れない)。
const SHORT_TERM_STRONG_MIN = 2;

export class PredictiveConversion {
  // Completions of `prefix`, best first: the user's learned words (by pick
  // count) then curated/dictionary words, deduped by surface, capped. `learned`
  // is the conversion learning store (KanaKanjiConverter.getLearned()); passed
  // in rather than imported to keep this module dependency-free and
  // unit-testable.
  // dictHits は辞書由来の前方一致 (KanaKanjiConverter.prefixCompletions)。
  // 引数で受け取るのは、このモジュールを依存なしに保つという元の方針のまま
  // 辞書を使えるようにするため。
  //
  // 「今打った文字より後ろに伸びる」候補 (蛇足候補) は、使用頻度の割に頻繁に
  // 出てくるとの指摘を受けて絞り込んだ。かるたの決まり字のたとえの通り、
  // 「この続きの文字はこの語しかあり得ない」というところまで打ってようやく
  // 出す。具体的には:
  //   - learned (本人が実際に選んだ実績) はそのままの信頼度で許可。ただし
  //     1回だけの選択はノイズになりうるので LEARNED_CONFIDENT_MIN 回以上に限る。
  //   - curated (手書き表) + dictHits (辞書全体) は、この prefix の続きとして
  //     あり得る語がちょうど1つに絞られたとき (=決まり字に達したとき) だけ、
  //     その1語だけを出す。2つ以上あり得るうちはまだ確実ではないので出さない。
  static predict(prefix: string, learned: Record<string, Record<string, number>>,
      dictHits?: string[], shortTermHits?: ShortTermHit[]): string[] {
    if (prefix.length < MIN_PREFIX) { return []; }
    const out: string[] = [];
    const seen = new Set<string>();
    const push = (surface: string): void => {
      if (surface.length > 0 && !seen.has(surface) && out.length < MAX_COMPLETIONS) {
        seen.add(surface);
        out.push(surface);
      }
    };

    // 1. learned readings that extend the prefix, best surface per reading,
    //    複数回選んだ語だけ「確実」として通す。
    interface LearnedHit { surface: string; count: number; }
    const hits: LearnedHit[] = [];
    if (learned) {
      for (const reading of Object.keys(learned)) {
        if (reading.length <= prefix.length || !reading.startsWith(prefix)) { continue; }
        const counts = learned[reading];
        let bestSurface = '';
        let bestCount = 0;
        for (const surface of Object.keys(counts)) {
          if (counts[surface] > bestCount) { bestCount = counts[surface]; bestSurface = surface; }
        }
        if (bestSurface.length > 0) { hits.push({ surface: bestSurface, count: bestCount }); }
      }
      hits.sort((a: LearnedHit, b: LearnedHit) => b.count - a.count);
      for (const h of hits) {
        if (h.count >= LEARNED_CONFIDENT_MIN) { push(h.surface); }
      }
    }

    // 1.5 短期記憶 (このセッション中に何度か選んだ語)。SHORT_TERM_STRONG_MIN
    //     回以上選ばれていれば learned と同じ「確実」枠として扱い、決まり字を
    //     無視して許可する。まだ弱い(1回だけ)ものはここでは出さず、後段の
    //     「1番目には出さない」ガード付きの枠に回す。
    const weakShortTerm: string[] = [];
    if (shortTermHits !== undefined) {
      for (const h of shortTermHits) {
        if (h.count >= SHORT_TERM_STRONG_MIN) {
          push(h.surface);
        } else {
          weakShortTerm.push(h.surface);
        }
      }
    }

    // 2+3. curated + 辞書全体からの前方一致をまとめて集め、この prefix の続きと
    //      してあり得る語(表記)がちょうど1つだけに絞れているときだけ採用する。
    if (out.length < MAX_COMPLETIONS) {
      const curatedPool = new Set<string>();
      for (const c of CURATED) {
        if (c.reading.length > prefix.length && c.reading.startsWith(prefix)) { curatedPool.add(c.surface); }
      }
      const pool = new Set<string>();
      for (const s of curatedPool) { pool.add(s); }
      if (dictHits !== undefined) {
        for (const d of dictHits) { if (d.length > 0) { pool.add(d); } }
      }
      if (pool.size === 1) {
        for (const s of pool) {
          if (curatedPool.has(s) || prefix.length >= DICT_ONLY_MIN_PREFIX) { push(s); }
        }
      }
    }

    // 4. 短期記憶の弱い方 (1回だけ選ばれた語)。ここまでに何か1つでも出て
    //    いれば足してよいが、これしか無い(out が空のまま)場合はまだ確証が
    //    無いので出さない -- 「1番目には出さないようにしよう」の実体。
    if (out.length > 0) {
      for (const s of weakShortTerm) { push(s); }
    }
    return out;
  }
}
