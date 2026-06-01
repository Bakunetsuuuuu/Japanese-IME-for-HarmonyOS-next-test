# shunti IME — HarmonyOS Next 日本語入力

HarmonyOS NEXT (API 12 / 6.1) 向けの日本語 IME です。フリック入力・QWERTY ローマ字入力の両方に対応し、SKK-JISYO.L ベースの大規模辞書による高精度な漢字変換を提供します。

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
| **リアルタイム候補表示** | 入力中にDP文節分割で自動変換候補を更新 |
| **スペース変換** | スペースで候補一覧表示 → 繰り返しで次候補へ |
| **文節変換モード** | 文全体を文節に分割して個別に変換先を選択 |
| **カタカナ変換** | 全文をカタカナに変換する候補を常に提供 |
| **大規模辞書** | SKK-JISYO.L 由来 20万エントリ超 |
| **変換学習** | 選んだ変換先の優先度を自動で上げ、次回から上位表示 |
| **ユーザー辞書** | アプリ本体から「よみ→単語」を登録、変換候補の先頭に表示 |

### キーボード操作
| 機能 | 説明 |
|---|---|
| **長押し削除** | ⌫ 長押し 0.5秒後に 10文字/秒で連続削除 |
| **取り消し (↩)** | 直前に確定したテキストを削除して復元 |
| **カーソル移動** | ◄ ► キーでカーソル左右移動 |
| **記号パネル** | 約300種の記号・矢印・数学記号・全角文字 |
| **絵文字パネル** | 8カテゴリ512種の絵文字 |

---

## スクリーンショット

| フリック入力 | 変換候補 | 記号パネル |
|---|---|---|
| ![フリック入力](docs/screenshots/flick-input.png) | ![変換候補](docs/screenshots/conversion.png) | ![記号パネル](docs/screenshots/symbol-panel.png) |

---

## インストール

[Releases](https://github.com/shuntilettuce/japanese-ime-for-harmonyos-next/releases) から `.zip` をダウンロードし、展開して `.app` を取り出してください。

**前提条件：**
1. 設定 → 端末情報 → バージョン番号を7回タップ → 開発者向けオプションを有効化
2. 設定 → 開発者向けオプション → **USB デバッグ をオン**
3. USB で PC に接続 → 端末側に「USB デバッグを許可しますか？」と出たら **許可**

**hdc でインストール：**

hdc（HarmonyOS Device Connector）は DevEco Studio に同梱されているコマンドラインツールです。  
まず hdc のパスを確認します：

- **DevEco Studio でパスを調べる：**  
  `File → Settings → HarmonyOS SDK` → 表示される SDK Location を確認  
  hdc は `<SDK Location>/default/openharmony/toolchains/hdc`（Windows は `.exe`）にあります

- **よくあるデフォルトパス：**
  - Mac: `~/Library/Huawei/Sdk/default/openharmony/toolchains/hdc`
  - Windows: `C:\Users\<ユーザー名>\AppData\Local\Huawei\Sdk\default\openharmony\toolchains\hdc.exe`

毎回フルパスを打つのが面倒な場合は、上記ディレクトリを環境変数 `PATH` に追加してください。

**インストール手順：**

```sh
# 1. デバイスが認識されているか確認（デバイス名が表示されれば OK）
hdc list targets

# 2. .app をインストール
hdc install JapaneseIMEforHarmonyOSnext-default-signed.app
```

> `[FAIL]` が出る場合は USB ケーブルを抜き差しして再試行してください。  
> それでも失敗する場合、端末側に「USB デバッグを許可しますか？」のダイアログが出ていないか確認してください。

**有効化：**  
設定 → 言語と入力 → キーボードの管理 → **shunti IME** をオン

---

## ソースからビルドする

開発者向け。DevEco Studio (API 20) でプロジェクトを開き、署名設定後に ▶ ボタンで実機にデプロイできます。

---

```
entry/src/main/ets/
├── inputmethodextability/
│   └── InputMethodExtAbility.ets   ← IME エントリポイント
├── entryability/
│   └── EntryAbility.ets            ← アプリ本体エントリポイント
├── ime/
│   ├── KeyboardController.ets      ← パネル管理・InputHandler・状態管理
│   ├── JapaneseConverter.ets       ← ローマ字→かな FSM
│   ├── KanaKanjiConverter.ets      ← かな→漢字変換・DP文節分割・学習
│   ├── UserDictStore.ets           ← ユーザー辞書の永続化（preferences）
│   └── JapaneseConverter.ets       ← toKatakana などユーティリティ
├── pages/
│   ├── KeyboardPage.ets            ← キーボード UI ページ（モード分岐）
│   └── Index.ets                   ← アプリ本体（ユーザー辞書登録 UI）
└── components/
    ├── FlickKeyboardView.ets        ← フリックキーボード
    ├── KeyboardView.ets             ← QWERTY キーボード
    ├── CandidateBar.ets             ← 変換候補バー
    ├── BunsetsuBar.ets              ← 文節変換バー
    ├── SymbolView.ets               ← 記号入力パネル
    └── EmojiView.ets                ← 絵文字入力パネル

tools/
└── skk_convert.py                  ← SKK-JISYO.L → dict.json 変換スクリプト
```

---

## ライセンス

### アプリコード

`.ets` ファイル等のアプリ独自コードは **MIT License** で提供します。  
ただし dict.json を含む配布物全体は GPL v2 の制約を受けます（下記参照）。

### 変換辞書 (dict.json)

`entry/src/main/resources/rawfile/dict.json` は [SKK-JISYO.L](https://github.com/skk-dev/dict) を変換・加工したものです。

**GNU General Public License v2.0 以降** が適用されます。

> Copyright (C) 1988-1995, 1997, 1999-2014  
> Masahiko Sato, Hironobu Takahashi, and SKK Development Team \<skk@ring.gr.jp\>  
> Source: https://github.com/skk-dev/dict

詳細は [NOTICE](./NOTICE) および [LICENSES/GPL-2.0.txt](./LICENSES/GPL-2.0.txt) を参照してください。
