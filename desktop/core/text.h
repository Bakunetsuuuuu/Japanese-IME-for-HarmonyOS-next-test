// 文字の変換 (UTF-8 と UTF-16、ひらがな・カタカナ・半角カナ・全角英数)。PC 版 (Windows・Linux) で共通
#pragma once
#include <string>

namespace shunti {

using u16 = std::u16string;

u16 from_utf8(const std::string& s);
std::string to_utf8(const u16& s);

inline bool is_hira(char16_t c) { return c >= 0x3041 && c <= 0x3096; }
inline bool is_kata(char16_t c) { return c >= 0x30A1 && c <= 0x30F6; }
// かな漢字変換の読みになる字 (ひらがなと長音)
inline bool is_reading_char(char16_t c) { return is_hira(c) || c == 0x30FC || c == 0x3094; }
inline bool is_ascii_alnum(char16_t c) { return (c >= u'0' && c <= u'9') || (c >= u'a' && c <= u'z') || (c >= u'A' && c <= u'Z'); }

u16 to_katakana(const u16& s);
u16 to_hiragana(const u16& s);
// 全角カタカナ・ひらがな・記号 → 半角カナ (ガ → ｶﾞ)
u16 to_halfwidth_kana(const u16& s);
// ASCII → 全角 (空白は全角の空白)。ASCII 以外はそのまま
u16 to_fullwidth_ascii(const u16& s);
// 全角英数記号 → ASCII。それ以外はそのまま
u16 to_halfwidth_ascii(const u16& s);
// 打った ASCII の記号を、日本語入力のときの字に (, → 、 . → 。 [ → 「 など。それ以外の記号は全角に)
char16_t japanese_symbol(char16_t c);

}  // namespace shunti
