#include "composer.h"

#include <algorithm>

#include "tables.h"

namespace shunti {

namespace {
constexpr size_t CTX_MAX = 40;   // モデルの文脈の長さ

bool is_digit(char16_t c) { return c >= u'0' && c <= u'9'; }
bool is_upper(char16_t c) { return c >= u'A' && c <= u'Z'; }
bool is_lower(char16_t c) { return c >= u'a' && c <= u'z'; }

u16 tail(const u16& s, size_t n) { return s.size() > n ? s.substr(s.size() - n) : s; }

bool contains(const std::vector<u16>& v, const u16& s) { return std::find(v.begin(), v.end(), s) != v.end(); }
void push_unique(std::vector<u16>& v, const u16& s) {
    if (!s.empty() && !contains(v, s)) v.push_back(s);
}

u16 lower(u16 s) { for (auto& c : s) if (is_upper(c)) c = char16_t(c + 32); return s; }
u16 upper(u16 s) { for (auto& c : s) if (is_lower(c)) c = char16_t(c - 32); return s; }
u16 capital(u16 s) {
    s = lower(s);
    if (!s.empty() && is_lower(s[0])) s[0] = char16_t(s[0] - 32);
    return s;
}

u16 replace_all(u16 s, const u16& from, const u16& to) {
    for (size_t i = s.find(from); i != u16::npos; i = s.find(from, i + to.size())) s.replace(i, from.size(), to);
    return s;
}

// 挨拶はかな書きを 1 位に (スマホ版 preferGreetings と同じ決まり)
void prefer_greetings(const u16& target, std::vector<u16>& cands) {
    if (cands.empty()) return;
    const u16& top = cands[0];
    u16 trimmed = target;
    while (!trimmed.empty() && u16(u"、。！？!?ー〜").find(trimmed.back()) != u16::npos) trimmed.pop_back();
    struct Rule { const char16_t* kanji; const char16_t* kana; bool ok; };
    const Rule rules[] = {
        {u"今日は", u"こんにちは", target.find(u"こんにちは") != u16::npos && target.find(u"きょうは") == u16::npos},
        {u"今晩は", u"こんばんは", trimmed == u"こんばんは"},
    };
    for (auto& r : rules) {
        if (!r.ok || top.find(r.kanji) == u16::npos) continue;
        u16 fixed = replace_all(top, r.kanji, r.kana);
        cands.erase(std::remove(cands.begin(), cands.end(), fixed), cands.end());
        cands.insert(cands.begin(), fixed);
        return;
    }
}
}  // namespace

u16 greeting_fix(const u16& reading, const u16& surf) {
    if (reading.find(u"こんにちは") != u16::npos && reading.find(u"きょうは") == u16::npos) return replace_all(surf, u"今日は", u"こんにちは");
    return surf;
}

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
                commit_text(ev.shift != options.space_fullwidth ? u"　" : u" ");
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
    if (ev.key != Key::F9 && ev.key != Key::F10 && ev.key != Key::Muhenkan) last_f_ = Key::Char;
    if (state_ == State::Input) update_live();
    if (state_ == State::Convert && options.always_cands && !segs_.empty()) {
        if (!segs_[focus_].loaded) load_cands(focus_);
        cand_open_ = true;
    }
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
    live_key_.clear();
    live_cands_.clear();
    prev_segs_.clear();
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
        // 打ち間違いを消して、ローマ字にならなかった英字 (子音) だけが残っているとき (「ps」→ s を消す → 「p」):
        // その英字を溜めている分に戻して、続けて打ったキーとつなぐ (p + a → ぱ)。つながる綴りになるときだけ
        if (romaji_.pending().empty() && is_lower(c)) {
            size_t n = 0;
            while (n < 3 && caret_ > n && is_lower(kana_[caret_ - 1 - n])) n++;
            for (; n > 0; n--) {
                u16 back = kana_.substr(caret_ - n, n);
                bool sokuon = n == 1 && back[0] == c && c != u'n' && u16(u"aiueo").find(c) == u16::npos;   // t + t → っt
                if (!romaji_.is_prefix(back + c) && !sokuon) continue;
                kana_.erase(caret_ - n, n);
                caret_ -= n;
                romaji_.unread(back);
                break;
            }
        }
        Romaji::Result r = romaji_.process(c);
        insert(r.committed);
        return;
    }
    flush_romaji();
    if ((c == 0x309B || c == 0x309C) && caret_ > 0) {   // かな入力の濁点・半濁点: 前のかなにつける (か + ゛ → が)
        char16_t p = kana_[caret_ - 1];
        const char16_t* voiced = u"かきくけこさしすせそたちつてとはひふへほ";
        const char16_t* semi = u"はひふへほ";
        if (c == 0x309B && u16(voiced).find(p) != u16::npos) { kana_[caret_ - 1] = char16_t(p + 1); return; }
        if (c == 0x309B && p == u'う') { kana_[caret_ - 1] = u'ゔ'; return; }
        if (c == 0x309C && u16(semi).find(p) != u16::npos) { kana_[caret_ - 1] = char16_t(p + 2); return; }
    }
    if (is_digit(c)) insert(u16(1, options.digits_fullwidth ? char16_t(c + 0xFEE0) : c));
    else if (c == u',') insert(options.punct == 1 || options.punct == 3 ? u"，" : u"、");
    else if (c == u'.') insert(options.punct == 1 || options.punct == 2 ? u"．" : u"。");
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
        case Key::Down:
        case Key::Tab:   // 打っている間の候補を選び始める
            flush_romaji();
            update_live();
            if (!live_cands_.empty()) {
                enter_single(live_cands_[0], live_cands_, 0);
                first_cands_ = live_cands_;
                first_via_ = "live";
            }
            return true;
        case Key::Enter:
            flush_romaji();
            log({"raw", kana_, kana_, ctx_});
            commit_text(kana_);
            to_idle();
            return true;
        case Key::Escape:
            log({"clear", kana_ + romaji_.pending(), u16(), ctx_});
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
        case Key::F6: case Key::F7: case Key::F8: case Key::F9: case Key::F10: case Key::Muhenkan:
            flush_romaji();
            if (kana_.empty()) { to_idle(); return true; }
            enter_single(kana_, {}, 0);
            first_via_ = "fkey";
            transform(ev.key);
            return true;
        default:   // ↑・PageUp/Down: 入力中は入力欄に渡さない
            return true;
    }
}

bool Composer::press_convert(const KeyEvent& ev) {
    Seg& s = segs_[focus_];
    auto set_sel = [&](int i) {
        if (!s.loaded) load_cands(focus_);
        if (s.cands.empty()) return;
        int n = int(s.cands.size());
        s.sel = ((i % n) + n) % n;
        s.surface = s.cands[size_t(s.sel)];
        s.changed = true;
        cand_open_ = true;
    };
    switch (ev.key) {
        case Key::Char: {
            if (cand_open_ && ev.ch >= u'1' && ev.ch <= u'9') {   // 候補の窓の番号で選ぶ
                int idx = (s.sel / PAGE) * PAGE + (ev.ch - u'1');
                if (idx < int(s.cands.size())) {
                    set_sel(idx);
                    if (!options.always_cands) cand_open_ = false;
                }
                return true;
            }
            // 変換中に次の字を打った: 確定してから打ち始める (文脈は確定した文まで)
            u16 carry = ctx_;
            for (auto& x : segs_) carry += x.surface;
            commit_all();
            start_input();
            ctx_ = tail(carry, CTX_MAX);
            type_char(ev.ch, ev.raw);
            return true;
        }
        case Key::Space:
        case Key::Henkan:
        case Key::Down:
        case Key::Tab:
            set_sel(ev.shift && ev.key != Key::Down ? s.sel - 1 : s.sel + 1);
            return true;
        case Key::Up:
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
            if (cand_open_ && !options.always_cands) cand_open_ = false;
            else back_to_input();
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
        case Key::F6: case Key::F7: case Key::F8: case Key::F9: case Key::F10: case Key::Muhenkan:
            transform(ev.key);
            return true;
        default:
            return true;
    }
}

void Composer::select_candidate(int index) {
    if (state_ == State::Input) {   // 打っている間の候補: それを確定する
        if (index < 0 || index >= int(live_cands_.size())) return;
        u16 c = live_cands_[size_t(index)];
        flush_romaji();
        {
            LogEvent e{"commit", kana_, c, ctx_, live_cands_, index};
            e.segs = {c};
            e.extra = "live,mouse";
            log(e);
        }
        if (learning_) learning_->record(kana_, c);
        commit_text(c);
        to_idle();
        rebuild_view();
        return;
    }
    if (state_ != State::Convert) return;
    Seg& s = segs_[focus_];
    if (index < 0 || index >= int(s.cands.size())) return;
    s.sel = index;
    s.surface = s.cands[size_t(index)];
    s.changed = true;
    log({"bseg", s.reading, s.surface, left_context(focus_), s.cands, index, {}, "mouse"});
    if (!options.always_cands) cand_open_ = false;
    rebuild_view();
}

// ---------------------------------------------------------------- 打っている間の変換

void Composer::update_live() {
    if (!options.live || state_ != State::Input || !conv_ || kana_.empty()) {
        live_cands_.clear();
        live_key_.clear();
        return;
    }
    u16 key = ctx_ + u'\x01' + kana_;
    if (key == live_key_) return;
    sync_user_dict();
    Conversion c = conv_->convert(ctx_, kana_, 10);
    if (options.live_commit && caret_ == kana_.size() && !alpha_run_ && live_commit(c)) {
        update_live();   // 前の方を確定した: 残りを変換し直す
        return;
    }
    live_key_ = key;
    std::vector<u16> cands = c.cands;
    if (learning_) cands = learning_->apply_order(kana_, cands);
    prefer_greetings(kana_, cands);
    // 予測 (スマホ版と同じ置き方): 決まり文句は先頭に、読みの続く語 (学習した語・辞書の語) は 1 位の直後に 3 つまで
    const Phrase2* phrase = nullptr;
    for (auto& p : PREDICTIVE_PHRASES) {
        u16 r = p.reading;
        if (kana_.size() >= size_t(p.min_prefix) && kana_.size() < r.size() && r.compare(0, kana_.size(), kana_) == 0) { phrase = &p; break; }
    }
    if (kana_.size() >= 2) {
        std::vector<u16> comp;
        if (learning_) for (auto& x : learning_->completions(kana_, 2)) push_unique(comp, x);
        for (auto& x : conv_->complete(kana_, 4)) push_unique(comp, x);
        size_t at = std::min<size_t>(1, cands.size());
        int inserted = 0;
        for (auto& x : comp) {
            if (inserted >= 3) break;
            if (contains(cands, x) || (phrase && x == phrase->text)) continue;
            cands.insert(cands.begin() + long(at++), x);
            inserted++;
        }
    }
    if (phrase) {
        u16 t = phrase->text;
        cands.erase(std::remove(cands.begin(), cands.end(), t), cands.end());
        cands.insert(cands.begin(), t);
    }
    if (dict_) {   // ユーザー辞書に登録した語は先頭に
        std::vector<u16> user = dict_->lookup(kana_);
        for (auto it = user.rbegin(); it != user.rend(); ++it) {
            cands.erase(std::remove(cands.begin(), cands.end(), *it), cands.end());
            cands.insert(cands.begin(), *it);
        }
    }
    if (cands.empty()) cands.push_back(kana_);
    live_cands_ = std::move(cands);
}

// リアルタイム確定 (スマホ版 AiConverter.maybeFreeze と同じ決まり)。確定したら true
bool Composer::live_commit(const Conversion& c) {
    if (c.cands.empty() || c.words.size() < 2) {
        prev_segs_.clear();
        return false;
    }
    const u16& top = c.cands[0];
    size_t cum_r = 0, cum_s = 0, freeze_end = 0, freeze_len = 0;
    std::map<size_t, u16> segs;
    for (size_t i = 0; i + 1 < c.words.size(); i++) {   // 最後の語は確定しない
        cum_r += c.words[i].reading.size();
        cum_s += c.words[i].surface.size();
        u16 surf = top.substr(0, std::min(cum_s, top.size()));
        segs[cum_r] = surf;
        bool punct = u16(u"、。！？!?").find(kana_[cum_r - 1]) != u16::npos;
        auto it = prev_segs_.find(cum_r);
        bool stable = it != prev_segs_.end() && it->second == surf;
        if (cum_r + KEEP <= kana_.size() && (stable || punct)) {
            freeze_end = cum_r;
            freeze_len = cum_s;
        }
    }
    prev_segs_ = std::move(segs);
    if (!freeze_end) return false;
    // 確定する前の方にも挨拶のかな書きを当てる (候補の並べ替えだけでは、ここで「今日は」が確定されてしまう)
    u16 fs = greeting_fix(kana_.substr(0, freeze_end), top.substr(0, std::min(freeze_len, top.size())));
    {
        std::vector<u16> cs(c.cands.begin(), c.cands.begin() + long(std::min<size_t>(c.cands.size(), 5)));
        LogEvent e{"auto", kana_.substr(0, freeze_end), fs, ctx_, cs, -1};
        e.extra = to_utf8(kana_.substr(freeze_end));   // まだ確定していない残りの読み
        log(e);
    }
    commit_text(fs);
    ctx_ = tail(ctx_ + fs, CTX_MAX);
    kana_.erase(0, freeze_end);
    caret_ -= std::min(caret_, freeze_end);
    raw_valid_ = false;
    prev_segs_.clear();
    live_key_.clear();
    return true;
}

// ---------------------------------------------------------------- 変換

void Composer::sync_user_dict() {
    if (!dict_ || !conv_) return;
    dict_->refresh();
    if (dict_->version() != dict_version_) {
        conv_->set_user_words(dict_->engine_forms());
        dict_version_ = dict_->version();
        live_key_.clear();
    }
}

std::vector<Composer::Seg> Composer::convert_phrases(const u16& ctx, const u16& reading, std::vector<u16>* whole) {
    std::vector<Seg> out;
    Conversion c = conv_ ? conv_->convert(ctx, reading, 10) : Conversion();
    if (whole) {
        *whole = c.cands;
        prefer_greetings(reading, *whole);
    }
    std::vector<Word> words = c.words;
    if (words.empty()) words.push_back({reading, c.cands.empty() ? reading : c.cands[0]});
    for (auto& p : group_phrases(words)) {
        Seg s{p.reading, greeting_fix(p.reading, p.surface)};
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
    sync_user_dict();
    segs_ = convert_phrases(ctx_, kana_, &whole_);
    first_cands_ = whole_;
    first_via_ = "space";
    if (segs_.size() != 1) whole_.clear();
    focus_ = 0;
    cand_open_ = false;
    state_ = State::Convert;
}

void Composer::enter_single(const u16& surface, std::vector<u16> cands, int sel) {
    Seg s{kana_, surface};
    if (!cands.empty()) {
        push_unique(cands, kana_);
        push_unique(cands, to_katakana(kana_));
        s.cands = std::move(cands);
        s.loaded = true;
        s.sel = sel;
        cand_open_ = true;
    } else {
        cand_open_ = false;
    }
    segs_.assign(1, std::move(s));
    whole_.clear();
    focus_ = 0;
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
        case Key::Muhenkan:   // 押すたびに カタカナ → 半角カタカナ → ひらがな
            f_cycle_ = (last_f_ == f) ? (f_cycle_ + 1) % 3 : 0;
            out = f_cycle_ == 0 ? to_katakana(s.reading) : f_cycle_ == 1 ? to_halfwidth_kana(s.reading) : to_hiragana(s.reading);
            if (f_cycle_ == 0) s.changed = true;
            break;
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
    {
        u16 shown, reading;
        for (auto& s : segs_) { shown += s.surface; reading += s.reading; }
        log({"cancel", reading, shown, ctx_, first_cands_});
    }
    kana_.clear();
    for (auto& s : segs_) kana_ += s.reading;
    caret_ = kana_.size();
    segs_.clear();
    whole_.clear();
    cand_open_ = false;
    state_ = State::Input;
    live_key_.clear();
    prev_segs_.clear();
}

void Composer::commit_all() {
    u16 t, reading;
    std::vector<u16> segs;
    int changed = 0;
    for (auto& s : segs_) {
        t += s.surface;
        reading += s.reading;
        segs.push_back(s.surface);
        if (s.changed) {
            changed++;
            if (learning_) learning_->record(s.reading, s.surface);
            log({"bseg", s.reading, s.surface, u16(), s.cands, s.sel});
        }
    }
    if (on_log) {
        int idx = -1;
        for (size_t i = 0; i < first_cands_.size(); i++) if (first_cands_[i] == t) idx = int(i);
        LogEvent e{"commit", reading, t, ctx_, first_cands_, idx, segs};
        e.extra = first_via_ + ",changed=" + std::to_string(changed);
        log(e);
    }
    commit_text(t);
    to_idle();
}

void Composer::log(LogEvent e) {
    if (on_log) on_log(e);
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
    first_cands_.clear();
    first_via_.clear();
    cand_open_ = false;
    alpha_run_ = false;
    live_key_.clear();
    live_cands_.clear();
    prev_segs_.clear();
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
        if (!live_cands_.empty()) {
            v.cand_open = true;
            v.cands = live_cands_;
            v.cand_sel = -1;
        }
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
