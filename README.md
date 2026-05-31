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
| *(coming soon)* | *(coming soon)* | *(coming soon)* |

---

## ビルド & インストール

**必要環境**: DevEco Studio 5.x 以上、HarmonyOS Next API 12 以上の実機またはエミュレータ

```bash
# リポジトリをクローン
git clone https://github.com/shuntilettuce/japanese-ime-for-harmonyos-next.git

# DevEco Studio で開き、実機/エミュレータにデプロイ
# 設定 → 言語と入力 → キーボード → shunti IME を有効化
```

### 辞書の再生成

`dict.json` は SKK-JISYO.L から自動生成されます。最新辞書を取り込む場合:

```bash
curl "https://raw.githubusercontent.com/skk-dev/dict/master/SKK-JISYO.L" -o /tmp/SKK-JISYO.L
python3 tools/skk_convert.py
# → entry/src/main/resources/rawfile/dict.json が更新されます
```

---

## プロジェクト構成

```
entry/src/main/ets/
├── inputmethodextability/
│   └── InputMethodExtAbility.ets   ← IME エントリポイント
├── ime/
│   ├── KeyboardController.ets      ← パネル管理・InputHandler・状態管理
│   ├── JapaneseConverter.ets       ← ローマ字→かな FSM
│   ├── KanaKanjiConverter.ets      ← かな→漢字変換・DP文節分割
│   └── JapaneseConverter.ets       ← toKatakana などユーティリティ
├── pages/
│   └── KeyboardPage.ets            ← メイン UI ページ（モード分岐）
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
