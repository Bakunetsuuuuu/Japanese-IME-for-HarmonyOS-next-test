// Tenth held-out TEST corpus. Authored fresh (not reused from TEST1-9),
// specifically to serve as the first measurement of the mozc-derived
// "track B" engine (see tools/mozc_data/) side by side with the hand-built
// "track A" dictionary -- see tools/mozc_data/compare_engines.js. Both
// engines are scored against the same gold answers here so the numbers are
// directly comparable, though track B is *not* expected to match track A's
// accuracy: it ships mozc's statistics unmodified (no hand-tuning), so this
// corpus is informative about where it currently stands, not a target to
// tune either engine toward.
module.exports = [
  // --- everyday ---
  ['きょうはいいてんきですね', '今日はいい天気ですね'],
  ['わたしはがっこうにいきます', '私は学校に行きます'],
  ['にほんごをべんきょうしています', '日本語を勉強しています'],
  ['あしたはあめがふるらしいです', '明日は雨が降るらしいです'],
  ['これはとてもおもしろいほんです', 'これはとても面白い本です'],
  ['まいあさろくじにおきています', '毎朝六時に起きています'],
  ['ともだちとえいがをみにいきました', '友達と映画を見に行きました'],
  ['このみせのラーメンはとてもおいしい', 'この店のラーメンはとても美味しい'],
  // --- business ---
  ['あすのかいぎのしりょうをじゅんびした', '明日の会議の資料を準備した'],
  ['たんとうしゃにれんらくをとってください', '担当者に連絡を取ってください'],
  ['しんせいひんのはつばいびがきまりました', '新製品の発売日が決まりました'],
  // --- travel ---
  ['くうこうまでのみちがこんでいた', '空港までの道が混んでいた'],
  ['りょこうさきでしゃしんをたくさんとった', '旅行先で写真をたくさん撮った'],
  // --- home/health ---
  ['まいにちさんじゅっぷんうんどうしている', '毎日三十分運動している'],
  ['たいちょうがわるいのでびょういんにいった', '体調が悪いので病院に行った'],
  ['へやのそうじをしてすっきりした', '部屋の掃除をしてすっきりした'],
  // --- tech ---
  ['すまほのバッテリーがすぐなくなる', 'スマホのバッテリーがすぐなくなる'],
  ['あたらしいアプリをダウンロードした', '新しいアプリをダウンロードした'],
  // --- casual ---
  ['きょうはひまだからどこかいこうよ', '今日は暇だからどこか行こうよ'],
  ['それほんとにおもしろかったよ', 'それ本当に面白かったよ'],
];
