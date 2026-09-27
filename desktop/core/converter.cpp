#include "converter.h"

#include <algorithm>

#include "engine.h"
#include "pos_classes.h"
#include "tables.h"

namespace shunti {

namespace {
const uint16_t* p16(const u16& s) { return reinterpret_cast<const uint16_t*>(s.data()); }

char pos_class(int id) { return id >= 0 && id < POS_CLASS_COUNT ? POS_CLASSES[id] : '0'; }

bool is_punct(const u16& s) {
    return !s.empty() && s.find_first_not_of(u"、。，．！？!?…‥・,.") == u16::npos;
}

// 長すぎる読みを分ける位置 (真ん中より前の最後の句読点の後ろ。無ければ真ん中)
size_t split_point(const u16& kana) {
    size_t mid = std::min<size_t>(kana.size() / 2, 120);
    for (size_t i = mid; i > mid / 2; i--)
        if (u16(u"、。！？!?").find(kana[i - 1]) != u16::npos) return i;
    return mid;
}
}  // namespace

bool is_slur(const u16& s) {
    for (const auto& r : SLURS) {
        u16 w = r.word;
        for (size_t i = s.find(w); i != u16::npos; i = s.find(w, i + 1)) {
            bool excused = false;
            for (int k = 0; r.not_after[k]; k++)
                if (s.compare(i + w.size(), u16(r.not_after[k]).size(), r.not_after[k]) == 0) excused = true;
            if (!excused) return true;
        }
    }
    return false;
}

Converter::~Converter() {
    if (e_) kkc_close(e_);
}

bool Converter::open(const void* lex, size_t lex_size, const void* model, size_t model_size, int threads) {
    if (e_) kkc_close(e_);
    e_ = kkc_open(lex, lex_size, model, model_size);
    if (e_ && threads > 0) kkc_set_threads(e_, threads);
    return e_ != nullptr;
}

bool Converter::convert_once(const u16& ctx, const u16& kana, int max, Conversion& out) {
    out = Conversion();
    int want = max * 2;
    std::vector<uint16_t> buf(size_t(want) * (kana.size() * 4 + 16) + 64);
    int n = kkc_convert(e_, p16(ctx), int(ctx.size()), p16(kana), int(kana.size()), want, 1, buf.data(), int(buf.size()));
    if (n == -3) return false;
    if (n <= 0) return true;
    std::vector<u16> raw;
    for (size_t i = 0, st = 0; int(raw.size()) < n && i < buf.size(); i++) {
        if (buf[i] == 0) { raw.emplace_back(reinterpret_cast<const char16_t*>(buf.data() + st), i - st); st = i + 1; }
    }
    for (auto& c : raw) {
        if (int(out.cands.size()) >= max) break;
        if (!is_slur(c)) out.cands.push_back(c);
    }
    // 差別語で 1 位が落ちたときは区切りを使わない (区切りは元の 1 位のもの)
    if (raw.empty() || out.cands.empty() || out.cands[0] != raw[0]) return true;
    std::vector<int32_t> ends(kana.size() + 1), lens(kana.size() + 1), lids(kana.size() + 1), rids(kana.size() + 1);
    int m = kkc_last_segments(e_, ends.data(), lens.data(), int(ends.size()));
    if (m <= 0 || kkc_last_segment_pos(e_, lids.data(), rids.data(), int(lids.size())) != m) return true;
    const u16& top = raw[0];
    size_t r0 = 0, s0 = 0;
    for (int i = 0; i < m; i++) {
        size_t r1 = size_t(ends[i]), s1 = s0 + size_t(lens[i]);
        if (r1 < r0 || r1 > kana.size() || s1 > top.size()) { out.words.clear(); return true; }
        Word w{kana.substr(r0, r1 - r0), top.substr(s0, s1 - s0), lids[i], rids[i], false};
        w.pass = !w.reading.empty() && w.reading == w.surface && !is_reading_char(w.reading[0]);
        out.words.push_back(std::move(w));
        r0 = r1;
        s0 = s1;
    }
    if (r0 != kana.size() || s0 != top.size()) out.words.clear();
    return true;
}

Conversion Converter::convert(const u16& ctx, const u16& kana, int max) {
    Conversion out;
    if (!e_ || kana.empty()) return out;
    if (convert_once(ctx, kana, max, out)) return out;
    // 長すぎる: 前と後ろに分けて変換し、1 位どうしをつなぐ (後ろは前の 1 位を文脈にする)
    size_t sp = split_point(kana);
    Conversion a = convert(ctx, kana.substr(0, sp), 1);
    u16 sa = a.cands.empty() ? kana.substr(0, sp) : a.cands[0];
    Conversion b = convert(ctx + sa, kana.substr(sp), 1);
    u16 sb = b.cands.empty() ? kana.substr(sp) : b.cands[0];
    out.cands.push_back(sa + sb);
    if (a.words.empty()) a.words.push_back({kana.substr(0, sp), sa});
    if (b.words.empty()) b.words.push_back({kana.substr(sp), sb});
    out.words = a.words;
    out.words.insert(out.words.end(), b.words.begin(), b.words.end());
    return out;
}

std::vector<u16> Converter::complete(const u16& prefix, int max, int max_extra) {
    std::vector<u16> out;
    if (!e_ || prefix.empty()) return out;
    std::vector<uint16_t> buf(size_t(max) * 64 + 64);
    int n = kkc_complete(e_, p16(prefix), int(prefix.size()), max_extra, max, buf.data(), int(buf.size()));
    for (size_t i = 0, st = 0; n > 0 && int(out.size()) < n && i < buf.size(); i++) {
        if (buf[i] == 0) { out.emplace_back(reinterpret_cast<const char16_t*>(buf.data() + st), i - st); st = i + 1; }
    }
    out.erase(std::remove_if(out.begin(), out.end(), is_slur), out.end());
    return out;
}

int Converter::set_user_words(const std::vector<UserDict::Form>& forms, int bonus) {
    if (!e_) return 0;
    kkc_user_clear(e_);
    int n = 0;
    for (auto& f : forms)
        n += kkc_user_add_like(e_, p16(f.reading), int(f.reading.size()), p16(f.surface), int(f.surface.size()),
                               p16(f.tmpl_reading), int(f.tmpl_reading.size()), p16(f.tmpl_surface), int(f.tmpl_surface.size()), bonus);
    return n;
}

std::vector<Phrase> group_phrases(const std::vector<Word>& words) {
    std::vector<Phrase> out;
    bool in_tail = false;   // いまの文節の付属語の部分に入った
    for (size_t i = 0; i < words.size(); i++) {
        const Word& w = words[i];
        bool attach = false, head = false;
        if (i > 0) {
            const Word& p = words[i - 1];
            attach = pos_class(w.lid) == '1' || is_punct(w.surface) || (pos_class(w.lid) == '4' && pos_class(p.rid) == '3');
            head = !attach && (pos_class(p.rid) == '2' || (p.pass && w.pass)) && !in_tail;
            // 辞書に無い語 (かなのまま・カタカナ) は名詞の ID なので自立語になる
        }
        if ((attach || head) && !out.empty()) {
            Phrase& ph = out.back();
            ph.reading += w.reading;
            ph.surface += w.surface;
            if (head) { ph.head_r = ph.reading.size(); ph.head_s = ph.surface.size(); }
            else in_tail = true;
        } else {
            out.push_back({w.reading, w.surface, w.reading.size(), w.surface.size()});
            in_tail = false;
        }
    }
    return out;
}

}  // namespace shunti
