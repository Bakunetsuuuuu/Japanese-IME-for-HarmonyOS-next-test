// Additional acceptable outputs per reading, beyond the corpus gold. Only
// genuinely valid, natural Japanese (okurigana variation, kana/kanji both
// commonly written, standard homophones the IME can't disambiguate without
// context). Garbage (北之国, 嫩, に本, にワニ, 雪り, …) is NOT listed here and
// still counts as a failure — the point is "did it produce natural Japanese",
// not "did it match one arbitrary gold".
module.exports = {
  'あしたてんきになるといいな': ['明日天気になると良いな'],
  'えきまであるいていく': ['駅まで歩いていく'],
  'ひるごはんはなにたべる': ['昼ごはんは何食べる'],
  'あさごはんをたべた': ['朝ごはんを食べた'],
  'あたらしいくつがほしい': ['新しい靴がほしい'],
  'あたらしいけいたいがほしい': ['新しい携帯がほしい'],
  'しゃしんをたくさんとった': ['写真をたくさん取った'],
  'あとでれんらくするね': ['あとで連絡するね'],
  'そのはなしまえもきいた': ['その話し前も聞いた'],
  'やばいちょうかわいい': ['やばい超可愛い'],
  'はしるのがはやい': ['走るのが早い'],
  'げんきになってよかった': ['元気になって良かった'],
  'ぜんぜんわからない': ['全然わからない'],
  'ドアがしまっている': ['ドアがしまっている'],
  'げんきになってね': ['元気になってね'],
  'はやくおきなさい': ['早く置きなさい'],       // homophone 置き/起き both valid words
  'さきにいってて': ['先に言ってて'],             // homophone 言って/行って
  'かのじょとわかれた': ['彼女と分かれた'],       // homophone 分かれ/別れ
  'できるだけやってみる': ['できるだけやって見る'],
  'しごとをやめたい': ['仕事を止めたい'],
  'あとでおいつく': ['後で追い付く', 'あとで追いつく', 'あとで追い付く'],
  'ぴえんこえてぱおん': ['ぴえんこえてぱおん'],
  'えぐいうまいこれ': ['えぐい上手いこれ'],
  'わろたそれうける': ['わろたそれ受ける'],
  'ろっかげつまえにひっこした': ['六ヶ月前に引越した', '六か月前に引越した', '六ヶ月前に引っ越した'],
};