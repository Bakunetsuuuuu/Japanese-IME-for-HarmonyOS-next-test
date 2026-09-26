// 小さな JSON (学習とユーザー辞書のファイルを読み書きするだけ。Android 版と同じ形のファイルを使う)
#pragma once
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace shunti {
namespace json {

struct Value {
    enum Type { Null, Bool, Number, String, Array, Object } type = Null;
    bool b = false;
    double num = 0;
    std::string str;                                    // UTF-8
    std::vector<Value> arr;
    std::vector<std::pair<std::string, Value>> obj;     // 並びを保つ

    const Value* get(const std::string& k) const {
        for (auto& kv : obj) if (kv.first == k) return &kv.second;
        return nullptr;
    }
    std::string get_str(const std::string& k, const std::string& def = "") const {
        const Value* v = get(k);
        return v && v->type == String ? v->str : def;
    }
};

class Parser {
public:
    explicit Parser(const std::string& s) : s_(s) {}
    bool parse(Value& out) {
        ws();
        if (!value(out)) return false;
        ws();
        return i_ == s_.size();
    }

private:
    const std::string& s_;
    size_t i_ = 0;

    void ws() { while (i_ < s_.size() && (s_[i_] == ' ' || s_[i_] == '\t' || s_[i_] == '\n' || s_[i_] == '\r')) i_++; }
    bool lit(const char* w) {
        size_t n = std::char_traits<char>::length(w);
        if (s_.compare(i_, n, w) != 0) return false;
        i_ += n;
        return true;
    }
    static void put_utf8(std::string& o, unsigned c) {
        if (c < 0x80) o.push_back(char(c));
        else if (c < 0x800) { o.push_back(char(0xC0 | (c >> 6))); o.push_back(char(0x80 | (c & 0x3F))); }
        else if (c < 0x10000) { o.push_back(char(0xE0 | (c >> 12))); o.push_back(char(0x80 | ((c >> 6) & 0x3F))); o.push_back(char(0x80 | (c & 0x3F))); }
        else { o.push_back(char(0xF0 | (c >> 18))); o.push_back(char(0x80 | ((c >> 12) & 0x3F))); o.push_back(char(0x80 | ((c >> 6) & 0x3F))); o.push_back(char(0x80 | (c & 0x3F))); }
    }
    bool hex4(unsigned& v) {
        if (i_ + 4 > s_.size()) return false;
        v = 0;
        for (int k = 0; k < 4; k++) {
            char c = s_[i_++];
            v <<= 4;
            if (c >= '0' && c <= '9') v |= unsigned(c - '0');
            else if (c >= 'a' && c <= 'f') v |= unsigned(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') v |= unsigned(c - 'A' + 10);
            else return false;
        }
        return true;
    }
    bool string(std::string& o) {
        if (i_ >= s_.size() || s_[i_] != '"') return false;
        i_++;
        while (i_ < s_.size()) {
            char c = s_[i_++];
            if (c == '"') return true;
            if (c != '\\') { o.push_back(c); continue; }
            if (i_ >= s_.size()) return false;
            char e = s_[i_++];
            switch (e) {
                case '"': o.push_back('"'); break;
                case '\\': o.push_back('\\'); break;
                case '/': o.push_back('/'); break;
                case 'b': o.push_back('\b'); break;
                case 'f': o.push_back('\f'); break;
                case 'n': o.push_back('\n'); break;
                case 'r': o.push_back('\r'); break;
                case 't': o.push_back('\t'); break;
                case 'u': {
                    unsigned v;
                    if (!hex4(v)) return false;
                    if (v >= 0xD800 && v < 0xDC00 && i_ + 6 <= s_.size() && s_[i_] == '\\' && s_[i_ + 1] == 'u') {
                        i_ += 2;
                        unsigned lo;
                        if (!hex4(lo)) return false;
                        v = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00);
                    }
                    put_utf8(o, v);
                    break;
                }
                default: return false;
            }
        }
        return false;
    }
    bool value(Value& v) {
        if (i_ >= s_.size()) return false;
        char c = s_[i_];
        if (c == '{') {
            v.type = Value::Object;
            i_++;
            ws();
            if (i_ < s_.size() && s_[i_] == '}') { i_++; return true; }
            for (;;) {
                ws();
                std::string k;
                if (!string(k)) return false;
                ws();
                if (i_ >= s_.size() || s_[i_++] != ':') return false;
                ws();
                Value x;
                if (!value(x)) return false;
                v.obj.emplace_back(std::move(k), std::move(x));
                ws();
                if (i_ >= s_.size()) return false;
                if (s_[i_] == ',') { i_++; continue; }
                if (s_[i_] == '}') { i_++; return true; }
                return false;
            }
        }
        if (c == '[') {
            v.type = Value::Array;
            i_++;
            ws();
            if (i_ < s_.size() && s_[i_] == ']') { i_++; return true; }
            for (;;) {
                ws();
                Value x;
                if (!value(x)) return false;
                v.arr.push_back(std::move(x));
                ws();
                if (i_ >= s_.size()) return false;
                if (s_[i_] == ',') { i_++; continue; }
                if (s_[i_] == ']') { i_++; return true; }
                return false;
            }
        }
        if (c == '"') { v.type = Value::String; return string(v.str); }
        if (lit("true")) { v.type = Value::Bool; v.b = true; return true; }
        if (lit("false")) { v.type = Value::Bool; v.b = false; return true; }
        if (lit("null")) { v.type = Value::Null; return true; }
        size_t st = i_;
        while (i_ < s_.size() && (s_[i_] == '-' || s_[i_] == '+' || s_[i_] == '.' || s_[i_] == 'e' || s_[i_] == 'E' || (s_[i_] >= '0' && s_[i_] <= '9'))) i_++;
        if (st == i_) return false;
        v.type = Value::Number;
        v.num = std::strtod(s_.substr(st, i_ - st).c_str(), nullptr);
        return true;
    }
};

inline std::string quote(const std::string& s) {
    std::string o = "\"";
    for (unsigned char c : s) {
        if (c == '"') o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\r') o += "\\r";
        else if (c == '\t') o += "\\t";
        else if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; }
        else o.push_back(char(c));
    }
    return o + "\"";
}

}  // namespace json
}  // namespace shunti
