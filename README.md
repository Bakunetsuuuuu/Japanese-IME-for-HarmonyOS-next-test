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
