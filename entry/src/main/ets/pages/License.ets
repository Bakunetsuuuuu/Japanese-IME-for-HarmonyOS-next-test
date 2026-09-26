import { LegalDocView } from '../components/LegalDocView';

@Entry
@Component
struct License {
  private readonly bodyText: string =
    'shunti Japanese IME\n\n' +
    '■ 変換辞書 (dict.json, global_dict.json)\n' +
    '独自収集データを使用しています。\n' +
    '・常用漢字（文部科学省告示、パブリックドメイン）\n' +
    '・Unicode Unihan データベース（パブリックドメイン）\n' +
    '・Wikipedia日本語版から収集した読み情報（CC BY-SA 4.0）\n' +
    '・Wiktionary日本語版から収集した読み情報\n' +
    '  （CC BY-SA 4.0 / GFDL、ja.wiktionary.org）\n' +
    '・JMdict/EDICT（電子化辞書研究開発グループ、CC BY-SA 4.0）\n' +
    '  https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project\n' +
    '・日本郵便 郵便番号データ\n' +
    '・独自収録語彙（global_dict）\n\n' +
    '詳細な出典一覧は DATA_SOURCES.md を参照してください。\n\n' +
    '■ 文節分割\n' +
    '外部データファイルには依存せず、文法ルールをアプリ内に実装した\n' +
    '独自のViterbiアルゴリズムで分割しています。\n\n' +
    '■ 統計データ変換エンジン (mozc_dict.json 等, 設定でオプション有効化)\n' +
    '上記の独自辞書とは完全に別データの、切り替え式の第二変換エンジンです。\n' +
    '・mozc（Google, BSD-3-Clause）\n' +
    '  https://github.com/google/mozc\n' +
    '・JMdict/EDICT（電子化辞書研究開発グループ、CC BY-SA 4.0）\n' +
    '  https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project\n' +
    '・SudachiDict（Works Applications, Apache License 2.0）\n' +
    '  https://github.com/WorksApplications/SudachiDict\n' +
    '詳細なライセンス全文は THIRD_PARTY_NOTICES.md を参照してください。\n\n' +
    '■ AI変換 (shuntelligence / shuntorge)\n' +
    '・shuntelligence（変換モデル、shuntilettuce、CC BY 4.0）\n' +
    '  https://creativecommons.org/licenses/by/4.0/\n' +
    '・shuntorge（AI変換の辞書）: 独自部分は MIT。以下を含みます\n' +
    '  mozc（Google, BSD-3-Clause、IPAdic 由来の辞書データを含む）\n' +
    '  SudachiDict（Works Applications, Apache License 2.0、読みの一部）\n' +
    '  日本郵便 郵便番号データ（地名の照合）\n' +
    '学習のコードと教材は公開していません。学習に使った文章の出典は DATA_SOURCES.md を参照してください。\n\n' +
    '■ アプリコード\n' +
    'MIT License\n\n' +
    '■ 開発\n' +
    '開発者: Shunti (X: @shunti_nitijou)\n' +
    '協力者: Hashima';

  build() {
    Column() {
      LegalDocView({
        pageTitle: 'ライセンス',
        bodyText: this.bodyText
      })
    }
    .width('100%')
    .height('100%')
  }
}
