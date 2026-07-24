// Emoji suggestion (絵文字サジェスト): after a word is committed, offer the
// emoji a writer commonly reaches for after it, in the same next-word strip —
// tap 😊 right after 嬉しい, 🐱 after 猫 — instead of switching to the emoji
// keyboard. A signature modern-IME feature; here it's driven by a curated
// surface→emoji table rather than an ML model, so it's deterministic and
// unit-testable. The table maps the committed *surface* (and common kana
// spellings) to its most typical emoji, most-apt first.
//
// Deliberately conservative: only words with a genuinely conventional emoji
// association are listed, so the strip stays relevant and never sprays random
// emoji at ordinary nouns.

const EMOJI_FOR_SURFACE: Record<string, string[]> = {
  // --- emotions / reactions ---
  '嬉しい': ['😊', '😄', '🥰'], 'うれしい': ['😊', '😄'],
  '楽しい': ['😄', '🎶'], 'たのしい': ['😄'],
  '悲しい': ['😢', '😭'], 'かなしい': ['😢'],
  '寂しい': ['😔'], 'さびしい': ['😔'],
  '好き': ['❤️', '😍'], 'すき': ['❤️'], '大好き': ['❤️', '🥰'], 'だいすき': ['❤️'],
  '愛してる': ['❤️'], 'かわいい': ['🥰', '😍'], '可愛い': ['🥰', '😍'],
  '笑': ['😂', '🤣'], 'わら': ['😂'],
  '怒': ['😠', '💢'], 'むかつく': ['😡'], 'ムカつく': ['😡'],
  '疲れた': ['😩', '😮‍💨'], 'つかれた': ['😩'], 'お疲れ様': ['🙇'],
  '眠い': ['😴'], 'ねむい': ['😴'], '眠たい': ['😴'],
  'びっくり': ['😲'], 'ビックリ': ['😲'], '最高': ['🙌', '✨'], 'さいこう': ['🙌'],
  'やばい': ['😱', '🔥'], 'ヤバい': ['😱'], 'すごい': ['😳', '✨'], 'スゴい': ['✨'],
  '泣': ['😭'], 'えーん': ['😭'],
  // --- greetings / social ---
  'ありがとう': ['🙏', '🙇'], 'ありがとうございます': ['🙏'],
  'ごめん': ['🙇', '🙏'], 'ごめんなさい': ['🙇'], 'すみません': ['🙇'],
  'よろしく': ['🙇'], 'おめでとう': ['🎉', '㊗️', '🎊'], 'おめでとうございます': ['🎉'],
  'おはよう': ['☀️'], 'おやすみ': ['🌙', '😴'], 'こんにちは': ['👋'], 'ばいばい': ['👋'],
  'いってきます': ['🚶'], 'いただきます': ['🙏'], 'ごちそうさま': ['🙏'],
  'がんばる': ['💪'], 'がんばって': ['💪', '📣'], '頑張る': ['💪'], '頑張って': ['💪'],
  'いいね': ['👍'], 'ＯＫ': ['👌'], 'やった': ['🙌', '🎉'], 'よし': ['💪'],
  // --- animals ---
  '猫': ['🐱', '🐈'], 'ねこ': ['🐱'], '犬': ['🐶', '🐕'], 'いぬ': ['🐶'],
  '鳥': ['🐦'], '魚': ['🐟'], 'うさぎ': ['🐰'], '熊': ['🐻'], 'ぱんだ': ['🐼'], 'パンダ': ['🐼'],
  // --- food / drink ---
  'ご飯': ['🍚'], 'ごはん': ['🍚'], 'コーヒー': ['☕'], 'こーひー': ['☕'],
  'ビール': ['🍺'], 'お酒': ['🍶', '🍺'], '寿司': ['🍣'], 'すし': ['🍣'],
  'ケーキ': ['🍰'], 'ラーメン': ['🍜'], 'ピザ': ['🍕'], 'りんご': ['🍎'],
  'お茶': ['🍵'], 'パン': ['🍞'], 'たまご': ['🥚'], '卵': ['🥚'],
  // --- weather / nature ---
  '花': ['🌸', '💐'], 'はな': ['🌸'], '桜': ['🌸'], 'さくら': ['🌸'],
  '雨': ['🌧️', '☔'], 'あめ': ['🌧️'], '雪': ['❄️', '⛄'], 'ゆき': ['❄️'],
  '晴れ': ['☀️'], 'はれ': ['☀️'], '星': ['⭐'], 'ほし': ['⭐'],
  '月': ['🌙'], '海': ['🌊'], 'うみ': ['🌊'], '山': ['⛰️'], '虹': ['🌈'], 'にじ': ['🌈'],
  '火': ['🔥'], '雷': ['⚡'],
  // --- objects / places / events ---
  'お金': ['💰', '💴'], 'おかね': ['💰'], '車': ['🚗'], 'くるま': ['🚗'],
  '電車': ['🚃'], '飛行機': ['✈️'], '家': ['🏠'], 'いえ': ['🏠'],
  'プレゼント': ['🎁'], '誕生日': ['🎂', '🎉'], 'たんじょうび': ['🎂'],
  '音楽': ['🎵'], '本': ['📖'], '映画': ['🎬'], '仕事': ['💼'], '旅行': ['✈️', '🧳'],
  'ハート': ['❤️', '💕'], '花火': ['🎆'], 'はなび': ['🎆'], 'クリスマス': ['🎄'],
  'メール': ['📧'], '電話': ['📞'], '写真': ['📷'], 'カメラ': ['📷'],
};

export class EmojiSuggest {
  // Emoji for a just-committed surface, most-apt first, or [] if the word has
  // no conventional emoji association.
  static forSurface(surface: string): string[] {
    const e = EMOJI_FOR_SURFACE[surface];
    return e !== undefined ? e : [];
  }
}
