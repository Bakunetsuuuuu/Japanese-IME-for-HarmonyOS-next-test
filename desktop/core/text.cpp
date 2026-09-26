#include "text.h"

#include <cstdint>

namespace shunti {

u16 from_utf8(const std::string& s) {
    u16 o;
    o.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
        uint8_t b = uint8_t(s[i]);
        uint32_t c;
        int n;
        if (b < 0x80) { c = b; n = 1; }
        else if ((b >> 5) == 6) { c = b & 0x1F; n = 2; }
        else if ((b >> 4) == 14) { c = b & 0x0F; n = 3; }
        else if ((b >> 3) == 30) { c = b & 0x07; n = 4; }
        else { i++; o.push_back(0xFFFD); continue; }
        if (i + n > s.size()) { o.push_back(0xFFFD); break; }
        for (int k = 1; k < n; k++) c = (c << 6) | (uint8_t(s[i + k]) & 0x3F);
        i += n;
        if (c >= 0x10000) {
            c -= 0x10000;
            o.push_back(char16_t(0xD800 + (c >> 10)));
            o.push_back(char16_t(0xDC00 + (c & 0x3FF)));
        } else o.push_back(char16_t(c));
    }
    return o;
}

std::string to_utf8(const u16& s) {
    std::string o;
    o.reserve(s.size() * 3);
    for (size_t i = 0; i < s.size(); i++) {
        uint32_t c = s[i];
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < s.size() && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000) {
            c = 0x10000 + ((c - 0xD800) << 10) + (s[i + 1] - 0xDC00);
            i++;
        }
        if (c < 0x80) o.push_back(char(c));
        else if (c < 0x800) { o.push_back(char(0xC0 | (c >> 6))); o.push_back(char(0x80 | (c & 0x3F))); }
        else if (c < 0x10000) {
            o.push_back(char(0xE0 | (c >> 12)));
            o.push_back(char(0x80 | ((c >> 6) & 0x3F)));
            o.push_back(char(0x80 | (c & 0x3F)));
        } else {
            o.push_back(char(0xF0 | (c >> 18)));
            o.push_back(char(0x80 | ((c >> 12) & 0x3F)));
            o.push_back(char(0x80 | ((c >> 6) & 0x3F)));
            o.push_back(char(0x80 | (c & 0x3F)));
        }
    }
    return o;
}

u16 to_katakana(const u16& s) {
    u16 o = s;
    for (auto& c : o) if (is_hira(c)) c = char16_t(c + 0x60);
    return o;
}

u16 to_hiragana(const u16& s) {
    u16 o = s;
    for (auto& c : o) if (c >= 0x30A1 && c <= 0x30F6) c = char16_t(c - 0x60);
    return o;
}

namespace {
// 全角カタカナ (濁点・半濁点の無い形) と半角カナの組
const char16_t* FULL = u"ァアィイゥウェエォオカキクケコサシスセソタチッツテトナニヌネノハヒフヘホマミムメモャヤュユョヨラリルレロワヲンーヮヰヱヵヶ。、「」・";
const char16_t* HALF = u"ｧｱｨｲｩｳｪｴｫｵｶｷｸｹｺｻｼｽｾｿﾀﾁｯﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓｬﾔｭﾕｮﾖﾗﾘﾙﾚﾛﾜｦﾝｰﾜｲｴｶｹ｡､｢｣･";
const char16_t* VOICED = u"ガギグゲゴザジズゼゾダヂヅデドバビブベボ";
const char16_t* SEMI = u"パピプペポ";

int index_of(const char16_t* s, char16_t c) {
    for (int i = 0; s[i]; i++) if (s[i] == c) return i;
    return -1;
}
}  // namespace

u16 to_halfwidth_kana(const u16& s) {
    u16 o;
    for (char16_t c0 : to_katakana(s)) {
        char16_t c = c0;
        int i = index_of(FULL, c);
        if (i >= 0) { o.push_back(HALF[i]); continue; }
        if (index_of(VOICED, c) >= 0 && (i = index_of(FULL, char16_t(c - 1))) >= 0) { o.push_back(HALF[i]); o.push_back(0xFF9E); continue; }
        if (index_of(SEMI, c) >= 0 && (i = index_of(FULL, char16_t(c - 2))) >= 0) { o.push_back(HALF[i]); o.push_back(0xFF9F); continue; }
        if (c == 0x30F4) { o += u"ｳﾞ"; continue; }
        if (c == 0x30F7) { o += u"ﾜﾞ"; continue; }
        o += to_halfwidth_ascii(u16(1, c));
    }
    return o;
}

u16 to_fullwidth_ascii(const u16& s) {
    u16 o = s;
    for (auto& c : o) {
        if (c == u' ') c = 0x3000;
        else if (c > 0x20 && c < 0x7F) c = char16_t(c + 0xFEE0);
    }
    return o;
}

u16 to_halfwidth_ascii(const u16& s) {
    u16 o = s;
    for (auto& c : o) {
        if (c == 0x3000) c = u' ';
        else if (c > 0xFF00 && c < 0xFF5F) c = char16_t(c - 0xFEE0);
        else if (c == 0xFFE5) c = u'\\';
    }
    return o;
}

char16_t japanese_symbol(char16_t c) {
    switch (c) {
        case u',': return u'、';
        case u'.': return u'。';
        case u'[': return u'「';
        case u']': return u'」';
        case u'/': return u'・';
        case u'-': return u'ー';
        case u'\\': return 0xFFE5;   // ￥
        default: break;
    }
    if (c > 0x20 && c < 0x7F) return char16_t(c + 0xFEE0);
    return c;
}

}  // namespace shunti
