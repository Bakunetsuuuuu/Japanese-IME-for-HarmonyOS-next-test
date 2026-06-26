# shunti Japanese IME — HarmonyOS NEXT 日本語入力

HarmonyOS NEXT (API 12+) 向けの日本語 IME です。フリック入力・QWERTY ローマ字入力の両方に対応し、SKK-JISYO.L ベースの大規模辞書による高精度な漢字変換を提供します。

> **開発者**: shuntilettuce

---

## インストール

**Huawei AppGallery** から入手できます。

AppGallery で「shunti Japanese IME」を検索してインストール後、以下の手順で有効化してください。

**有効化手順：**
1. 設定 → 通用 → 输入法（言語と入力）→ デフォルト入力メソッド
2. 一覧に表示された **shunti Japanese IME** を選択

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
| **大規模辞書** | SKK-JISYO.L 由来 30 万エントリ超（地名・固有名詞辞書含む） |
| **変換学習** | 選んだ変換先の優先度を自動で上げ、次回から上位表示 |
| **ユーザー辞書** | アプリ本体から「よみ→単語」を登録、変換候補の先頭に表示 |
| **括弧変換** | 「かっこ」で `()` `「」` `【】` 等を入力。確定後カーソルが内側へ移動 |

### キーボード操作
| 機能 | 説明 |
|---|---|
| **長押し削除** | ⌫ 長押し 0.5秒後に 10文字/秒で連続削除 |
| **取り消し (↩)** | 直前に確定したテキストを削除して復元 |
| **カーソル移動** | ◄ ► キーでカーソル左右移動 |
| **記号パネル** | 約 300 種の記号・矢印・数学記号・全角文字 |
| **絵文字パネル** | 8 カテゴリ 512 種の絵文字 |

---

## プライバシーポリシー

- [日本語](https://shuntilettuce.github.io/japanese-ime-for-harmonyos-next/privacy-policy)
- [English](https://shuntilettuce.github.io/japanese-ime-for-harmonyos-next/privacy-policy-en)
- [中文](https://shuntilettuce.github.io/japanese-ime-for-harmonyos-next/privacy-policy-zh)

本アプリは入力内容・変換履歴を外部サーバーへ一切送信しません。すべての処理はデバイス内で完結します。

---

## ライセンス

### アプリコード

`.ets` ファイル等のアプリ独自コードは **MIT License** で提供します。  
ただし dict.json を含む配布物全体は GPL v2 の制約を受けます（下記参照）。

### 変換辞書 (dict.json)

`entry/src/main/resources/rawfile/dict.json` は [SKK-JISYO.L](https://github.com/skk-dev/dict) / SKK-JISYO.geo / SKK-JISYO.propernoun を変換・加工したものです。

**GNU General Public License v2.0 以降** が適用されます。

> Copyright (C) 1988-1995, 1997, 1999-2014  
> Masahiko Sato, Hironobu Takahashi, and SKK Development Team \<skk@ring.gr.jp\>  
> Source: https://github.com/skk-dev/dict

詳細は [NOTICE](./NOTICE) および [LICENSES/GPL-2.0.txt](./LICENSES/GPL-2.0.txt) を参照してください。

### 文節分割データ (reading_cost.json / matrix.json)

[mecab-ipadic](https://taku910.github.io/mecab/) 2.7.0 を加工したもので、Viterbi 文節分割に使用します。

**NAIST License**（商用利用可）が適用されます。

> Copyright 2000–2003 Nara Institute of Science and Technology (NAIST). All Rights Reserved.

詳細は [NOTICE](./NOTICE) および [LICENSES/mecab-ipadic-COPYING.txt](./LICENSES/mecab-ipadic-COPYING.txt) を参照してください。
