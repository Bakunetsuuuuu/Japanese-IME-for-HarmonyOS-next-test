// ローマ字 → かな (HarmonyOS 版 ime/JapaneseConverter.ets・Android 版 JapaneseConverter.kt の移植。決まりは向こうと同じ)。
// 表は HarmonyOS 版と同じもの (tables.h) に、PC のキーボードでよく打つ綴り (ca・qa・kwa・tsa・wha・n' など) と
// z で始まる記号 (zh → ← など) を足したもの。
#pragma once
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "text.h"

namespace shunti {

class Romaji {
public:
    Romaji();

    struct Result {
        u16 committed;   // かなに決まった分
        u16 pending;     // まだ決まらないローマ字
    };

    // 1 キー (小文字の a-z・-・' など) を足す
    Result process(char16_t key);
    // 溜めているローマ字 (まだかなに決まっていない分)
    const u16& pending() const { return buffer_; }
    // 溜めている分を出して空にする (n は ん、それ以外は打ったまま)
    u16 flush();
    void backspace() { if (!buffer_.empty()) buffer_.pop_back(); }
    void reset() { buffer_.clear(); }
    // key が溜めている分に続けてローマ字として意味を持つか (z の後の記号など)
    bool accepts(char16_t key) const;

    // かな → ローマ字 (F9・F10 で英字に戻すとき、打ったキーが分からない場合に使う)
    u16 to_romaji(const u16& kana) const;

private:
    Result process_buffered();

    std::unordered_map<u16, u16> table_;
    std::unordered_set<u16> prefixes_;
    std::unordered_map<u16, u16> reverse_;   // かな → いちばん短い綴り
    size_t max_kana_ = 1;
    u16 buffer_;
};

}  // namespace shunti
