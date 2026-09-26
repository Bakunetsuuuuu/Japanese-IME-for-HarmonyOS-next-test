// 変換エンジン (engine.cpp) の窓口。差別語の候補を弾き、長すぎる読みは分けて変換し、1 位の候補を文節に分ける。
#pragma once
#include <cstddef>
#include <vector>

#include "store.h"
#include "text.h"

struct kkc_engine;

namespace shunti {

// 1 位の候補の語 (読み・表記・品詞の左右 ID)
struct Word { u16 reading, surface; int lid = 0, rid = 0; bool pass = false; };
// 文節 (自立語 + 付属語)。head_r・head_s = 自立語 (と接頭) の読みと表記の長さ。残りが付属語
struct Phrase { u16 reading, surface; size_t head_r = 0, head_s = 0; };

struct Conversion {
    std::vector<u16> cands;      // 候補 (よい順)
    std::vector<Word> words;     // cands[0] の語の区切り (分からなければ空)
};

class Converter {
public:
    Converter() = default;
    ~Converter();
    Converter(const Converter&) = delete;
    Converter& operator=(const Converter&) = delete;

    // 辞書とモデル (呼び出し側がメモリに写したもの。閉じるまで持っておく)
    bool open(const void* lex, size_t lex_size, const void* model, size_t model_size, int threads);
    bool ok() const { return e_ != nullptr; }

    // ctx = 左の文脈 (確定済みの文)、kana = 読み
    Conversion convert(const u16& ctx, const u16& kana, int max);
    // 予測: 読みが prefix で始まる辞書の語
    std::vector<u16> complete(const u16& prefix, int max, int max_extra = 6);
    // ユーザー辞書の語を網に入れ直す (前の分は消す)
    int set_user_words(const std::vector<UserDict::Form>& forms, int bonus = 800);

private:
    // 返り値 false = 読みが長すぎる
    bool convert_once(const u16& ctx, const u16& kana, int max, Conversion& out);

    kkc_engine* e_ = nullptr;
};

// 語をつないで差別語になった候補か (HarmonyOS 版 AiConverter.SLURS と同じ)
bool is_slur(const u16& s);

// 1 位の候補の語を文節にまとめる (付属語は前の語に、接頭の後ろの語はその接頭に、続く英数字はひとまとまりに)
std::vector<Phrase> group_phrases(const std::vector<Word>& words);

}  // namespace shunti
