# shunti IME

HarmonyOS NEXT (6.1) 向け日本語入力メソッド (IME)

## 機能

- **ローマ字入力** → ひらがな自動変換（全パターン対応）
- **漢字変換** スペースキーで候補表示・選択
- **カタカナモード** ローマ字入力でカタカナに変換
- **英数字モード** 直接ラテン文字入力
- **モード切替** あ → ア → A のサイクル
- 画面回転対応（縦画面 / 横画面）

## 入力方法

| 操作 | 動作 |
|------|------|
| ローマ字タイプ | かな変換しながら composing バッファに蓄積 |
| スペース | かな→漢字変換候補を表示 / 次の候補へ |
| 候補タップ | その候補を確定して挿入 |
| エンター | composing テキストをそのまま確定 |
| バックスペース | 1文字削除 / 変換キャンセル |
| あ/ア/A ボタン | 入力モード切替 |

## プロジェクト構成

```
entry/src/main/ets/
├── inputmethodextability/InputMethodExtAbility.ets  ← IME エントリ
├── ime/
│   ├── KeyboardController.ets   ← パネル管理 + InputHandler
│   ├── JapaneseConverter.ets    ← ローマ字→かな FSM
│   └── KanaKanjiConverter.ets   ← かな→漢字辞書
├── pages/KeyboardPage.ets       ← パネル UI ページ
└── components/
    ├── KeyboardView.ets          ← QWERTY キーボード
    └── CandidateBar.ets         ← 変換候補バー
```

## ビルド・インストール

DevEco Studio で開き、HarmonyOS NEXT 実機 or エミュレータにデプロイ。  
設定 → 言語入力 → キーボード → **shunti IME** を選択して有効化。

### 辞書の再生成

`dict.json` は SKK-JISYO.L から自動生成されます。更新する場合:

```bash
curl "https://raw.githubusercontent.com/skk-dev/dict/master/SKK-JISYO.L" -o /tmp/SKK-JISYO.L
python3 tools/skk_convert.py
```

## ライセンス

### アプリコード

本プロジェクト独自のソースコード（`.ets` ファイル等）は MIT ライセンスです。

### 変換辞書 (dict.json)

`entry/src/main/resources/rawfile/dict.json` は [SKK-JISYO.L](https://github.com/skk-dev/dict) を変換したものです。

**GNU General Public License v2.0 以降** が適用されます。

> Copyright (C) 1988-1995, 1997, 1999-2014  
> Masahiko Sato, Hironobu Takahashi, and SKK Development Team \<skk@ring.gr.jp\>  
> Source: https://github.com/skk-dev/dict

詳細は [NOTICE](./NOTICE) および [LICENSES/GPL-2.0.txt](./LICENSES/GPL-2.0.txt) を参照してください。
