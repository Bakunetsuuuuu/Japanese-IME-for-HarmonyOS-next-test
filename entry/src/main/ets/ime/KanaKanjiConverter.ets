const DICTIONARY: Record<string, string[]> = {
  // 数字・基本
  'いち': ['一', '１'], 'さん': ['三', '参', '３'],
  'し': ['四', '死', '氏', 'し'], 'ご': ['五', '後', '語', '御'],
  'ろく': ['六'], 'なな': ['七'], 'はち': ['八'],
  'きゅう': ['九', '旧'], 'じゅう': ['十', '住', '重'],
  'ひゃく': ['百'], 'せん': ['千', '先', '選', '専', '線'],
  'まん': ['万'],

  // 代名詞
  'わたし': ['私', 'わたし'], 'わたくし': ['私'],
  'ぼく': ['僕'], 'おれ': ['俺'],
  'あなた': ['あなた', '貴方', '貴女'],
  'かれ': ['彼'], 'かのじょ': ['彼女'],
  'かれら': ['彼ら', '彼等'], 'わたしたち': ['私たち', '私達'],
  'これ': ['これ', '此れ'], 'それ': ['それ', '其れ'], 'あれ': ['あれ', '彼れ'],
  'ここ': ['ここ', '此処'], 'そこ': ['そこ', '其処'], 'あそこ': ['あそこ', '彼処'],
  'なに': ['何', 'なに'], 'なん': ['何', 'なん'],
  'だれ': ['誰', '誰か'], 'いつ': ['いつ', '何時'],
  'どこ': ['どこ', '何処'], 'どれ': ['どれ'], 'どう': ['どう', '如何'],

  // 時間
  'きょう': ['今日'], 'こんにち': ['今日'],
  'あした': ['明日', '明朝'], 'あす': ['明日'],
  'きのう': ['昨日'], 'さくじつ': ['昨日'],
  'いま': ['今'], 'いまごろ': ['今頃'],
  'ことし': ['今年'], 'らいねん': ['来年'], 'きょねん': ['去年'],
  'らいげつ': ['来月'], 'せんげつ': ['先月'], 'こんげつ': ['今月'],
  'らいしゅう': ['来週'], 'せんしゅう': ['先週'], 'こんしゅう': ['今週'],
  'じかん': ['時間'], 'ふん': ['分'], 'びょう': ['秒'],
  'あさ': ['朝', '麻'], 'ひる': ['昼'], 'よる': ['夜', '余'],
  'よなか': ['夜中'], 'まよなか': ['真夜中'],
  'げつようび': ['月曜日', '月曜'], 'かようび': ['火曜日', '火曜'],
  'すいようび': ['水曜日', '水曜'], 'もくようび': ['木曜日', '木曜'],
  'きんようび': ['金曜日', '金曜'], 'どようび': ['土曜日', '土曜'],
  'にちようび': ['日曜日', '日曜'],

  // 自然
  'そら': ['空'], 'うみ': ['海'], 'やま': ['山'], 'かわ': ['川', '河'],
  'もり': ['森'], 'はやし': ['林'], 'しぜん': ['自然'],
  'たいよう': ['太陽'], 'つき': ['月', '付き'],
  'ほし': ['星'], 'くも': ['雲', '蜘蛛'],
  'かぜ': ['風', '風邪'], 'あめ': ['雨', '飴'], 'ゆき': ['雪'],
  'みず': ['水'], 'ひ': ['火', '日', '氷'],
  'つち': ['土', '地'], 'いし': ['石'],
  'はな': ['花', '鼻', '話'], 'き': ['木', '気', '機', '記', '期', '基'],
  'くさ': ['草'],

  // 動物
  'ねこ': ['猫'], 'いぬ': ['犬'], 'とり': ['鳥', '取り'],
  'さかな': ['魚'], 'うし': ['牛'],
  'うま': ['馬'], 'ぶた': ['豚'], 'にわとり': ['鶏', '雉'],
  'ぞう': ['象'], 'らいおん': ['ライオン'],

  // 食べ物・飲み物
  'ごはん': ['ご飯', '御飯'], 'たべもの': ['食べ物'],
  'のみもの': ['飲み物'], 'おちゃ': ['お茶'],
  'みそしる': ['味噌汁'], 'すし': ['寿司', '鮨'],
  'ラーメン': ['ラーメン'], 'らーめん': ['ラーメン'],
  'にく': ['肉'], 'やさい': ['野菜'], 'くだもの': ['果物'],
  'りんご': ['りんご', '林檎'], 'みかん': ['みかん', '蜜柑'],
  'たまご': ['卵', '玉子'], 'パン': ['パン'], 'ぱん': ['パン'],
  'さとう': ['砂糖'], 'しお': ['塩'], 'しょうゆ': ['醤油'],

  // 場所・建物
  'いえ': ['家'], 'うち': ['家', '内', 'うち'],
  'たてもの': ['建物'], 'へや': ['部屋'],
  'がっこう': ['学校'], 'だいがく': ['大学'],
  'かいしゃ': ['会社'], 'びょういん': ['病院'],
  'えき': ['駅'], 'くうこう': ['空港'],
  'みち': ['道'], 'まち': ['町', '街'],
  'とし': ['都市', '年'], 'くに': ['国'],
  'にほん': ['日本'], 'にっぽん': ['日本'],
  'せかい': ['世界'], 'にほんご': ['日本語'],
  'としょかん': ['図書館'], 'びじゅつかん': ['美術館'],
  'こうえん': ['公園'], 'スーパー': ['スーパー'], 'すーぱー': ['スーパー'],
  'とうきょう': ['東京'], 'おおさか': ['大阪'], 'きょうと': ['京都'],
  'よこはま': ['横浜'], 'なごや': ['名古屋'], 'さっぽろ': ['札幌'],
  'こうべ': ['神戸'], 'せんだい': ['仙台'], 'ふくおか': ['福岡'],
  'ほっかいどう': ['北海道'], 'おきなわ': ['沖縄'], 'とうきょうと': ['東京都'],
  'かながわ': ['神奈川'], 'さいたま': ['埼玉'], 'ちば': ['千葉'],
  'にほんかい': ['日本海'], 'たいへいよう': ['太平洋'],
  'しんかんせん': ['新幹線'], 'ちかてつ': ['地下鉄'],

  // 交通
  'くるま': ['車'], 'でんしゃ': ['電車'],
  'バス': ['バス'], 'ばす': ['バス'],
  'ひこうき': ['飛行機'], 'ふね': ['船'],
  'じてんしゃ': ['自転車'], 'とっきゅう': ['特急'],

  // 人・社会
  'ひと': ['人', '一'], 'にんげん': ['人間'],
  'こども': ['子供', '子ども'], 'おとこ': ['男'],
  'おんな': ['女'], 'おとな': ['大人'],
  'ともだち': ['友達', '友人'], 'かぞく': ['家族'],
  'ちち': ['父', '血'], 'はは': ['母'],
  'おとうさん': ['お父さん'], 'おかあさん': ['お母さん'],
  'あに': ['兄'], 'あね': ['姉'],
  'おとうと': ['弟'], 'いもうと': ['妹'],
  'せんせい': ['先生'], 'がくせい': ['学生'],
  'しごと': ['仕事'], 'かいぎ': ['会議'],

  // 体
  'からだ': ['体'], 'あたま': ['頭'],
  'め': ['目', '芽'], 'くち': ['口'],
  'みみ': ['耳'], 'て': ['手'],
  'あし': ['足', '脚'], 'かみ': ['髪', '神', '紙'],
  'こころ': ['心'], 'いのち': ['命'],

  // 動詞（辞書形）
  'する': ['する', '為る'], 'くる': ['来る', 'くる'],
  'いく': ['行く'], 'みる': ['見る', '診る'],
  'きく': ['聞く', '効く'], 'よむ': ['読む'],
  'かく': ['書く', '描く'], 'たべる': ['食べる'],
  'のむ': ['飲む'], 'ねる': ['寝る'],
  'おきる': ['起きる'], 'あるく': ['歩く'],
  'はしる': ['走る'], 'かう': ['買う', '飼う'],
  'うる': ['売る'], 'つくる': ['作る', '造る'],
  'いう': ['言う'],
  'はなす': ['話す'], 'きえる': ['消える'],
  'かえる': ['帰る', '返る', '変える', '蛙'],
  'みつける': ['見つける'], 'あける': ['開ける'],
  'しめる': ['閉める', '締める'], 'いれる': ['入れる'],
  'だす': ['出す'], 'もつ': ['持つ'],
  'しる': ['知る'],
  'できる': ['できる', '出来る'], 'はじめる': ['始める'],
  'おわる': ['終わる'], 'つかう': ['使う'],
  'みせる': ['見せる'], 'おしえる': ['教える'],
  'おぼえる': ['覚える'],
  'わすれる': ['忘れる'], 'ちがう': ['違う'],

  // い形容詞
  'おおきい': ['大きい'], 'ちいさい': ['小さい'],
  'たかい': ['高い'], 'ひくい': ['低い'],
  'ながい': ['長い'], 'みじかい': ['短い'],
  'おもい': ['重い'], 'かるい': ['軽い'],
  'あたらしい': ['新しい'], 'ふるい': ['古い'],
  'いい': ['いい', '良い'], 'よい': ['良い', '好い'],
  'わるい': ['悪い'],
  'おおい': ['多い'], 'すくない': ['少ない'],
  'やさしい': ['易しい', '優しい'],
  'たのしい': ['楽しい'],
  'うつくしい': ['美しい'],
  'つよい': ['強い'], 'よわい': ['弱い'],
  'はやい': ['速い', '早い'], 'おそい': ['遅い'],
  'あたたかい': ['暖かい', '温かい'], 'つめたい': ['冷たい'],
  'あつい': ['暑い', '熱い', '厚い'], 'さむい': ['寒い'],
  'あかるい': ['明るい'], 'くらい': ['暗い'],
  'しろい': ['白い'], 'くろい': ['黒い'],
  'あかい': ['赤い'], 'あおい': ['青い'],
  'きいろい': ['黄色い'], 'からい': ['辛い'],

  // な形容詞
  'きれい': ['きれい', '綺麗'],
  'しずか': ['静か', 'しずか'],
  'にぎやか': ['賑やか'],
  'げんき': ['元気'],
  'だいじょうぶ': ['大丈夫'],
  'すき': ['好き'],
  'きらい': ['嫌い'],
  'じょうず': ['上手'],
  'たいせつ': ['大切'],
  'しんせつ': ['親切'],
  'ゆうめい': ['有名'],
  'とくべつ': ['特別'],
  'しんじゅう': ['心中'],

  // 挨拶・よく使う言葉
  'こんにちは': ['こんにちは', '今日は'],
  'おはよう': ['おはよう', 'お早う'],
  'おはようございます': ['おはようございます', 'お早うございます'],
  'こんばんは': ['こんばんは', '今晩は'],
  'おやすみ': ['おやすみ', 'お休み'],
  'おやすみなさい': ['おやすみなさい'],
  'ありがとう': ['ありがとう', '有難う'],
  'ありがとうございます': ['ありがとうございます'],
  'すみません': ['すみません', '済みません'],
  'ごめんなさい': ['ごめんなさい'],
  'ごめん': ['ごめん'],
  'はじめまして': ['はじめまして', '初めまして'],
  'よろしく': ['よろしく', '宜しく'],
  'よろしくおねがいします': ['よろしくお願いします'],
  'さようなら': ['さようなら', '左様なら'],
  'またね': ['またね'],
  'いただきます': ['いただきます', '頂きます'],
  'ごちそうさま': ['ごちそうさま', '御馳走様'],
  'おかえり': ['おかえり', 'お帰り'],
  'ただいま': ['ただいま', '只今'],
  'いってきます': ['いってきます', '行ってきます'],
  'いってらっしゃい': ['いってらっしゃい'],

  // テクノロジー
  'でんわ': ['電話'], 'けいたいでんわ': ['携帯電話'],
  'すまーとふぉん': ['スマートフォン'],
  'パソコン': ['パソコン'], 'ぱそこん': ['パソコン'],
  'いんたーねっと': ['インターネット'],
  'でんき': ['電気', '電機'],
  'かがく': ['科学', '化学'],
  'ぎじゅつ': ['技術'],
  'アプリ': ['アプリ'], 'あぷり': ['アプリ', '応用'],
  'ソフトウェア': ['ソフトウェア'], 'そふとうぇあ': ['ソフトウェア'],
  'ハードウェア': ['ハードウェア'],

  // 外来語・カタカナ語（カタカナ優先）
  'てれび': ['テレビ'],
  'すまほ': ['スマホ'],
  'こーひー': ['コーヒー'],
  'じゅーす': ['ジュース'],
  'びーる': ['ビール'],
  'わいん': ['ワイン'],
  'ぴざ': ['ピザ'],
  'けーき': ['ケーキ'],
  'ちょこれーと': ['チョコレート'],
  'あいすくりーむ': ['アイスクリーム'],
  'はんばーがー': ['ハンバーガー'],
  'さんどいっち': ['サンドイッチ'],
  'ぱすた': ['パスタ'],
  'ほてる': ['ホテル'],
  'れすとらん': ['レストラン'],
  'こんびに': ['コンビニ'],
  'めーる': ['メール'],
  'ふぁいる': ['ファイル'],
  'うぇぶ': ['ウェブ'],
  'げーむ': ['ゲーム'],
  'こんぴゅーた': ['コンピュータ'],
  'かめら': ['カメラ'],
  'すくりーん': ['スクリーン'],
  'きーぼーど': ['キーボード'],
  'ばってりー': ['バッテリー'],
  'さーば': ['サーバ', 'サーバー'],
  'でーた': ['データ'],
  'くらうど': ['クラウド'],
  'ねっと': ['ネット'],
  'かーど': ['カード'],
  'ぺーじ': ['ページ'],
  'ぶらうざ': ['ブラウザ'],
  'さいと': ['サイト'],
  'あかうんと': ['アカウント'],
  'ぱすわーど': ['パスワード'],
  'あぷりけーしょん': ['アプリケーション'],
  'でざいん': ['デザイン'],
  'さーびす': ['サービス'],
  'こんてんつ': ['コンテンツ'],
  'ちーむ': ['チーム'],
  'ちゃんす': ['チャンス'],
  'すきる': ['スキル'],
  'ぼーなす': ['ボーナス'],
  'てくのろじー': ['テクノロジー'],
  'えねるぎー': ['エネルギー'],
  'じゃあなる': ['ジャーナル'],
  'ぺっと': ['ペット'],
  'ぱーてぃー': ['パーティー'],
  'ぱーてぃ': ['パーティ', 'パーティー'],
  'きっちん': ['キッチン'],
  'べっど': ['ベッド'],
  'そふぁ': ['ソファ', 'ソファー'],
  'てーぶる': ['テーブル'],
  'しゃわー': ['シャワー'],
  'といれ': ['トイレ'],
  'まんしょん': ['マンション'],
  'あぱーと': ['アパート'],
  'にゅーす': ['ニュース'],
  'すぽーつ': ['スポーツ'],
  'おんらいん': ['オンライン'],
  'うぃるす': ['ウイルス'],
  'すとれす': ['ストレス'],
  'いめーじ': ['イメージ'],
  'すたいる': ['スタイル'],
  'えにめ': ['アニメ'],
  'あにめ': ['アニメ'],
  'まんが': ['漫画', 'まんが', 'マンガ'],
  'むーびー': ['ムービー', '映画'],
  'らいぶ': ['ライブ'],
  'こんさーと': ['コンサート'],
  'おーでぃお': ['オーディオ'],
  'びでお': ['ビデオ', '動画'],
  'もーど': ['モード'],
  'すてーたす': ['ステータス'],
  'れべる': ['レベル'],
  'いんすとーる': ['インストール'],
  'でりーと': ['デリート'],
  'こぴー': ['コピー'],
  'ぺーすと': ['ペースト'],
  'せーぶ': ['セーブ', '保存'],
  'ろーど': ['ロード', '読み込み'],
  'あっぷでーと': ['アップデート'],
  'あっぷろーど': ['アップロード'],
  'だうんろーど': ['ダウンロード'],

  // 頻出活用形（SKK辞書の順序が不自然なものを上書き）
  'なった': ['成った', 'なった', '鳴った'],
  'いった': ['行った', '言った', 'いった'],
  'きた': ['来た', 'きた'],
  'いきたい': ['行きたい', '生きたい', 'いきたい'],
  'みたい': ['みたい', '見たい'],
  'したい': ['したい', '仕たい'],
  'うれしい': ['嬉しい', 'うれしい'],
  'おいしい': ['美味しい', 'おいしい'],
  'かなしい': ['悲しい', 'かなしい'],
  'さびしい': ['寂しい', 'さびしい'],
  'むずかしい': ['難しい', 'むずかしい'],
  'おもしろい': ['面白い', 'おもしろい'],
  'まじめ': ['真面目', 'まじめ'],
  'なにか': ['何か', 'なにか'],
  'だれか': ['誰か', 'だれか'],
  'どこか': ['どこか', '何処か'],
  'なんで': ['なんで', '何で'],
  'そんな': ['そんな', '然な'],
  'こんな': ['こんな', '然な'],
  'あんな': ['あんな', '然な'],
  'どんな': ['どんな'],
  'ちゃんと': ['ちゃんと'],
  'やっぱり': ['やっぱり', 'やはり'],
  'やはり': ['やはり', 'やっぱり'],
  'ちょっと': ['ちょっと', '一寸'],
  'もっと': ['もっと'],
  'ずっと': ['ずっと'],
  'きっと': ['きっと', '必ず'],
  'やっと': ['やっと', 'ようやく'],
  'ほんとう': ['本当', 'ほんとう'],
  'ほんと': ['本当', 'ほんと'],
  'すごく': ['すごく', '凄く'],
  'めちゃ': ['めちゃ'],
  'とても': ['とても', '大変'],
  'すごい': ['凄い', 'すごい'],
  'たくさん': ['たくさん', '沢山'],
  'いっぱい': ['一杯', 'いっぱい'],
  'ありがと': ['ありがと'],
  'おねがい': ['お願い', 'おねがい'],
  'おねがいします': ['お願いします', 'おねがいします'],
  'わかった': ['分かった', 'わかった'],
  'わかる': ['分かる', '解る', 'わかる'],
  'おもう': ['思う', 'おもう'],
  'かんじる': ['感じる', 'かんじる'],
  'かんがえる': ['考える', 'かんがえる'],
  'いそがしい': ['忙しい', 'いそがしい'],
  'たいへん': ['大変', 'たいへん'],
  'じゃない': ['じゃない', 'ではない'],
  'じゃなくて': ['じゃなくて', 'ではなくて'],
  'だって': ['だって', '何故なら'],
  'つまり': ['つまり', '即ち'],
  'やばい': ['やばい', 'ヤバい'],
  'かわいい': ['可愛い', 'かわいい'],
  'かっこいい': ['格好いい', 'かっこいい'],
  'うまい': ['上手い', '旨い', 'うまい'],
  'へた': ['下手', 'へた'],
  'なるほど': ['なるほど', '成る程'],

  // 助詞・機能語（かな自体が候補）
  'は': ['は'], 'が': ['が'], 'を': ['を'],
  'に': ['二', '似', '荷', '２', 'に'],
  'で': ['で'], 'と': ['と', '都', '十'],
  'から': ['から', '空', '殻', '柄'],
  'まで': ['まで', '迄'],
  'より': ['より', '依り'],
  'の': ['の'], 'も': ['も'],
  'か': ['か'], 'ね': ['ね', '根', '音'],
  'よ': ['よ'],

  // 数え方
  'ひとつ': ['一つ'], 'ふたつ': ['二つ'],
  'みっつ': ['三つ'], 'よっつ': ['四つ'],
  'いつつ': ['五つ'], 'むっつ': ['六つ'],
  'ななつ': ['七つ'], 'やっつ': ['八つ'],
  'ここのつ': ['九つ'], 'とお': ['十'],

  // 接続詞・副詞
  'でも': ['でも', '何でも'],
  'しかし': ['しかし', '然し'],
  'だから': ['だから', '何故なら'],
  'そして': ['そして'],
  'また': ['また', '又', '再び'],
  'もう': ['もう', '最早'],
  'まだ': ['まだ', '未だ'],
  'すでに': ['すでに', '既に'],
  'よく': ['よく', '良く'],
  'たとえば': ['例えば'],
  'たぶん': ['たぶん', '多分'],
  'もちろん': ['もちろん', '勿論'],
};

export class KanaKanjiConverter {
  private static supplementaryDict: Record<string, string[]> = {};
  private static learned: Record<string, Record<string, number>> = {};
  private static userDict: Record<string, string[]> = {};
  // Developer-curated dictionary bundled as rawfile/global_dict.json. Highest priority.
  private static globalDict: Record<string, string[]> = {};

  // Particles and auxiliaries kept as kana in auto-convert and preferred during DP traceback
  private static readonly FUNCTION_WORDS: Record<string, boolean> = {
    'は': true, 'が': true, 'を': true, 'に': true, 'で': true,
    'も': true, 'と': true, 'の': true, 'へ': true, 'や': true,
    'から': true, 'まで': true, 'より': true, 'ほど': true,
    'くらい': true, 'ぐらい': true, 'ばかり': true, 'など': true,
    'なんか': true, 'しか': true, 'だけ': true, 'さえ': true, 'こそ': true,
    'か': true, 'ね': true, 'よ': true, 'ぞ': true, 'わ': true, 'な': true,
    'て': true, 'ば': true, 'のに': true, 'ので': true,
    'けど': true, 'けれど': true, 'けれども': true, 'ながら': true, 'たり': true,
    'ために': true, 'ように': true,
    'た': true, 'ない': true, 'だ': true, 'じゃ': true, 'かな': true,
    'なく': true, 'なくて': true, 'なかった': true, 'なければ': true,
    'たい': true, 'たく': true, 'たくて': true,
    'いる': true, 'ある': true, 'する': true, 'なる': true, 'くる': true,
    'こと': true, 'もの': true, 'とき': true, 'ところ': true, 'ほう': true,
    'これ': true, 'それ': true, 'あれ': true, 'どれ': true,
    'です': true, 'ます': true, 'ません': true, 'でした': true, 'ました': true,
    'でしょう': true, 'ましょう': true, 'だろう': true, 'だろ': true,
    'ください': true, 'ちゃう': true, 'てる': true, 'でる': true,
    // 否定・打消し系
    'もない': true, 'でもない': true, 'ではない': true, 'じゃない': true,
    'でしかない': true, 'しかない': true, 'ことない': true, 'ことはない': true,
    'なくちゃ': true, 'なきゃ': true, 'なければならない': true, 'ねばならない': true,
    'ずに': true, 'ずには': true, 'ぬ': true,
    // 推量・伝聞・様態
    'かも': true, 'かもしれない': true, 'かもしれません': true, 'かもね': true,
    'みたい': true, 'みたいな': true, 'みたいに': true, 'らしい': true,
    'そう': true, 'そうだ': true, 'そうです': true, 'ようだ': true, 'ような': true,
    'はず': true, 'はずだ': true, 'わけ': true, 'わけだ': true, 'べき': true,
    'つもり': true, 'まま': true, 'ところで': true, 'ところが': true,
    // 接続・引用
    'という': true, 'といった': true, 'とか': true, 'って': true, 'ったって': true,
    'なんて': true, 'なんと': true, 'だって': true, 'たって': true,
    'のだ': true, 'んだ': true, 'のです': true, 'んです': true, 'のである': true,
    'だが': true, 'ですが': true, 'だけど': true, 'だけれど': true,
    'および': true, 'または': true, 'ただし': true, 'なお': true,
    // 補助動詞・アスペクト
    'ている': true, 'ていた': true, 'ています': true, 'てた': true,
    'ておく': true, 'とく': true, 'てしまう': true, 'ちゃった': true,
    'てみる': true, 'ていく': true, 'てくる': true, 'てきた': true,
    'すぎる': true, 'すぎ': true, 'がち': true, 'っぽい': true,
    // 副助詞・その他
    'ずつ': true, 'ごと': true, 'つつ': true, 'だらけ': true, 'まみれ': true,
    'ても': true, 'でも': true, 'のような': true, 'のように': true,
    'ながらも': true, 'つつも': true, 'からこそ': true, 'ばこそ': true,
    'やつ': true, 'もん': true, 'わけではない': true, 'というか': true,
  };

  static loadDictionary(dict: Record<string, string[]>): void {
    KanaKanjiConverter.supplementaryDict = dict;
  }

  static setUserDict(dict: Record<string, string[]>): void {
    KanaKanjiConverter.userDict = dict;
  }

  static setGlobalDict(dict: Record<string, string[]>): void {
    KanaKanjiConverter.globalDict = dict;
  }

  static setLearned(data: Record<string, Record<string, number>>): void {
    KanaKanjiConverter.learned = data;
  }

  static getLearned(): Record<string, Record<string, number>> {
    return KanaKanjiConverter.learned;
  }

  static recordChoice(kana: string, candidate: string): void {
    if (kana.length === 0 || candidate.length === 0 || candidate === kana) { return; }
    if (!KanaKanjiConverter.learned[kana]) {
      if (Object.keys(KanaKanjiConverter.learned).length >= 500) { return; }
      KanaKanjiConverter.learned[kana] = {};
    }
    const entry = KanaKanjiConverter.learned[kana];
    if (entry[candidate] !== undefined || Object.keys(entry).length < 5) {
      entry[candidate] = (entry[candidate] ?? 0) + 1;
    }
  }

  private static applyLearning(kana: string, cands: string[]): string[] {
    const counts = KanaKanjiConverter.learned[kana];
    if (!counts || Object.keys(counts).length === 0) { return cands; }
    const boosted = cands.filter((c: string) => (counts[c] ?? 0) > 0)
      .sort((a: string, b: string) => (counts[b] ?? 0) - (counts[a] ?? 0));
    const rest = cands.filter((c: string) => (counts[c] ?? 0) === 0);
    return [...boosted, ...rest];
  }

  // Prepend user-registered words (deduped), keeping them ahead of dict order.
  // Prepend the words of a registered dictionary (deduped), keeping them ahead.
  private static withRegisteredWords(
    registered: string[] | undefined,
    list: string[]
  ): string[] {
    if (!registered || registered.length === 0) { return list; }
    const rest = list.filter((c: string) => !registered.includes(c));
    return [...registered, ...rest];
  }

  lookup(kana: string): string[] {
    const entry = DICTIONARY[kana];
    const ext = KanaKanjiConverter.supplementaryDict[kana];
    const user = KanaKanjiConverter.userDict[kana];
    const global = KanaKanjiConverter.globalDict[kana];
    const kata = KanaKanjiConverter.toKatakana(kana);
    let cands: string[];

    if (entry && entry.length > 0) {
      cands = [...entry];
      if (ext && ext.length > 0) {
        for (const c of ext) {
          if (!cands.includes(c)) { cands.push(c); }
        }
      }
      if (kata !== kana && !cands.includes(kata)) { cands.push(kata); }
      if (!cands.includes(kana)) { cands.push(kana); }
    } else if (ext && ext.length > 0) {
      cands = [...ext];
      if (kata !== kana && !cands.includes(kata)) { cands.push(kata); }
      if (!cands.includes(kana)) { cands.push(kana); }
    } else if ((user && user.length > 0) || (global && global.length > 0)) {
      // Only a registered dictionary (user/global) knows this reading.
      cands = [];
      if (kata !== kana) { cands.push(kata); }
      if (!cands.includes(kana)) { cands.push(kana); }
      // global leads user; both prepended ahead of the katakana/kana fallback.
      const withUser = KanaKanjiConverter.withRegisteredWords(user, cands);
      return KanaKanjiConverter.withRegisteredWords(global, withUser);
    } else {
      // Not in any dict: katakana first (handles loanwords not yet in dict)
      return kata !== kana ? [kata, kana] : [kana];
    }

    const filtered = KanaKanjiConverter.filterCandidates(kana, cands);
    // Function words (particles/auxiliaries) default to hiragana, not rare kanji
    // (e.g. ない should lead with かな, not 綯い).
    let ordered: string[];
    if (KanaKanjiConverter.FUNCTION_WORDS[kana] && filtered[0] !== kana) {
      const reordered = filtered.filter((c: string) => c !== kana);
      reordered.unshift(kana);
      ordered = KanaKanjiConverter.applyLearning(kana, reordered);
    } else {
      ordered = KanaKanjiConverter.applyLearning(kana, filtered);
    }
    // Registered words always lead: user first, then global prepended → global wins.
    const withUser = KanaKanjiConverter.withRegisteredWords(user, ordered);
    return KanaKanjiConverter.withRegisteredWords(global, withUser);
  }

  // Returns the best single conversion: keeps kana for function words, else first lookup candidate.
  autoConvert(kana: string): string {
    if (KanaKanjiConverter.FUNCTION_WORDS[kana]) {
      return kana;
    }
    return this.lookup(kana)[0];
  }

  // Convert hiragana to katakana (U+3041-U+3096 → U+30A1-U+30F6, offset 0x60).
  static toKatakana(hiragana: string): string {
    let result = '';
    for (let i = 0; i < hiragana.length; i++) {
      const code = hiragana.charCodeAt(i);
      result += (code >= 0x3041 && code <= 0x3096)
        ? String.fromCharCode(code + 0x60)
        : hiragana[i];
    }
    return result;
  }

  // Remove half-width katakana and pure-ASCII romaji only.
  // Full-width katakana is always kept (loanwords need カタカナ even when kanji exists).
  private static filterCandidates(kana: string, cands: string[]): string[] {
    const filtered = cands.filter(c => {
      if (/^[ｦ-ﾟ]+$/.test(c)) { return false; } // half-width katakana
      if (/^[A-Za-zÀ-ɏ]+$/.test(c)) { return false; } // romaji / latin
      return true;
    });
    return filtered.length > 0 ? filtered : [kana];
  }

  private inDict(sub: string): boolean {
    return !!(KanaKanjiConverter.globalDict[sub]
      || KanaKanjiConverter.userDict[sub]
      || KanaKanjiConverter.supplementaryDict[sub]
      || DICTIONARY[sub]);
  }

  // Returns true for kana that cannot start a Japanese word/morpheme.
  private static isNoStarter(c: string): boolean {
    return 'っゃゅょぁぃぅぇぉゎん'.indexOf(c) >= 0;
  }

  // Two-phase DP segmentation with backward DP validation.
  // Forward dp[i] = min segments to cover kana[0..i).
  // Backward bdp[j] = min segments to cover kana[j..n).
  // A segment at position i of length len is globally optimal iff dp[i]+1+bdp[i+len] == dp[n].
  // Traceback prefers function words, then longest dict match, among globally optimal segments.
  segment(kana: string): string[] {
    const n = kana.length;
    if (n === 0) { return []; }
    const INF = n + 1;
    const MAX_LEN = 10;

    // Forward DP
    const dp: number[] = [];
    for (let j = 0; j <= n; j++) { dp.push(INF); }
    dp[0] = 0;
    for (let i = 0; i < n; i++) {
      if (dp[i] === INF) { continue; }
      const maxLen = MAX_LEN < n - i ? MAX_LEN : n - i;
      for (let len = 1; len <= maxLen; len++) {
        const sub = kana.slice(i, i + len);
        if (this.inDict(sub) || len === 1) {
          const cost = dp[i] + 1;
          if (cost < dp[i + len]) { dp[i + len] = cost; }
        }
      }
    }

    // Backward DP
    const bdp: number[] = [];
    for (let j = 0; j <= n; j++) { bdp.push(INF); }
    bdp[n] = 0;
    for (let i = n - 1; i >= 0; i--) {
      const maxLen = MAX_LEN < n - i ? MAX_LEN : n - i;
      for (let len = 1; len <= maxLen; len++) {
        const sub = kana.slice(i, i + len);
        if (this.inDict(sub) || len === 1) {
          const cost = bdp[i + len] + 1;
          if (cost < bdp[i]) { bdp[i] = cost; }
        }
      }
    }

    const optTotal = dp[n];
    const segs: string[] = [];
    let i = 0;
    while (i < n) {
      const maxLen = MAX_LEN < n - i ? MAX_LEN : n - i;

      // Prefer the longest function word on a globally optimal path
      let fwChosen = 0;
      for (let len = 1; len <= maxLen; len++) {
        const sub = kana.slice(i, i + len);
        if (KanaKanjiConverter.FUNCTION_WORDS[sub]
            && dp[i] + 1 + bdp[i + len] === optTotal) {
          fwChosen = len;
        }
      }

      let chosen: number;
      if (fwChosen > 0) {
        chosen = fwChosen;
      } else {
        // No function word: take longest dict match on globally optimal path
        chosen = 1;
        for (let len = maxLen; len >= 1; len--) {
          const sub = kana.slice(i, i + len);
          if ((this.inDict(sub) || len === 1)
              && dp[i] + 1 + bdp[i + len] === optTotal) {
            chosen = len;
            break;
          }
        }
      }

      segs.push(kana.slice(i, i + chosen));
      i += chosen;
    }

    // Post-process: merge segments that start with a non-word-start kana into the previous segment.
    // e.g. ["い","っしょ"] → ["いっしょ"],  ["もっ","と"] is fine but ["も","っと"] → ["もっと"]
    const merged: string[] = [];
    for (const seg of segs) {
      if (merged.length > 0 && KanaKanjiConverter.isNoStarter(seg[0])) {
        merged[merged.length - 1] += seg;
      } else {
        merged.push(seg);
      }
    }
    return merged;
  }
}
