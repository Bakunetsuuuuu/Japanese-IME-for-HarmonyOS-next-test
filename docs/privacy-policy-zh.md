# shunti Japanese IME 隐私政策

[日本語](privacy-policy) | [English](privacy-policy-en) | **中文**

最后更新：2026年6月

- **应用名称**：shunti Japanese IME
- **开发者名称**：shuntilettuce

---

## 前言

shunti Japanese IME（以下简称“本应用”），由开发者 shuntilettuce 提供，是一款面向 HarmonyOS NEXT 的日语输入法（IME）。本政策说明本应用对数据的处理方式。

---

## 关于数据收集

**本应用不收集任何个人信息。** 本应用不会将您的输入内容、转换历史、登记词语或任何其他数据发送、上传或收集到任何外部服务器。所有处理均在您的设备本地完成。

---

## 在设备本地处理的数据

为提供日语输入功能，本应用仅在**您的设备上**处理以下数据。这些数据绝不会向外部发送。

- **输入文本** —— 在设备本地处理，用于生成假名汉字转换及候选。转换确定后不会被保留。
- **转换历史** —— 仅保存在设备本地的 Preferences（本地存储）中，用于学习以提升转换准确度。
- **用户登记的词语** —— 您自行登记的“读音→词语”配对，仅保存在您的设备本地。

---

## 数据的存储与删除

转换历史与用户登记的词语通过 HarmonyOS 的 Preferences API 仅保存在您的设备本地。

- **云端存储**：不使用。
- **数据删除**：卸载本应用即可删除所有已保存的数据。

---

## 向第三方提供

本应用不会向任何第三方提供、出售或共享您的输入数据、转换历史或用户词典。

---

## 捆绑数据（词典文件）

本应用包含以下转换词典数据。它们是**只读**数据文件，与您的输入内容无关。

| 文件 | 来源 | 许可证 |
|------|------|--------|
| dict.json, global_dict.json | 常用汉字（日本文部科学省告示）／Unicode Unihan 数据库／自有收录词汇及读音 | 公有领域／自制 |
| mozc_dict.json, mozc_costs.json, mozc_matrix.json | mozc（Google）的转换词典与连接成本数据，并以 JMdict、SudachiDict 补充汉字候选 | BSD-3-Clause／CC BY-SA 4.0／Apache License 2.0 |

详细出处与完整许可证文本请参见 [`DATA_SOURCES.md`](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next/blob/claude/harmonyos-japanese-ime-app-3OaxO/DATA_SOURCES.md) 与 [`THIRD_PARTY_NOTICES.md`](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next/blob/claude/harmonyos-japanese-ime-app-3OaxO/THIRD_PARTY_NOTICES.md)。

---

## 崩溃报告与分析工具

本应用不使用任何分析工具、崩溃报告服务或广告 SDK。

---

## 儿童隐私

由于本应用不收集任何用户的个人信息，因此也不会收集 13 岁以下儿童的个人信息。

---

## 政策的变更

本隐私政策可能在不另行通知的情况下变更。如有重大变更，我们将通过应用更新进行通知。

---

## 联系方式

如有隐私相关问题，请通过华为 AppGallery 开发者信息中所列的电子邮件地址与我们联系。

---

*本页面由 [shunti Japanese IME GitHub 仓库](https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next) 维护。*
