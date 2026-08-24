# shunti Japanese IME プライバシーポリシー

**日本語** | [English](privacy-policy-en) | [中文](privacy-policy-zh)

最終更新: 2026年6月

- **アプリ名**: shunti Japanese IME
- **開発者名**: shuntilettuce

---

## はじめに

shunti Japanese IME（以下「本アプリ」）は、開発者 shuntilettuce が提供する HarmonyOS NEXT 向けの日本語入力メソッド（IME）です。本ポリシーは、本アプリにおけるデータの取り扱いについて説明します。

---

## データの収集について

**本アプリは、ユーザーの個人情報を一切収集しません。** 入力内容・変換履歴・登録単語などを外部サーバーへ送信・アップロード・収集することはありません。すべての処理はユーザーのデバイス内で完結します。

---

## デバイス内で処理されるデータ

本アプリは、日本語入力機能を提供するために、以下のデータを**デバイス内でのみ**処理します。これらが外部に送信されることはありません。

- **入力テキスト** — かな漢字変換と候補表示のためにデバイス内で処理されます。変換確定後に保持されることはありません。
- **変換履歴** — 変換精度を向上させる学習のために、デバイス内の Preferences（ローカルストレージ）にのみ保存されます。
- **ユーザー登録単語** — ユーザーが任意で登録した「よみ→単語」のペアが、デバイス内にのみ保存されます。

---

## データの保存と削除

変換履歴・ユーザー登録単語は HarmonyOS の Preferences API を使用してデバイス内のみに保存されます。

- **クラウドへの保存**: 行いません
- **データの削除**: アプリのアンインストールにより、保存されたすべてのデータが削除されます

---

## 第三者への提供

本アプリは、ユーザーの入力データ・変換履歴・ユーザー辞書を、いかなる第三者にも提供・販売・共有しません。

---

## バンドルデータ（辞書ファイル）

本アプリには以下の変換辞書データが含まれています。これらは**読み取り専用**のデータファイルであり、ユーザーの入力内容とは無関係です。

| ファイル | 出典 | ライセンス |
|---------|------|-----------|
| dict.json, global_dict.json | 常用漢字（文部科学省告示）／Unicode Unihan データベース／独自収録の語彙・読み | パブリックドメイン／自作 |
| mozc_dict.json, mozc_costs.json, mozc_matrix.json | mozc（Google）の変換辞書・連接コストデータ／JMdict・SudachiDictによる漢字表記の補強 | BSD-3-Clause／CC BY-SA 4.0／Apache License 2.0 |

詳細な出典・ライセンス全文は [`DATA_SOURCES.md`](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next/blob/main/DATA_SOURCES.md) および [`THIRD_PARTY_NOTICES.md`](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next/blob/main/THIRD_PARTY_NOTICES.md) を参照してください。

---

## クラッシュレポート・分析ツール

本アプリは分析ツール・クラッシュレポートサービス・広告 SDK を一切使用していません。

---

## お子様のプライバシー

本アプリはいかなるユーザーからも個人情報を収集しないため、13 歳未満のお子様の個人情報を収集することもありません。

---

## ポリシーの変更

本プライバシーポリシーは予告なく変更される場合があります。重要な変更がある場合はアプリのアップデートを通じてお知らせします。

---

## お問い合わせ

プライバシーに関するご質問は、Huawei AppGallery の開発者情報に記載のメールアドレスまでお問い合わせください。

---

*このページは [shunti Japanese IME GitHub リポジトリ](https://github.com/shuntilettuce/japanese-ime-for-harmonyos-next) により管理されています。*
