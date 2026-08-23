# shunti Japanese IME Privacy Policy

[日本語](privacy-policy) | **English** | [中文](privacy-policy-zh)

Last updated: June 2026

- **App name**: shunti Japanese IME
- **Developer**: shuntilettuce

---

## Introduction

shunti Japanese IME ("the App"), provided by the developer shuntilettuce, is a Japanese input method (IME) for HarmonyOS NEXT. This policy explains how the App handles data.

---

## Data Collection

**The App does not collect any personal information.** It does not transmit, upload, or collect your input, conversion history, registered words, or any other data to any external server. All processing takes place entirely on your device.

---

## Data Processed On Your Device

To provide its Japanese input functionality, the App processes the following data **only on your device**. This data is never sent externally.

- **Input text** — Processed on-device to generate kana-to-kanji conversions and candidates. It is not retained after a conversion is committed.
- **Conversion history** — Stored only in on-device Preferences (local storage) to learn and improve conversion accuracy.
- **User-registered words** — "Reading → word" pairs you optionally register, stored only on your device.

---

## Storage and Deletion

Conversion history and user-registered words are stored only on your device using the HarmonyOS Preferences API.

- **Cloud storage**: Not used.
- **Data deletion**: Uninstalling the App deletes all stored data.

---

## Disclosure to Third Parties

The App does not provide, sell, or share your input data, conversion history, or user dictionary with any third party.

---

## Bundled Data (Dictionary Files)

The App includes the following conversion dictionary data. These are **read-only** data files and are unrelated to your input.

| File | Source | License |
|------|--------|---------|
| dict.json, global_dict.json | Jōyō kanji (MEXT notification) / Unicode Unihan database / original vocabulary & readings | Public domain / original |
| mozc_dict.json, mozc_costs.json, mozc_matrix.json | mozc (Google) conversion dictionary & connection-cost data, augmented with kanji-spelling candidates from JMdict and SudachiDict | BSD-3-Clause / CC BY-SA 4.0 / Apache License 2.0 |

See [`DATA_SOURCES.md`](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next/blob/main/DATA_SOURCES.md) and [`THIRD_PARTY_NOTICES.md`](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next/blob/main/THIRD_PARTY_NOTICES.md) for full attribution and license text.

---

## Crash Reporting and Analytics

The App does not use any analytics tools, crash-reporting services, or advertising SDKs.

---

## Children's Privacy

Because the App does not collect personal information from any user, it does not collect personal information from children under the age of 13 either.

---

## Changes to This Policy

This privacy policy may be changed without prior notice. We will notify you of significant changes through App updates.

---

## Contact

For privacy-related questions, please contact the email address listed in the developer information on Huawei AppGallery.

---

*This page is maintained in the [shunti Japanese IME GitHub repository](https://github.com/shuntilettuce/japanese-ime-for-harmonyos-next).*
