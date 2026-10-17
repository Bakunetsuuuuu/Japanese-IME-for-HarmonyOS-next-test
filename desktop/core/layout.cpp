#include "layout.h"

#include <algorithm>

#include "text.h"

namespace shunti {

// 10 進の整数 (atoi は使わない: glibc 2.38 の __isoc23_strtol を要求して、Linux 版の動く範囲が狭まる)
static int to_int(const char* p) {
    int sign = 1, v = 0;
    while (*p == ' ') p++;
    if (*p == '-') { sign = -1; p++; }
    while (*p >= '0' && *p <= '9') v = v * 10 + (*p++ - '0');
    return sign * v;
}


namespace {

const char* SHIFTS[] = {"space", "lthumb", "rthumb"};

bool is_shift_key(const std::string& k) {
    for (const char* s : SHIFTS)
        if (k == s) return true;
    return false;
}

std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> out;
    size_t i = 0;
    while (true) {
        size_t j = s.find(sep, i);
        out.push_back(s.substr(i, j == std::string::npos ? std::string::npos : j - i));
        if (j == std::string::npos) break;
        i = j + 1;
    }
    return out;
}

// キーを名前順に並べて + でつなぐ (同時押しは順番を問わない)
std::string chord_key(std::vector<std::string> keys) {
    std::sort(keys.begin(), keys.end());
    std::string k;
    for (auto& x : keys) k += (k.empty() ? "" : "+") + x;
    return k;
}

}  // namespace

bool Layout::load(const std::string& tsv, std::string* err) {
    *this = Layout();
    size_t i = 0;
    int line_no = 0;
    while (i < tsv.size()) {
        size_t j = tsv.find('\n', i);
        if (j == std::string::npos) j = tsv.size();
        std::string line = tsv.substr(i, j - i);
        i = j + 1;
        line_no++;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line_no == 1 && line.size() >= 3 && line.compare(0, 3, "\xEF\xBB\xBF") == 0) line.erase(0, 3);
        if (line.empty()) continue;
        if (line.compare(0, 2, "#!") == 0) {   // 見出し: #! name 大西配列
            std::string rest = line.substr(2);
            while (!rest.empty() && rest[0] == ' ') rest.erase(0, 1);
            size_t sp = rest.find(' ');
            std::string k = rest.substr(0, sp), v = sp == std::string::npos ? "" : rest.substr(sp + 1);
            if (k == "name") name_ = v;
            else if (k == "author") author_ = v;
            else if (k == "url") url_ = v;
            else if (k == "kind") kind_ = v == "kana" ? Kind::Kana : v == "chord" ? Kind::Chord : Kind::Letters;
            else if (k == "window") window_ms = uint64_t(std::max(20, std::min(400, to_int(v.c_str()))));
            continue;
        }
        if (line[0] == '#') continue;
        size_t tab = line.find('\t');
        if (tab == std::string::npos || tab == 0) {
            if (err) *err = "行 " + std::to_string(line_no) + ": キーと字の間にタブがありません";
            return false;
        }
        std::string keys = line.substr(0, tab);
        u16 out = from_utf8(line.substr(tab + 1));
        if (keys.size() > 3 && keys[0] == 'p' && keys.find('>') != std::string::npos) {   // 前置シフトの面
            prefixed_[keys] = out;
            continue;
        }
        if (keys.size() > 2 && keys.compare(0, 2, "S-") == 0) {
            shifted_[keys.substr(2)] = out;
            continue;
        }
        if (keys.find('+') == std::string::npos || keys == "+") {
            single_[keys] = out;
            continue;
        }
        std::vector<std::string> ks = split(keys, '+');
        for (auto& k : ks) {
            if (is_shift_key(k)) shift_keys_.insert(k);
            else chord_keys_.insert(k);
        }
        chords_[chord_key(ks)] = out;
    }
    if (!loaded() && err) *err = "キーの行がありません";
    return loaded();
}

std::string Layout::map_key(const std::string& k) const {
    if (thumbs == 0 || !(shift_keys_.count("lthumb") || shift_keys_.count("rthumb"))) return k;   // 親指の配列でなければそのまま
    if (thumbs == 1) {   // 無変換・空白: 空白が右親指、変換キーはふつうに
        if (k == "space") return "rthumb";
        if (k == "rthumb") return std::string();
    } else if (thumbs == 2) {   // 空白・変換: 空白が左親指、無変換キーはふつうに
        if (k == "space") return "lthumb";
        if (k == "lthumb") return std::string();
    }
    return k;
}

bool Layout::handles(const std::string& key) const {
    if (single_.count(key) || shifted_.count(key) || chord_keys_.count(key) || shift_keys_.count(key)) return true;
    for (auto& kv : prefixed_) {   // 前置シフトの面にしか無いキー (p1>e の e)
        const size_t gt = kv.first.find('>');
        if (gt != std::string::npos && kv.first.compare(gt + 1, std::string::npos, key) == 0) return true;
    }
    return false;
}

void Layout::reset() {
    evs_.clear();
    shifts_.clear();
    prefix_.clear();
    pending_.clear();
    held_.clear();
    shift_used_ = false;
}

std::vector<Layout::Out> Layout::emit(const u16& s) {
    std::vector<Out> out;
    if (s.size() == 4 && s[0] == u'{' && s[1] == u'p' && s[3] == u'}') {   // 前置シフトのキー: 次のキーをその面で読む
        prefix_ = std::string("p") + char(s[2]);
        return out;
    }
    // {bs} などは打鍵に、それ以外は字に (つながった字は 1 つにまとめる)
    size_t i = 0;
    u16 text;
    while (i < s.size()) {
        if (s[i] == u'{') {
            size_t e = s.find(u'}', i);
            if (e != u16::npos) {
                if (!text.empty()) { out.push_back({text, ""}); text.clear(); }
                std::string k;
                for (size_t x = i + 1; x < e; x++) k.push_back(char(s[x]));
                out.push_back({u16(), k});
                i = e + 1;
                continue;
            }
        }
        text.push_back(s[i++]);
    }
    if (!text.empty()) out.push_back({text, ""});
    return out;
}

Layout::Out Layout::lookup1(const std::string& key, bool shift) const {
    if (shift) {
        auto it = shifted_.find(key);
        if (it != shifted_.end()) return {it->second, ""};
        if (kind_ == Kind::Letters) {   // 英字の配列で Shift の行が無い英字: 大文字
            auto s1 = single_.find(key);
            if (s1 != single_.end() && s1->second.size() == 1 && s1->second[0] >= u'a' && s1->second[0] <= u'z')
                return {u16(1, char16_t(s1->second[0] - 32)), ""};
        }
    }
    auto it = single_.find(key);
    if (it != single_.end()) return {it->second, ""};
    return {};
}

std::string Layout::shift_held() const {
    for (const char* s : SHIFTS)
        if (held_.count(s) && shift_keys_.count(s)) return s;
    return std::string();
}

std::vector<Layout::Out> Layout::flush_pending() {
    std::vector<Out> out;
    if (pending_.empty()) return out;
    std::vector<std::string> ks;
    for (auto& p : pending_) ks.push_back(p.key);
    const std::string sh = shift_held();
    if (!sh.empty()) {   // シフトを押している間: シフト+キー (無ければ単打)
        for (auto& p : pending_) {
            auto it = chords_.find(chord_key({sh, p.key}));
            if (it != chords_.end()) {
                auto e = emit(it->second);
                out.insert(out.end(), e.begin(), e.end());
                shift_used_ = true;
            } else {
                auto e = emit(lookup1(p.key, p.shift).text);
                out.insert(out.end(), e.begin(), e.end());
            }
        }
        pending_.clear();
        return out;
    }
    // 同時押しの組 (いちばん長い組から。3 キー → 2 キー → 単打)
    size_t i = 0;
    while (i < pending_.size()) {
        bool done = false;
        for (size_t len = std::min<size_t>(3, pending_.size() - i); len >= 2; len--) {
            std::vector<std::string> sub;
            for (size_t x = i; x < i + len; x++) sub.push_back(pending_[x].key);
            auto it = chords_.find(chord_key(sub));
            if (it != chords_.end()) {
                auto e = emit(it->second);
                out.insert(out.end(), e.begin(), e.end());
                i += len;
                done = true;
                break;
            }
        }
        if (!done) {
            auto e = emit(lookup1(pending_[i].key, pending_[i].shift).text);
            out.insert(out.end(), e.begin(), e.end());
            i++;
        }
    }
    pending_.clear();
    return out;
}

std::vector<Layout::Out> Layout::down(const std::string& key, bool shift, uint64_t t) {
    std::vector<Out> out;
    if (held_.count(key)) {   // 押しっぱなしの繰り返し: 単打の繰り返し (同時押しの配列でも、組にしない)
        if (!repeat) return out;
        if (!is_shift_key(key) && kind_ != Kind::Chord) return emit(lookup1(key, shift).text);
        if (!is_shift_key(key) && kind_ == Kind::Chord) {
            for (auto& e : evs_) if (e.key == key && !e.decided) return out;   // まだ決まっていない: 繰り返さない
            return emit(lookup1(key, shift).text);
        }
        if (!is_shift_key(key) && pending_.empty()) return emit(lookup1(key, shift).text);
        return out;
    }
    if (!prefix_.empty() && !is_shift_key(key)) {   // 前置シフトの次のキー
        auto it = prefixed_.find(prefix_ + ">" + key);
        prefix_.clear();
        held_.insert(key);
        if (it != prefixed_.end()) return emit(it->second);
        held_.erase(key);   // その面に無いキー: ふつうに
    }
    if (kind_ == Kind::Chord) return chord_down(key, shift, t);
    // 時間切れの待ちを先に出す (このキーを押す前に決まっていた分)
    if (!pending_.empty() && t - pending_.front().t >= window_ms) out = flush_pending();
    held_.insert(key);
    if (is_shift_key(key) && shift_keys_.count(key)) {   // シフトを押した: 押しっぱなしで効く
        shift_used_ = false;
        // 先に押していて待っているキー (時間内) はシフトと組む (NICOLA: 文字キーと親指は順番を問わない)
        auto e = flush_pending();
        out.insert(out.end(), e.begin(), e.end());
        return out;
    }
    const bool chordable = chord_keys_.count(key) > 0 || !shift_held().empty();
    if (kind_ != Kind::Chord || !chordable) {
        auto p = flush_pending();
        out.insert(out.end(), p.begin(), p.end());
        const std::string sh = shift_held();
        if (!sh.empty()) {
            auto it = chords_.find(chord_key({sh, key}));
            if (it != chords_.end()) {
                shift_used_ = true;
                auto e = emit(it->second);
                out.insert(out.end(), e.begin(), e.end());
                return out;
            }
        }
        auto e = emit(lookup1(key, shift).text);
        out.insert(out.end(), e.begin(), e.end());
        return out;
    }
    if (!shift_held().empty()) {   // シフトを押している間は待たずに決まる
        pending_.push_back({key, shift, t});
        auto e = flush_pending();
        out.insert(out.end(), e.begin(), e.end());
        return out;
    }
    pending_.push_back({key, shift, t});
    if (pending_.size() >= 3) {   // 3 キーまで。そこで決める
        auto e = flush_pending();
        out.insert(out.end(), e.begin(), e.end());
    }
    return out;
}

std::vector<Layout::Out> Layout::up(const std::string& key, uint64_t t) {
    std::vector<Out> out;
    if (!held_.count(key)) return out;
    if (kind_ == Kind::Chord) return chord_up(key, t);
    if (is_shift_key(key) && shift_keys_.count(key)) {
        auto e = flush_pending();   // シフトを離す前に押していたキーはシフトと組む
        held_.erase(key);
        out.insert(out.end(), e.begin(), e.end());
        if (!shift_used_) {   // シフトを単独で押して離した: そのキーの単打 (空白など)
            auto it = single_.find(key);
            if (it != single_.end()) {
                auto s = emit(it->second);
                out.insert(out.end(), s.begin(), s.end());
            } else if (key == "space") {
                out.push_back({u16(), "space"});
            } else if (key == "lthumb" || key == "rthumb") {   // 親指キーを単独で: 無変換・変換キーとして
                out.push_back({u16(), key == "lthumb" ? "muhenkan" : "henkan"});
            }
        }
        shift_used_ = false;
        return out;
    }
    // 待っているキーを離した: そこまでで決める
    bool was_pending = false;
    for (auto& p : pending_) was_pending = was_pending || p.key == key;
    held_.erase(key);
    if (was_pending) out = flush_pending();
    return out;
}

std::vector<Layout::Out> Layout::tick(uint64_t now) {
    if (kind_ == Kind::Chord) return resolve(now);
    if (!pending_.empty() && now - pending_.front().t >= window_ms && shift_held().empty()) return flush_pending();
    return {};
}

// ---------------------------------------------------------------- 同時押しの配列: 押していた時間の重なりで決める

std::vector<Layout::Out> Layout::chord_down(const std::string& key, bool shift, uint64_t t) {
    held_.insert(key);
    Ev e;
    e.key = key;
    e.shift = shift;
    e.is_shift = is_shift_key(key) && shift_keys_.count(key) > 0;
    e.down = t;
    if (e.is_shift) {
        e.shift_id = next_shift_id_++;
        ShiftRec r;
        r.id = e.shift_id;
        r.key = key;
        r.down = t;
        shifts_.push_back(r);
    }
    evs_.push_back(std::move(e));
    return resolve(t);
}

std::vector<Layout::Out> Layout::chord_up(const std::string& key, uint64_t t) {
    held_.erase(key);
    for (auto& e : evs_)
        if (e.key == key && !e.released) { e.released = true; e.up = t; break; }
    for (auto& r : shifts_)
        if (r.key == key && !r.released) { r.released = true; r.up = t; }
    return resolve(t);
}

std::vector<Layout::Out> Layout::resolve(uint64_t now) {
    auto end_of = [&](const Ev& e) { return e.released ? e.up : now; };
    auto dur = [&](const Ev& e) { return double(end_of(e) - e.down); };
    auto overlap = [&](const Ev& a, const Ev& b) {
        const uint64_t s = std::max(a.down, b.down), en = std::min(end_of(a), end_of(b));
        return en > s ? double(en - s) : 0.0;
    };
    // a から見た b との重なりの割合 (b がまだ押されているなら a の押していた時間に対して、両方離していれば短い方に対して)
    auto ratio = [&](const Ev& a, const Ev& b) {
        const double base = b.released ? std::min(dur(a), dur(b)) : dur(a);
        return base > 0 ? overlap(a, b) / base : 0.0;
    };
    for (size_t i = 0; i < evs_.size(); i++) {
        Ev& e = evs_[i];
        if (e.decided || e.is_shift) continue;
        const bool long_alone = !e.released && now - e.down >= window_ms;
        if (!e.released && !long_alone) continue;
        // 組になれる相手: まだ決まっていない字と、シフトの記録 (組んだ後も押している間は使える)。重なりが十分なもの
        std::vector<size_t> strong;
        // シフトの記録を、相手の候補として evs_ の後ろに一時的に並べる (番号 >= evs_.size() はシフトの記録)
        const size_t n_ev = evs_.size();
        std::vector<Ev> sh;
        for (auto& r : shifts_) {
            Ev x;
            x.key = r.key;
            x.is_shift = true;
            x.down = r.down;
            x.up = r.up;
            x.released = r.released;
            x.shift_id = r.id;
            sh.push_back(x);
        }
        auto at = [&](size_t j) -> Ev& { return j < n_ev ? evs_[j] : sh[j - n_ev]; };
        for (size_t j = 0; j < n_ev + sh.size(); j++) {
            if (j == i) continue;
            const Ev& x = at(j);
            if (j < n_ev && x.is_shift) continue;   // シフトは記録の方で見る
            if (!x.is_shift && x.decided) continue;
            if (j >= n_ev) {
                bool used = false;
                for (auto& r : shifts_) if (r.id == x.shift_id) used = r.used;
                if (used && (!continuous || !(e.released ? (!x.released || x.up >= e.up) : long_alone))) continue;
            }
            // 字どうしは押した時刻が近いときだけ (片方を長く押したまま、ずっと後でもう片方を押したのは組にしない)
            if (!x.is_shift && (x.down > e.down ? x.down - e.down : e.down - x.down) > window_ms * 3 / 2) continue;
            if (ratio(e, x) >= overlap_ratio || (long_alone && !x.released && x.down <= e.down && x.is_shift)) strong.push_back(j);
        }
        if (long_alone && strong.empty()) {
            // 1 つだけ長く押している: まだほかと重なっていなければ単打に決める (重なっている相手が後から来たら待つ)
            bool any = false;
            for (size_t j = 0; j < n_ev; j++) any = any || (j != i && !evs_[j].is_shift && !evs_[j].decided && overlap(e, evs_[j]) > 0);
            for (auto& x : sh) any = any || overlap(e, x) > 0;
            if (any) continue;
        } else if (long_alone) {
            continue;   // 重なっている相手がいる: 離すまで待つ
        }
        auto absorb = [&](const std::vector<size_t>& with, const u16& out) {
            size_t first = i;   // 出す位置は組の中でいちばん先に押したキー
            for (size_t j : with) if (j < n_ev) first = std::min(first, j);
            e.decided = true;
            for (size_t j : with) {
                if (j >= n_ev) {   // シフト: 使った印 (単打を出さない)。evs_ の方も決まりにして後ろの字を待たせない
                    const int id = at(j).shift_id;
                    for (auto& r : shifts_) if (r.id == id) r.used = true;
                    for (auto& x : evs_) if (x.shift_id == id) { x.used = true; x.decided = true; }
                } else {
                    evs_[j].decided = true;
                }
            }
            evs_[first].out = emit(out);
            if (first != i) e.out.clear();
        };
        bool done = false;
        // 3 キー
        for (size_t a = 0; a < strong.size() && !done; a++)
            for (size_t b = a + 1; b < strong.size() && !done; b++) {
                auto it = chords_.find(chord_key({e.key, at(strong[a]).key, at(strong[b]).key}));
                if (it != chords_.end()) { absorb({strong[a], strong[b]}, it->second); done = true; }
            }
        // 2 キー (重なりの大きい相手から)
        std::sort(strong.begin(), strong.end(), [&](size_t a, size_t b) { return ratio(e, at(a)) > ratio(e, at(b)); });
        for (size_t a = 0; a < strong.size() && !done; a++) {
            auto it = chords_.find(chord_key({e.key, at(strong[a]).key}));
            if (it != chords_.end()) { absorb({strong[a]}, it->second); done = true; }
        }
        if (!done) {
            e.decided = true;
            e.out = emit(lookup1(e.key, e.shift).text);
        }
    }
    // シフト: 離して、重なっていた字が全部決まったら。どの字とも組まなかったら単打 (空白・無変換・変換)
    for (auto& s : evs_) {
        if (!s.is_shift || s.decided || !s.released) continue;   // まだ押している・使った (決まり済み) シフトは見ない
        bool wait = false;
        for (auto& c : evs_) wait = wait || (!c.is_shift && !c.decided && overlap(s, c) > 0);
        if (wait) continue;
        s.decided = true;
        for (auto& r : shifts_) if (r.id == s.shift_id && r.used) s.used = true;
        if (!s.used) {
            auto it = single_.find(s.key);
            if (it != single_.end()) s.out = emit(it->second);
            else if (s.key == "space") s.out.push_back({u16(), "space"});
            else if (!thumb_tap) {}   // 親指キーの単独打鍵は何もしない
            else if ((s.key == "rthumb" && thumbs == 1) || (s.key == "lthumb" && thumbs == 2)) s.out.push_back({u16(), "space"});   // 空白を親指にしたとき
            else if (s.key == "lthumb" || s.key == "rthumb") s.out.push_back({u16(), s.key == "lthumb" ? "muhenkan" : "henkan"});
        }
    }
    shifts_.erase(std::remove_if(shifts_.begin(), shifts_.end(), [&](const ShiftRec& r) {
        if (!r.released || now - r.up < 1000) return false;
        for (auto& c : evs_) if (!c.is_shift && !c.decided && c.down <= r.up) return false;
        return true;
    }), shifts_.end());
    // 決まったものを押した順に出す (前が決まっていなければ待つ)
    std::vector<Out> out;
    while (!evs_.empty() && evs_.front().decided) {
        out.insert(out.end(), evs_.front().out.begin(), evs_.front().out.end());
        evs_.pop_front();
    }
    return out;
}

std::string key_name_from_scancode(unsigned sc, bool extended) {
    if (extended) return std::string();
    switch (sc) {
        case 0x02: return "1"; case 0x03: return "2"; case 0x04: return "3"; case 0x05: return "4"; case 0x06: return "5";
        case 0x07: return "6"; case 0x08: return "7"; case 0x09: return "8"; case 0x0A: return "9"; case 0x0B: return "0";
        case 0x0C: return "-"; case 0x0D: return "=";
        case 0x10: return "q"; case 0x11: return "w"; case 0x12: return "e"; case 0x13: return "r"; case 0x14: return "t";
        case 0x15: return "y"; case 0x16: return "u"; case 0x17: return "i"; case 0x18: return "o"; case 0x19: return "p";
        case 0x1A: return "["; case 0x1B: return "]";
        case 0x1E: return "a"; case 0x1F: return "s"; case 0x20: return "d"; case 0x21: return "f"; case 0x22: return "g";
        case 0x23: return "h"; case 0x24: return "j"; case 0x25: return "k"; case 0x26: return "l"; case 0x27: return ";";
        case 0x28: return "'"; case 0x29: return "`"; case 0x2B: return "\\";
        case 0x2C: return "z"; case 0x2D: return "x"; case 0x2E: return "c"; case 0x2F: return "v"; case 0x30: return "b";
        case 0x31: return "n"; case 0x32: return "m"; case 0x33: return ","; case 0x34: return "."; case 0x35: return "/";
        case 0x39: return "space";
        case 0x73: return "ro";     // JIS の \ _ (ろ)
        case 0x7D: return "yen";    // JIS の ¥ |
        case 0x7B: return "lthumb"; // 無変換
        case 0x79: return "rthumb"; // 変換
        default: return std::string();
    }
}

}  // namespace shunti
