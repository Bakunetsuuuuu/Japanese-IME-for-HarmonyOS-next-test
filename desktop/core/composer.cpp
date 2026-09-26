#include "composer.h"

#include <algorithm>

namespace shunti {

namespace {
constexpr size_t CTX_MAX = 40;   // モデルの文脈の長さ

bool is_digit(char16_t c) { return c >= u'0' && c <= u'9'; }
bool is_upper(char16_t c) { return c >= u'A' && c <= u'Z'; }
bool is_lower(char16_t c) { return c >= u'a' && c <= u'z'; }

u16 tail(const u16& s, size_t n) { return s.size() > n ? s.substr(s.size() - n) : s; }

void push_unique(std::vector<u16>& v, const u16& s) {
    if (!s.empty() && std::find(v.begin(), v.end(), s) == v.end()) v.push_back(s);
}

u16 lower(u16 s) { for (auto& c : s) if (is_upper(c)) c = char16_t(c + 32); return s; }
u16 upper(u16 s) { for (auto& c : s) if (is_lower(c)) c = char16_t(c - 32); return s; }
u16 capital(u16 s) {
    s = lower(s);
    if (!s.empty() && is_lower(s[0])) s[0] = char16_t(s[0] - 32);
    return s;
}
}  // namespace

Composer::Composer(Converter* conv, Learning* learning, UserDict* dict) : conv_(conv), learning_(learning), dict_(dict) {}

// ---------------------------------------------------------------- キー

bool Composer::will_handle(const KeyEvent& ev) const {
    if (ev.ctrl || ev.alt) return false;
    if (state_ == State::Idle) return ev.key == Key::Char || ev.key == Key::Space;
    return true;
}

bool Composer::press(const KeyEvent& ev) {
    if (!will_handle(ev)) return false;
    bool handled = false;
    switch (state_) {
        case State::Idle:
            if (ev.key == Key::Space) {   // 何も打っていないときの空白: 全角 (Shift で半角)
                commit_text(ev.shift ? u" " : u"　");
                handled = true;
            } else if (ev.key == Key::Char) {
                start_input();
                type_char(ev.ch, ev.raw);
                handled = true;
            }
            break;
        case State::Input: handled = press_input(ev); break;
        case State::Convert: handled = press_convert(ev); break;
    }
    if (ev.key != Key::F9 && ev.key != Key::F10) last_f_ = Key::Char;
    rebuild_view();
    return handled;
}

void Composer::start_input() {
    u16 c = context_ ? context_() : u16();
    ctx_ = tail(c.empty() ? history_ : c, CTX_MAX);
    state_ = State::Input;
    kana_.clear();
    caret_ = 0;
    romaji_.reset();
    raw_.clear();
    raw_valid_ = true;
    alpha_run_ = false;
}

void Composer::insert(const u16& t) {
    kana_.insert(caret_, t);
    caret_ += t.size();
}

void Composer::flush_romaji() {
    if (!romaji_.pending().empty()) insert(romaji_.flush());
}

void Composer::type_char(char16_t c, bool raw) {
    if (raw_valid_ && caret_ == kana_.size()) raw_.push_back(c);
    else raw_valid_ = false;
    if (raw) {
        flush_romaji();
        insert(u16(1, c));
        return;
    }
    char16_t prev = caret_ > 0 ? kana_[caret_ - 1] : 0;
    if (is_upper(c)) {                                     // 大文字: ここから英字のまま
        flush_romaji();
        alpha_run_ = true;
        insert(u16(1, c));
        return;
    }
    if (alpha_run_ && c != u' ' && c < 0x7F) {            // 英字の続き (記号も打ったまま)
        flush_romaji();
        insert(u16(1, c));
        return;
    }
    if (romaji_.pending().empty() && is_digit(prev) && (c == u'-' || c == u',' || c == u'.' || c == u':' || c == u'/')) {
        insert(u16(1, c));                                  // 数の続きの記号 (03-1234・1,000・3.14・12:30・9/27)
        return;
    }
    if (is_lower(c) || romaji_.accepts(c) || c == u'-') {
        Romaji::Result r = romaji_.process(c);
        insert(r.committed);
        return;
    }
    flush_romaji();
    if (is_digit(c)) insert(u16(1, c));
    else insert(u16(1, japanese_symbol(c)));
}

bool Composer::press_input(const KeyEvent& ev) {
    switch (ev.key) {
        case Key::Char:
            type_char(ev.ch, ev.raw);
            return true;
        case Key::Space:
        case Key::Henkan:
            convert_all();
            return true;
        case Key::Enter:
            flush_romaji();
            commit_text(kana_);
            to_idle();
            return true;
        case Key::Escape:
            to_idle();
            return true;
        case Key::Backspace:
            if (!romaji_.pending().empty()) {
                romaji_.backspace();
                if (raw_valid_ && !raw_.empty()) raw_.pop_back();
            } else if (caret_ > 0) {
                kana_.erase(caret_ - 1, 1);
                caret_--;
                raw_valid_ = false;
            }
            if (kana_.empty() && romaji_.pending().empty()) to_idle();
            return true;
        case Key::Delete:
            flush_romaji();
            if (caret_ < kana_.size()) { kana_.erase(caret_, 1); raw_valid_ = false; }
            if (kana_.empty()) to_idle();
            return true;
        case Key::Left:
            flush_romaji();
            if (caret_ > 0) caret_--;
            return true;
        case Key::Right:
            flush_romaji();
            if (caret_ < kana_.size()) caret_++;
            return true;
        case Key::Home:
            flush_romaji();
            caret_ = 0;
            return true;
        case Key::End:
            flush_romaji();
            caret_ = kana_.size();
            return true;
        case Key::F6: case Key::F7: case Key::F8: case Key::F9: case Key::F10:
            flush_romaji();
            if (kana_.empty()) { to_idle(); return true; }
            segs_.clear();
            segs_.push_back({kana_, kana_});
            whole_.clear();
            focus_ = 0;
            cand_open_ = false;
            state_ = State::Convert;
            transform(ev.key);
            return true;
        case Key::Muhenkan:
            flush_romaji();
            if (kana_.empty()) { to_idle(); return true; }
            segs_.assign(1, Seg{kana_, kana_});
            whole_.clear();
            focus_ = 0;
            cand_open_ = false;
            state_ = State::Convert;
            transform(Key::F7);
            return true;
        default:   // ↑↓・Tab・PageUp/Down: 入力中は入力欄に渡さない
            return true;
    }
}

bool Composer::press_convert(const KeyEvent& ev) {
    Seg& s = segs_[focus_];
    auto set_sel = [&](int i) {
        if (s.cands.empty()) return;
        int n = int(s.cands.size());
        s.sel = ((i % n) + n) % n;
        s.surface = s.cands[size_t(s.sel)];
        s.changed = true;
    };
    auto open = [&]() {
        if (!s.loaded) load_cands(focus_);
        if (!cand_open_) { cand_open_ = true; before_open_ = s.surface; return true; }
        return false;
    };
    switch (ev.key) {
        case Key::Char: {
            if (cand_open_ && ev.ch >= u'1' && ev.ch <= u'9') {   // 候補の窓の番号で選ぶ
                int idx = (s.sel / PAGE) * PAGE + (ev.ch - u'1');
                if (idx < int(s.cands.size())) { set_sel(idx); cand_open_ = false; }
                return true;
            }
            commit_all();                // 変換中に次の字を打った: 確定してから打ち始める
            start_input();
            type_char(ev.ch, ev.raw);
            return true;
        }
        case Key::Space:
        case Key::Henkan:
        case Key::Down:
        case Key::Tab:
            open();
            set_sel(ev.shift && ev.key != Key::Down ? s.sel - 1 : s.sel + 1);
            return true;
        case Key::Up:
            open();
            set_sel(s.sel - 1);
            return true;
        case Key::PageDown:
            if (cand_open_) set_sel(std::min(int(s.cands.size()) - 1, (s.sel / PAGE + 1) * PAGE));
            return true;
        case Key::PageUp:
            if (cand_open_) set_sel(std::max(0, (s.sel / PAGE - 1) * PAGE));
            return true;
        case Key::Enter:
            commit_all();
            return true;
        case Key::Escape:
            if (cand_open_) {
                s.surface = before_open_;
                for (size_t i = 0; i < s.cands.size(); i++) if (s.cands[i] == s.surface) s.sel = int(i);
                cand_open_ = false;
            } else {
                back_to_input();
            }
            return true;
        case Key::Backspace:
            back_to_input();
            return true;
        case Key::Left:
        case Key::Right:
            if (ev.shift) { resize_focus(ev.key == Key::Left ? -1 : 1); return true; }
            cand_open_ = false;
            if (ev.key == Key::Left && focus_ > 0) focus_--;
            if (ev.key == Key::Right && focus_ + 1 < segs_.size()) focus_++;
            return true;
        case Key::Home:
            cand_open_ = false;
            focus_ = 0;
            return true;
        case Key::End:
            cand_open_ = false;
            focus_ = segs_.size() - 1;
            return true;
        case Key::F6: case Key::F7: case Key::F8: case Key::F9: case Key::F10:
            cand_open_ = false;
            transform(ev.key);
            return true;
        case Key::Muhenkan:
            cand_open_ = false;
            transform(Key::F7);
            return true;
        default:
            return true;
    }
}

void Composer::select_candidate(int index) {
    if (state_ != State::Convert || !cand_open_) return;
    Seg& s = segs_[focus_];
    if (index < 0 || index >= int(s.cands.size())) return;
    s.sel = index;
    s.surface = s.cands[size_t(index)];
    s.changed = true;
    cand_open_ = false;
    rebuild_view();
}

// ---------------------------------------------------------------- 変換

std::vector<Composer::Seg> Composer::convert_phrases(const u16& ctx, const u16& reading, std::vector<u16>* whole) {
    std::vector<Seg> out;
    Conversion c = conv_ ? conv_->convert(ctx, reading, 10) : Conversion();
    if (whole) *whole = c.cands;
    std::vector<Word> words = c.words;
    if (words.empty()) words.push_back({reading, c.cands.empty() ? reading : c.cands[0]});
    for (auto& p : group_phrases(words)) {
        Seg s{p.reading, p.surface};
        if (p.head_r < p.reading.size() && p.head_s < p.surface.size()) {
            s.tail_r = p.reading.substr(p.head_r);
            s.tail_s = p.surface.substr(p.head_s);
        }
        // 自分で選び直したことのある文節の読みは、そのとき選んだ表記にする
        if (learning_) {
            u16 t = learning_->top(p.reading);
            if (!t.empty()) s.surface = t;
        }
        out.push_back(std::move(s));
    }
    return out;
}

void Composer::convert_all() {
    flush_romaji();
    if (kana_.empty()) { to_idle(); return; }
    if (dict_) {
        dict_->refresh();
        if (dict_->version() != dict_version_ && conv_) {
            conv_->set_user_words(dict_->engine_forms());
            dict_version_ = dict_->version();
        }
    }
    segs_ = convert_phrases(ctx_, kana_, &whole_);
    if (segs_.size() != 1) whole_.clear();
    focus_ = 0;
    cand_open_ = false;
    state_ = State::Convert;
}

u16 Composer::left_context(size_t seg) const {
    u16 c = ctx_;
    for (size_t i = 0; i < seg && i < segs_.size(); i++) c += segs_[i].surface;
    return tail(c, CTX_MAX);
}

void Composer::load_cands(size_t i) {
    Seg& s = segs_[i];
    std::vector<u16> list;
    if (dict_) for (auto& w : dict_->lookup(s.reading)) push_unique(list, w);
    if (segs_.size() == 1 && !whole_.empty()) {
        for (auto& c : whole_) push_unique(list, c);
    } else if (conv_) {
        // 自立語だけを変換して付属語をつなぐ (がくせい|です → 学生です・楽聖です・学制です)。
        // 付属語が無い文節 (または分けられない文節) は文節ごと変換する
        u16 head = s.reading.substr(0, s.reading.size() - s.tail_r.size());
        for (auto& c : conv_->convert(left_context(i), head, 10).cands) push_unique(list, c + s.tail_s);
        if (!s.tail_r.empty()) push_unique(list, head + s.tail_s);
    }
    if (learning_) list = learning_->apply_order(s.reading, list);
    // いまの表記を先頭に (選ぶ前の並びがいちばん上から始まるように)
    auto it = std::find(list.begin(), list.end(), s.surface);
    if (it != list.end()) list.erase(it);
    list.insert(list.begin(), s.surface);
    push_unique(list, s.reading);
    push_unique(list, to_katakana(s.reading));
    s.cands = std::move(list);
    s.sel = 0;
    s.loaded = true;
}

void Composer::resize_focus(int delta) {
    cand_open_ = false;
    Seg& s = segs_[focus_];
    u16 rest;
    for (size_t i = focus_ + 1; i < segs_.size(); i++) rest += segs_[i].reading;
    int len = int(s.reading.size()) + delta;
    if (len < 1 || len > int(s.reading.size() + rest.size())) return;
    u16 all = s.reading + rest;
    u16 mine = all.substr(0, size_t(len));
    rest = all.substr(size_t(len));
    Conversion c = conv_ ? conv_->convert(left_context(focus_), mine, 10) : Conversion();
    Seg ns{mine, c.cands.empty() ? mine : c.cands[0]};
    std::vector<Phrase> ph = group_phrases(c.words);   // 伸び縮みした文節の付属語 (候補を作るときに使う)
    if (ph.size() == 1 && ph[0].reading == mine && ph[0].head_r < mine.size() && ph[0].head_s < ph[0].surface.size()) {
        ns.tail_r = mine.substr(ph[0].head_r);
        ns.tail_s = ph[0].surface.substr(ph[0].head_s);
    }
    ns.changed = true;
    segs_.resize(focus_);
    segs_.push_back(std::move(ns));
    if (!rest.empty()) {
        std::vector<Seg> after = convert_phrases(left_context(focus_ + 1), rest, nullptr);
        segs_.insert(segs_.end(), after.begin(), after.end());
    }
    whole_.clear();
}

u16 Composer::alpha_source(const u16& reading) const {
    if (segs_.size() == 1 && raw_valid_ && !raw_.empty()) return raw_;
    return romaji_.to_romaji(reading);
}

void Composer::transform(Key f) {
    Seg& s = segs_[focus_];
    u16 out;
    switch (f) {
        case Key::F6: out = to_hiragana(s.reading); break;
        case Key::F7: out = to_katakana(s.reading); s.changed = true; break;
        case Key::F8: out = to_halfwidth_kana(s.reading); break;
        case Key::F9:
        case Key::F10: {
            f_cycle_ = (last_f_ == f) ? (f_cycle_ + 1) % 3 : 0;
            u16 a = alpha_source(s.reading);
            a = to_halfwidth_ascii(a);
            a = f_cycle_ == 0 ? lower(a) : f_cycle_ == 1 ? upper(a) : capital(a);
            // かなの記号は英数字の記号に戻す (ー → -)
            for (auto& c : a) if (c == u'ー') c = u'-';
            out = f == Key::F9 ? to_fullwidth_ascii(a) : a;
            break;
        }
        default: return;
    }
    last_f_ = f;
    s.surface = out;
    s.cands.clear();
    s.loaded = false;
}

void Composer::back_to_input() {
    kana_.clear();
    for (auto& s : segs_) kana_ += s.reading;
    caret_ = kana_.size();
    segs_.clear();
    whole_.clear();
    cand_open_ = false;
    state_ = State::Input;
}

void Composer::commit_all() {
    u16 t;
    for (auto& s : segs_) {
        t += s.surface;
        if (s.changed && learning_) learning_->record(s.reading, s.surface);
    }
    commit_text(t);
    to_idle();
}

void Composer::commit_text(const u16& t) {
    commit_ += t;
    history_ = tail(history_ + t, CTX_MAX);
}

void Composer::to_idle() {
    state_ = State::Idle;
    kana_.clear();
    caret_ = 0;
    romaji_.reset();
    segs_.clear();
    whole_.clear();
    cand_open_ = false;
    alpha_run_ = false;
}

void Composer::finish() {
    if (state_ == State::Input) {
        flush_romaji();
        commit_text(kana_);
        to_idle();
    } else if (state_ == State::Convert) {
        commit_all();
    }
    rebuild_view();
}

void Composer::cancel() {
    to_idle();
    rebuild_view();
}

// ---------------------------------------------------------------- 見せ方

void Composer::rebuild_view() {
    View v;
    if (state_ == State::Input) {
        const u16& p = romaji_.pending();
        v.text = kana_.substr(0, caret_) + p + kana_.substr(caret_);
        v.caret = int(caret_ + p.size());
        if (!v.text.empty()) v.spans.push_back({0, int(v.text.size()), SpanKind::Input});
    } else if (state_ == State::Convert) {
        for (size_t i = 0; i < segs_.size(); i++) {
            int st = int(v.text.size());
            v.text += segs_[i].surface;
            int len = int(segs_[i].surface.size());
            if (len) v.spans.push_back({st, len, i == focus_ ? SpanKind::Focused : SpanKind::Converted});
            if (i == focus_) { v.anchor = st; v.caret = st + len; }
        }
        if (cand_open_) {
            v.cand_open = true;
            v.cands = segs_[focus_].cands;
            v.cand_sel = segs_[focus_].sel;
        }
    }
    view_ = std::move(v);
}

}  // namespace shunti
