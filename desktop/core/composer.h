// PC 版の入力の状態と操作 (Windows の TSF・Linux の Fcitx5 から同じものを使う)。
//
// ハードウェアキーボードで打つ PC の IME の決まり (MS-IME・Google 日本語入力と同じ操作):
//   ローマ字で打つ → 空白 (変換キー) で AI 変換 → 文節ごとに直す (←→ で文節を選び、Shift+←→ で伸び縮み、
//   空白・↓ で候補の窓を出して選ぶ) → Enter で確定。F6〜F10 でひらがな・カタカナ・半角カナ・全角英数・半角英数。
// 変換は文全体を一度にモデルに通し (左の文脈 = 入力欄のカーソルの左)、その 1 位を品詞で文節に分ける。
// 文節の候補は、その文節の読みを、左の文節までを文脈にして変換したもの。
// 学習は、変換のあとで自分で選び直した文節だけを覚える (手を入れなかった文節は、文脈で決まる AI の結果に任せる)。
#pragma once
#include <functional>
#include <string>
#include <vector>

#include "converter.h"
#include "romaji.h"
#include "store.h"
#include "text.h"

namespace shunti {

enum class Key {
    Char, Space, Enter, Backspace, Delete, Escape, Left, Right, Up, Down, Home, End, Tab, PageUp, PageDown,
    F6, F7, F8, F9, F10, Henkan, Muhenkan,
};

struct KeyEvent {
    Key key = Key::Char;
    char16_t ch = 0;     // Key::Char のときの字 (キーボードの配列に従って打たれた字)
    bool shift = false, ctrl = false, alt = false;
    bool raw = false;    // かなにせず打ったまま入れる (テンキー)
};

enum class SpanKind { Input, Converted, Focused };
struct Span { int start, len; SpanKind kind; };

// 入力中の文字の見せ方と候補の窓
struct View {
    u16 text;
    std::vector<Span> spans;
    int caret = 0;
    int anchor = 0;               // 候補の窓をこの字の下に出す
    bool cand_open = false;
    std::vector<u16> cands;
    int cand_sel = 0;
};

class Composer {
public:
    static constexpr int PAGE = 9;   // 候補の窓の 1 ページの数 (1〜9 で選ぶ)

    Composer(Converter* conv, Learning* learning, UserDict* dict);

    // 入力欄のカーソルの左の文 (変換の文脈)。読めない入力欄では空を返してよい (そのときはこれまでに確定した文を使う)
    void set_context_provider(std::function<u16()> f) { context_ = std::move(f); }
    // 入力欄が変わったとき: これまでに確定した文 (文脈の代わり) を忘れる
    void reset_history() { history_.clear(); }

    // このキーをこちらで扱うか (状態は変えない。TSF の OnTestKeyDown 用)
    bool will_handle(const KeyEvent& ev) const;
    // キーを扱う。扱ったら true。確定する文は take_commit で、入力中の見せ方は view で受け取る
    bool press(const KeyEvent& ev);
    u16 take_commit() { u16 c; c.swap(commit_); return c; }
    const View& view() const { return view_; }
    bool composing() const { return state_ != State::Idle; }

    // 候補の窓の index 番目をマウスで選んだ
    void select_candidate(int index);
    // 入力中のものをいま見えているまま確定する (入力欄を離れたときなど)。確定した文は take_commit で
    void finish();
    // 入力中のものを捨てる
    void cancel();

private:
    enum class State { Idle, Input, Convert };
    struct Seg {
        u16 reading, surface;
        u16 tail_r, tail_s;      // 付属語の読みと表記 (候補は自立語だけを変換して、これをつなぐ)
        std::vector<u16> cands;
        bool loaded = false;
        int sel = 0;
        bool changed = false;    // 変換のあとで選び直した (確定したときに学習する)
    };

    void start_input();
    void insert(const u16& t);
    void flush_romaji();
    void type_char(char16_t c, bool raw = false);
    bool press_input(const KeyEvent& ev);
    bool press_convert(const KeyEvent& ev);
    void convert_all();
    std::vector<Seg> convert_phrases(const u16& ctx, const u16& reading, std::vector<u16>* whole);
    u16 left_context(size_t seg) const;
    void load_cands(size_t i);
    void resize_focus(int delta);
    void transform(Key f);
    u16 alpha_source(const u16& reading) const;
    void back_to_input();
    void commit_all();
    void commit_text(const u16& t);
    void to_idle();
    void rebuild_view();

    Converter* conv_;
    Learning* learning_;
    UserDict* dict_;
    std::function<u16()> context_;

    State state_ = State::Idle;
    u16 ctx_;          // 入力を始めたときの左の文脈
    u16 history_;      // これまでに確定した文 (入力欄の文が読めないときの文脈)
    u16 commit_;
    View view_;

    // 入力 (かな)
    u16 kana_;
    size_t caret_ = 0;
    Romaji romaji_;
    u16 raw_;               // 打ったキーそのまま (英字に戻すとき用。途中を直したら使えない)
    bool raw_valid_ = true;
    bool alpha_run_ = false;   // 大文字で始めた英字の続き (かなにしない)

    // 変換
    std::vector<Seg> segs_;
    std::vector<u16> whole_;   // 文全体の候補 (文節が 1 つのとき、その候補に使う)
    size_t focus_ = 0;
    bool cand_open_ = false;
    u16 before_open_;          // 候補の窓を開く前の表記 (Esc で戻す)
    uint32_t dict_version_ = 0;   // 変換の網に入れたユーザー辞書の版
    Key last_f_ = Key::Char;   // 続けて押した F9・F10 (小文字 → 大文字 → 先頭だけ大文字と回す)
    int f_cycle_ = 0;
};

}  // namespace shunti
