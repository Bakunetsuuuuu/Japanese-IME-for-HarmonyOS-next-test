# 辞書データの出典一覧

`entry/src/main/resources/rawfile/dict.json` および `global_dict.json` の語彙は、
本プロジェクトの開発過程（複数セッションにわたる）で以下の外部データソースから
収集・編纂されました。個々のエントリに出典タグは付与されていないため
（28万件超の規模でエントリ単位のタグ付けは非現実的）、本ファイルが
出典追跡の唯一の記録です。git のコミット履歴と合わせて参照してください。

**免責事項**: 本ファイルは開発時点での把握内容をまとめたものであり、法的助言では
ありません。公開配布前には、特に JMdict（下記）のシェアアライク条項について
確認することを推奨します。

**関連ファイル**: `entry/src/main/resources/rawfile/mozc_dict.json` /
`mozc_costs.json` / `mozc_matrix.json`（設定でオプション有効化する第二変換
エンジン「統計データ」用、track Aとは完全に別データ）の出典は
`THIRD_PARTY_NOTICES.md` および `tools/mozc_data/README.md` を参照。JMdict
のみ両トラックで（別々の目的に）利用されているため、下記3.に両方の利用内容を
記載しています。

---

## 1. Wikipedia日本語版 (ja.wikipedia.org)

- **ライセンス**: CC BY-SA 4.0（一部旧版は3.0）
- **利用内容**: 記事本文を MeCab で形態素解析し、単語の「読み」を抽出。記事の
  文章そのものは保存・再配布していない（読み↔漢字の対応関係のみを抽出）。
  駅名・地名・専門用語カテゴリの網羅的収集に使用。
- **関連コミット**: `c38514d`〜`f1cb947`（本セッション、バッチ11〜16、駅・
  市区町村・廃駅・難語）、`db49fab`〜`021c4f1`（バッチ3〜10）、`edd5ab9`
  （Wikipedia corpus deep expansion）等
- **帰属表示**: アプリ内ライセンス画面（SymbolView.ets）・プライバシー
  ポリシー画面（PrivacyPolicy.ets）に記載済み

## 2. Wiktionary日本語版 (ja.wiktionary.org)

- **ライセンス**: CC BY-SA 4.0 + GFDL（デュアルライセンス）
- **利用内容**: 見出し語・読みの抽出（初期の dict.json 構築に使用）
- **関連コミット**: `4ff3f6e`, `48c59ba`, `a6cf6b0`, `2b45b58`, `a2cf1df`
- **帰属表示**: 記載済み — アプリ内ライセンス画面（`SymbolView.ets`）

## 3. JMdict/EDICT（電子化辞書研究開発グループ, EDRDG）

- **ライセンス**: Creative Commons Attribution-ShareAlike 4.0
- **利用内容 (track A, dict.json/global_dict.json)**: 「196K canonical
  dictionary, priority entries cross-referenced」として語彙収集に利用
- **利用内容 (track B, mozc_dict.json — 別セッション、後日追加)**:
  `tools/mozc_data/build_jmdict_augment.py` が、mozc/実ipadic統計データ
  エンジン（独自辞書とは完全に別データの、設定でオプション有効化する
  第二変換エンジン）向けに、既存の読みへの追加の候補表記（漢字表記の
  バリエーション）としてのみ利用。新しい読みキーの追加は一切行わない
  （DPのセグメンテーション挙動に影響を与えないための制約、詳細は
  `tools/mozc_data/build_jmdict_augment.py` のモジュールdocstring参照）。
- **関連コミット**: `1996469`（corpus blitz + JMdict expansion, track A）
- **帰属表示**: 記載済み — アプリ内ライセンス画面（`SymbolView.ets`
  「ⓘ ライセンス」、変換辞書セクションとtrack Bの統計データセクション
  両方）、`THIRD_PARTY_NOTICES.md`（track B分の全文条件を記載）、
  本ファイル。EDRDG公式要件（ソフトウェア／アプリでファイルを使用する
  場合、ドキュメント・宣伝資料・ウェブサイト等で使用と出典を明記する
  必要がある）を満たす。推奨URL:
  https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project
- **シェアアライク条項**: JMdict由来のデータを含む派生物（dict.json/
  global_dict.json の該当エントリ、および mozc_dict.json への追加候補）
  は CC BY-SA 4.0 の下で配布される（このリポジトリの他のデータ・コードは
  元々MIT/BSD等の互換ライセンスであり、抵触しない）。
- **定期更新要件**: EDRDG方針は「入手可能な最新版からのデータの定期的な
  更新手順」の実装を求めている。本プロジェクトは実行時取得ではなく
  ビルド時に静的アセットへ焼き込む方式のため、`tools/mozc_data/
  fetch_jmdict.py` を毎リリース前に再実行（キャッシュを消してから）
  して最新スナップショットを取り込む運用とする。

## 4. Aozora Bunko（青空文庫）

- **ライセンス**: 収録作品ごとに異なる（著作権保護期間満了＝パブリック
  ドメイン、または著作権者の許諾に基づく無料公開）
- **利用内容**: 古典文学作品から文語・難読語彙を収集
- **関連コミット**: `5172741`（Aozora+Wikipedia）, `1996469`（同上に言及）

## 5. 日本郵便 郵便番号データ (KEN_ALL.CSV)

- **ライセンス**: 日本郵便が無償公開する公共データ、自由利用可
- **利用内容**: 全国の町域名・読みの網羅的収集（区より細かい地名）
- **関連コミット**: `46e6ae1`（本セッション）
- **帰属表示**: アプリ内ライセンス画面に記載済み

## 6. 常用漢字表（文部科学省告示）

- **ライセンス**: パブリックドメイン（政府告示）
- **帰属表示**: アプリ内ライセンス画面に記載済み

## 7. Unicode Unihan データベース

- **ライセンス**: Unicode, Inc. のライセンス（データ利用は一般的に許可、
  Unicode社の利用条件表示が求められる場合がある）
- **帰属表示**: アプリ内ライセンス画面に記載済み

## 8. SudachiDict（Works Applications Co., Ltd.）

- **ライセンス**: Apache License 2.0
- **利用内容 (track B, mozc_dict.json のみ)**: `tools/mozc_data/
  build_sudachi_augment.py` が、統計データエンジン向けに、small/core
  レキシコンCSVから既存の読みへの追加の候補表記（漢字表記のバリエー
  ション）としてのみ利用。JMdictと同じ「新しい読みキーは追加しない」
  安全モード。track Aのdict.json/global_dict.jsonでは未使用。
- **帰属表示**: 記載済み — アプリ内ライセンス画面（`SymbolView.ets`
  「ⓘ ライセンス」track Bセクション）、`THIRD_PARTY_NOTICES.md`
  （全文条件を記載）、本ファイル。
- **注記**: Apache-2.0は許諾的ライセンスで、JMdictのCC BY-SAと異なり
  シェアアライク（同一ライセンスでの再配布）義務はない。帰属表示のみ
  required。

---

## 未対応の推奨アクション

1. ~~Wiktionary・JMdictの帰属表示をライセンス画面に追加~~ — 完了
   （両方ともアプリ内ライセンス画面に既に記載されていたことを本セッションで
   確認・修正。track B分のJMdict利用も新規に追記済み）
2. 可能であれば、今後の語彙拡充では出典を都度このファイルに追記する運用にする
