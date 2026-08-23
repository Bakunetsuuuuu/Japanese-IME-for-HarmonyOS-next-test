# shunti Japanese IME — HarmonyOS NEXT 日本語入力

HarmonyOS NEXT (API 12+) 向けの日本語 IME です。フリック入力・QWERTY ローマ字入力の両方に対応し、独自辞書による高精度な漢字変換を提供します。広告なし・分析ツールなし・個人開発のオープンソースプロジェクトです。

> **開発者**: shuntilettuce
> **最新バージョン**: 1.5.2（[更新履歴](./CHANGELOG.md)）
> **ライセンス**: [MIT](./LICENSE)（バンドル辞書データは別ライセンス、下記参照）

## 開発支援のご案内

shunti IMEは広告なし・完全無料で個人が開発しているオープンソースプロジェクトです。
現在、日々の変換精度向上のために発生するAI利用コスト（API料金など）を個人で全て負担しており、開発継続のための資金が不足している状態です。

もし shunti を気に入っていただけましたら、開発継続のために缶コーヒー1杯分だけでもご支援（寄付）をいただけますと大変励みになります。

- **Buy Me a Coffee**: **[buymeacoffee.com/shunti](https://buymeacoffee.com/shunti)**
  クレジットカードなどに対応した支援サービスです。GitHubアカウントは不要で、缶コーヒー1杯分から気軽に、応援メッセージを添えて支援ができます。
- **GitHub Sponsors**: **[github.com/sponsors/shuntilettuce](https://github.com/sponsors/shuntilettuce)**
  GitHubアカウントがあればカード情報の入力だけで、月額の継続支援または一度きりの支援ができます。

いただいたご支援は変換精度向上のためのAI利用料等に充てさせていただきます。

---

## インストール

**Huawei AppGallery** から入手できます。

AppGallery で「shunti Japanese IME」を検索してインストール後、以下の手順で有効化してください。

**有効化手順：**
1. 設定 → システム → 入力方法 
2. 一覧に表示される **shunti Japanese IME** を選択

（メニュー名は端末の HarmonyOS バージョンにより多少異なる場合があります）

---

## 機能一覧

### 入力方式
| 機能 | 説明 |
|---|---|
| **フリック入力** | Gboard 風 4×5 レイアウト。上下左右フリックでかな入力 |
| **QWERTY ローマ字入力** | 全ローマ字パターン対応（っ/ん/拗音含む） |
| **モード切替** | ひらがな / カタカナ / 英数字をワンタップで切替 |
| **濁点・半濁点** | フリックキーで゛゜を即時付与・サイクル |

### 変換
| 機能 | 説明 |
|---|---|
| **リアルタイム候補表示** | 入力中に Viterbi 文節分割で自動変換候補を更新 |
| **スペース変換** | スペースで候補一覧表示 → 繰り返しで次候補へ |
| **文節変換モード** | 文全体を文節に分割して個別に変換先を選択 |
| **カタカナ変換** | 全文をカタカナに変換する候補を常に提供 |
| **独自辞書** | 常用漢字・Unicode Unihan・独自収集データによる変換辞書 |
| **変換エンジン切替** | 独自辞書（track A）、mozc 由来の統計データ（track B）、両方を融合するハイブリッド（デフォルト・β）の3方式を設定で切替可能。詳細は下記「変換エンジンの仕組み」参照 |
| **変換学習** | 選んだ変換先の優先度を自動で上げ、次回から上位表示 |
| **ユーザー辞書** | アプリ本体から「よみ→単語」＋品詞（名詞/動詞/形容詞/人名/地名）を登録。動詞・形容詞は活用形も自動で変換候補に |
| **括弧変換** | 「かっこ」で `()` `「」` `【】` 等を入力。確定後カーソルが内側へ移動 |

### キーボード操作
| 機能 | 説明 |
|---|---|
| **長押し削除** | ⌫ 長押し 0.5秒後に 10文字/秒で連続削除 |
| **カーソル移動** | ◄ ► キーでカーソル左右移動 |
| **記号パネル** | 約 300 種の記号・矢印・数学記号・全角文字 |
| **絵文字パネル** | 8 カテゴリ 512 種の絵文字 |
| **クリップボード** | コピーしたテキストを候補バーに表示してワンタップ貼り付け。画像・ファイルは対応アプリの貼り付け機能を呼び出し |
| **片手モード** | キーボード全体を左右どちらかに寄せて縮小表示 |
| **ダークモード** | 端末の設定に自動追従（手動切替なし） |

### 設定
キーボードパネルの ⚙ から開く設定画面で、キーボードレイアウト（QWERTY / フリック）・片手モード・変換エンジン・クリップボード履歴・アプリ内ブラウザでの GitHub 表示・寄付リンクなどを変更できます。

---

## 変換エンジンの仕組み

設定画面から3方式のかな漢字変換エンジンを切り替えられます。

| エンジン | 中身 | 特徴 |
|---|---|---|
| **独自辞書 (track A)** | 常用漢字・Unihan・独自収集語彙による手作りの辞書＋文法ルール実装のViterbi文節分割 | チャット的な口語表現や「ひだり→←」のような独自の変換規則に強い。外部データファイルに依存しない自前ロジック |
| **統計データ (track B)** | mozc（Google）の変換辞書・連接コストデータをベースに、JMdict/SudachiDictで漢字表記を補強 | 一般的な文章・固有名詞のカバレッジが広い |
| **ハイブリッド（デフォルト・β）** | 文節分割・第一候補選定は track B（mozc統計）で行いつつ、track A側の語順整理・学習結果を候補順に混ぜ込む | 両方の強みを両立させる現在のデフォルト。単語単体で変換したときも track A の並び替えが効くよう継続的に手を入れている |

変換の学習は選んだ候補の優先度を個人の入力履歴から自動で引き上げる仕組みで、上記どのエンジンでも共通して働きます。辞書の改善は実際の入力ログ（後述）を元に継続的に行っています。

---

## 開発

### 必要環境

- [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（HarmonyOS NEXT SDK, API 12+）
- Node.js（辞書生成・評価スクリプト用）
- 実機または HarmonyOS エミュレータ、`hdc`（HarmonyOS Device Connector、SDK同梱）

### ビルド

DevEco Studio でプロジェクトを開くか、CLI から:

```bash
# デバッグビルド (HAP)
hvigorw assembleHap --mode module -p product=default -p buildMode=debug

# 実機へインストール (デバッグ署名済みHAP)
hdc install <出力されたhapファイル>
```

### プロジェクト構成（抜粋）

```
entry/src/main/ets/
  ime/          変換エンジン本体・IME拡張のロジック
    KanaKanjiConverter.ets   かな漢字変換のコア（辞書lookup・学習・3エンジンのブレンド）
    KeyboardController.ets   InputMethodExtensionAbility側の入力制御・状態管理
    JapaneseConverter.ets    ローマ字/フリック入力の変換・文字種処理
    ConjugationEngine.ets    活用形の自動展開（ユーザー辞書登録時など）
    InputLog.ets             デバッグ専用の入力ログ収集（下記参照）
  components/    キーボードUI（フリック/QWERTY/記号/絵文字/設定画面 等）
  pages/         本体アプリ側の画面（設定・ユーザー辞書・プライバシーポリシー）
tools/
  mozc_data/     mozc/JMdict/SudachiDictから統計データエンジンの辞書を構築するスクリプト群
  ime-eval/      変換精度の回帰テスト（corpus_test*.js）
  blind-eval/    Google日本語入力との変換結果比較用コーパス・スコアラー
  check_debug_log.js   InputLog呼び出し箇所の棚卸し（リリース前チェック）
```

IME本体は `InputMethodExtensionAbility` として別プロセス（`:inputMethod`）で動作するため、本体アプリとはサンドボックスが分離されています（ユーザー辞書やログの読み書きが両側で別経路になっているのはこのため）。

### 変換精度の回帰テスト

辞書やロジックを変更した際は、既存コーパスでのスコアを必ず確認してください。

```bash
bun tools/mozc_data/compare_engines.js corpus_test9.js
bun tools/mozc_data/compare_engines.js corpus_test10.js
bun tools/mozc_data/compare_engines.js corpus_test11.js
```

### コントリビュート

Issue・Pull Request歓迎です。辞書データや変換ロジックに手を入れる変更は、上記の回帰テストで既存スコアが下がっていないことを確認のうえ送ってください。

---

## プライバシーポリシー

- [日本語](https://shuntilettuce.github.io/Japanese-IME-for-HarmonyOS-next/privacy-policy)
- [English](https://shuntilettuce.github.io/Japanese-IME-for-HarmonyOS-next/privacy-policy-en)
- [中文](https://shuntilettuce.github.io/Japanese-IME-for-HarmonyOS-next/privacy-policy-zh)

本体アプリ（ユーザー辞書画面）のフッターからも同じ内容を確認できます。

本アプリは入力内容・変換履歴を外部サーバーへ一切送信しません。すべての処理はデバイス内で完結します。

---

## 開発版のみの機能: 入力ログ収集

変換精度を実際の入力から測るため、**開発ビルドにのみ**入力ログ収集を入れてあります。
配布版（AppGallery のリリースビルド）には含めません。

- 記録: 読み・確定した表記・選んだ候補の番号・文節の区切りと選択・変換範囲の変更・候補削除・未知語学習・削除した文字
- 記録しない: パスワード等の secure field、クリップボードの内容
- 保存先: 端末内アプリサンドボックスの 1 ファイルのみ。送信は一切しない
- 閲覧・書き出し・消去: 本体アプリのフッター「入力ログ」から

収集コードは `entry/src/main/ets/ime/InputLog.ets` に閉じており、外部の呼び出し箇所は
すべて行末に `// [DEBUG-LOG]` が付いています。リリース前の手順:

```
node tools/check_debug_log.js   # 収集地点を全部列挙（未マークの参照があれば exit 1）
```

出力に並んだファイルを削除し、`// [DEBUG-LOG]` の付いた行を消したあと、
もう一度実行して「収集コードはありません（リリース可）」になることを確認します。

> 収集したログは private リポジトリを含め、git に入れないでください。
> clone・バックアップ・コラボレータに渡り、履歴からは消せません。

---

## ライセンス

### アプリコード

`.ets` ファイル等のアプリ独自コードは **MIT License** で提供します。

### 変換辞書 (dict.json, global_dict.json) — track A（デフォルトの独自辞書）

`entry/src/main/resources/rawfile/dict.json` / `global_dict.json` は以下のデータから構築した自作辞書です。詳細な出典は [`DATA_SOURCES.md`](./DATA_SOURCES.md) を参照してください。

- 常用漢字（文部科学省告示）— パブリックドメイン
- Unicode Unihan データベース — パブリックドメイン
- Wikipedia日本語版から収集した読み情報 — CC BY-SA 4.0
- Wiktionary日本語版から収集した読み情報 — CC BY-SA 4.0 / GFDL
- JMdict/EDICT（電子化辞書研究開発グループ）— CC BY-SA 4.0
- 日本郵便 郵便番号データ — 自由利用可
- 独自収録語彙（global_dict）

### 文節分割

外部データファイルには依存せず、文法ルールをアプリ内に実装した独自のViterbiアルゴリズムで分割しています（track A）。

### 統計データ変換エンジン (mozc_dict.json 等) — track B（設定でオプション有効化）

上記の独自辞書とは完全に別データの、切り替え式の第二変換エンジンです。

- mozc（Google）— BSD-3-Clause
- JMdict/EDICT（読みへの追加候補表記としてのみ利用）— CC BY-SA 4.0
- SudachiDict（Works Applications）— Apache License 2.0

ライセンス全文は [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) を参照してください。
