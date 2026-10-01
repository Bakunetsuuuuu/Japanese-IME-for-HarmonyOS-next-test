// 端末で動くかな漢字変換エンジン。engine.h の説明を参照。
//
// 1 回の変換:
//   1. 網 (lattice.Lexicon.edges と同じ辺を同じ順に)
//   2. 下書き = 辞書のコストだけの 1 位 (best_path)
//   3. エンコーダ: [文脈 40 字] SEP [読み] SEP [下書き] を Transformer (pre-LN) に 1 回通す
//   4. 区間 q と語 k。どちらも最初の層は線形なので、区間は位置ごと・語は文字ごとに前もって掛けておき、
//      区間・語ごとには足し算 + 2 層目だけを計算する
//   5. u = q·k / √dk を辺の点数にして K-best Viterbi (lattice.nbest と同じ順・同じ浮動小数の計算)
//
// ファイル形式 (学習側の書き出しの道具が書く。各配列は 8 バイト境界から):
//   lex.bin   "KKL2" int32×13 (版, 名詞, 算用数字, 漢数字, 最長の読み, OOV, カタカナ, カタカナ/字, 素通し, 品詞数, conn16, 読み数, 語数)
//             int64×2 (読みの UTF-16 の総数, 表記の UTF-16 の総数)
//             conn[品詞数²] (int16 か int32)  読みの位置 u32[読み数+1]  語の範囲 u32[読み数+1]  語 {u32 表記の位置, u16 長さ, u16 左, u16 右, u16, i32 コスト}[語数]
//             読み u16[]  表記 u16[]
//   model.bin "KKM1" int32×12 (版, 語彙, d, 層, 頭, ff, dk, 最大長, 区分, 文脈, 下書きの最大, 下書きあり) float×2 (β, γ)
//             int32 文字数, u32 文字[] (語彙の 4 番から)、あとは float32 の重み (export_model の順)
#include "engine.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

// x86 (PC) では、AVX2 + FMA が使える CPU のときだけ速い版の計算 (engine_simd.h) を使う (起動時に CPU を見て選ぶ)。
// ビルドは古い命令のまま (どの x86 の CPU でも動く)。ARM (スマホ) は今までどおり (コンパイラが NEON にする)
#include <cstdlib>
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#define KKC_X86 1
#if defined(_MSC_VER) && !defined(__clang__)
#include <intrin.h>
// MSVC は engine_avx2.cpp (/arch:AVX2) にある
extern "C" void kkc_avx2_lin(const float* X, int T, int in, const float* WT, int ldw, const float* B, float* Y, int ldy, int o0, int o1);
extern "C" void kkc_avx2_gelu(float* v, size_t n);
extern "C" void kkc_avx2_attend(const float* qkv, int T, int d, int dh, int hh, float scale, float* sc, float* att);
extern "C" void kkc_avx2_quant_rows(const float* X, int T, int in, int inp, short* Xq, float* xs);
extern "C" void kkc_avx2_lin_q(const short* Xq, const float* xs, int T, int inp, const short* Wp, const float* ws,
                               const float* B, float* Y, int ldy, int o0, int o1);
#else
#define KKC_AVX2_FN __attribute__((target("avx2,fma")))
#include "engine_simd.h"
#define kkc_avx2_lin kkc_simd_lin
#define kkc_avx2_gelu kkc_simd_gelu
#define kkc_avx2_attend kkc_simd_attend
#define kkc_avx2_quant_rows kkc_simd_quant_rows
#define kkc_avx2_lin_q kkc_simd_lin_q
#endif
#else
#define KKC_X86 0
#endif

namespace {

typedef std::u32string ustr;
enum Kind { K_DICT = 0, K_KANA = 1, K_KATA = 2, K_PASS = 3, K_NUM = 4 };
const int UNK = 1, SEP = 2;

struct Ent { uint32_t soff; uint16_t slen, lid, rid, pad; int32_t cost; };
static_assert(sizeof(Ent) == 16, "Ent");

struct Edge { int s, e; ustr surf; int32_t lid, rid, cost; Kind kind; };

// 1 位の候補の語: 読みの終わりの位置・表記の長さ (UTF-16)・品詞の左右 ID
struct SegInfo { int e, l16, lid, rid; };

// ユーザー辞書の語 (読み・表記・品詞の左右 ID・コスト)。辞書の語と同じく網に入れ、モデルが文脈で採点する
struct UserWord { ustr r, s; int32_t lid, rid, cost; };

inline bool is_kana(char32_t c) { return (c >= 0x3041 && c <= 0x3096) || c == 0x30FC || c == 0x3094; }
inline char32_t kata(char32_t c) { return (c >= 0x3041 && c <= 0x3096) ? c + 0x60 : c; }
ustr to_kata(const ustr& s) { ustr o = s; for (auto& c : o) c = kata(c); return o; }

ustr from16(const uint16_t* p, size_t n) {
    ustr o;
    o.reserve(n);
    for (size_t i = 0; i < n; i++) {
        uint32_t c = p[i];
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && p[i + 1] >= 0xDC00 && p[i + 1] < 0xE000) {
            c = 0x10000 + ((c - 0xD800) << 10) + (p[i + 1] - 0xDC00);
            i++;
        }
        o.push_back(char32_t(c));
    }
    return o;
}

void to16(const ustr& s, std::vector<uint16_t>& o) {
    for (char32_t c : s) {
        if (c >= 0x10000) {
            uint32_t v = uint32_t(c) - 0x10000;
            o.push_back(uint16_t(0xD800 + (v >> 10)));
            o.push_back(uint16_t(0xDC00 + (v & 0x3FF)));
        } else o.push_back(uint16_t(c));
    }
}

// ---------------------------------------------------------------- 辞書 (mmap したファイルを読むだけ)
struct Lex {
    int32_t noun, num_arabic, num_kanji, max_word, oov, kata, kata_per, pass, nconn, conn16, nread, nent;
    const int16_t* c16 = nullptr;
    const int32_t* c32 = nullptr;
    const uint32_t* r_off;
    const uint32_t* e_first;
    const Ent* ents;
    const uint16_t* r_blob;
    const uint16_t* s_blob;

    inline int conn(int a, int b) const { size_t i = size_t(a) * nconn + b; return c16 ? c16[i] : c32[i]; }

    // 読み (UTF-16 の並び) の語の範囲。無ければ false
    bool find(const uint16_t* k, int n, uint32_t& lo_e, uint32_t& hi_e) const {
        int lo = 0, hi = nread;
        while (lo < hi) {
            int mid = (lo + hi) >> 1;
            const uint16_t* r = r_blob + r_off[mid];
            int rn = int(r_off[mid + 1] - r_off[mid]);
            int m = std::min(rn, n), c = 0;
            for (int i = 0; i < m && !c; i++) c = int(r[i]) - int(k[i]);
            if (!c) c = rn - n;
            if (c < 0) lo = mid + 1; else hi = mid;
        }
        if (lo >= nread) return false;
        const uint16_t* r = r_blob + r_off[lo];
        int rn = int(r_off[lo + 1] - r_off[lo]);
        if (rn != n || memcmp(r, k, size_t(n) * 2)) return false;
        lo_e = e_first[lo];
        hi_e = e_first[lo + 1];
        return true;
    }
};

struct Reader {
    const uint8_t* p;
    const uint8_t* end;
    size_t off = 0;
    bool ok = true;
    template <class T> const T* arr(size_t n) {
        off = (off + 7) & ~size_t(7);
        if (off + n * sizeof(T) > size_t(end - p)) { ok = false; return nullptr; }
        const T* r = reinterpret_cast<const T*>(p + off);
        off += n * sizeof(T);
        return r;
    }
    template <class T> T val() {
        T v;
        if (off + sizeof(T) > size_t(end - p)) { ok = false; return T(); }
        memcpy(&v, p + off, sizeof(T));
        off += sizeof(T);
        return v;
    }
};

// ---------------------------------------------------------------- 数の読み (学習側と同じ規則)
struct Piece { ustr k; char kind; int64_t v; };
struct Sok { ustr k; int64_t v, unit; };
std::vector<Piece> PIECES;
std::vector<Sok> SOKUON;
const char32_t* KANJI = U"〇一二三四五六七八九";

void init_numbers() {
    if (!PIECES.empty()) return;
    std::vector<Piece> p = {
        {U"いち", 'd', 1}, {U"に", 'd', 2}, {U"さん", 'd', 3}, {U"よん", 'd', 4}, {U"し", 'd', 4}, {U"ご", 'd', 5},
        {U"ろく", 'd', 6}, {U"なな", 'd', 7}, {U"しち", 'd', 7}, {U"はち", 'd', 8}, {U"きゅう", 'd', 9}, {U"く", 'd', 9},
        {U"れい", 'd', 0}, {U"ぜろ", 'd', 0}, {U"いっ", 'd', 1}, {U"ろっ", 'd', 6}, {U"はっ", 'd', 8},
        {U"じゅう", 's', 10}, {U"ひゃく", 's', 100}, {U"びゃく", 's', 100}, {U"ぴゃく", 's', 100}, {U"せん", 's', 1000},
        {U"ぜん", 's', 1000}, {U"まん", 'b', 10000}, {U"おく", 'b', 100000000LL}, {U"ちょう", 'b', 1000000000000LL}};
    std::stable_sort(p.begin(), p.end(), [](const Piece& a, const Piece& b) { return a.k.size() > b.k.size(); });
    PIECES = p;
    SOKUON = {{U"いっ", 1, 1}, {U"ろっ", 6, 1}, {U"はっ", 8, 1}, {U"じゅっ", 10, 10}, {U"じっ", 10, 10},
              {U"ひゃっ", 100, 100}, {U"せっ", 1000, 1000}};
}

inline bool starts_with(const ustr& s, size_t i, const ustr& k) { return i + k.size() <= s.size() && s.compare(i, k.size(), k) == 0; }
inline bool ends_with(const ustr& s, const ustr& k) { return s.size() >= k.size() && s.compare(s.size() - k.size(), k.size(), k) == 0; }

bool parse(const ustr& r, int64_t& value, bool& sokuon) {
    if (r.size() < 2) return false;
    const Sok* sok = nullptr;
    for (auto& s : SOKUON) if (ends_with(r, s.k)) { sok = &s; break; }
    ustr body = sok ? r.substr(0, r.size() - sok->k.size()) : r;
    std::vector<std::pair<char, int64_t>> toks;
    size_t i = 0;
    while (i < body.size()) {
        bool hit = false;
        for (auto& p : PIECES) if (starts_with(body, i, p.k)) { toks.push_back({p.kind, p.v}); i += p.k.size(); hit = true; break; }
        if (!hit) return false;
    }
    if (sok) {
        if (sok->unit > 1 && sok->v == sok->unit) toks.push_back({'s', sok->unit});
        else toks.push_back({'d', sok->v});
    }
    if (toks.empty()) return false;
    int64_t total = 0, group = 0, last_small = 100000;
    bool has_digit = false; int64_t digit = 0;
    for (auto& t : toks) {
        if (t.first == 'd') {
            if (has_digit) return false;
            has_digit = true; digit = t.second;
        } else if (t.first == 's') {
            if (t.second >= last_small) return false;
            group += (has_digit ? digit : 1) * t.second;
            has_digit = false; last_small = t.second;
        } else {
            group += has_digit ? digit : 0;
            if (group == 0) return false;
            total += group * t.second;
            group = 0; has_digit = false; last_small = 100000;
        }
    }
    group += has_digit ? digit : 0;
    value = total + group;
    if (value == 0 && !(toks.size() == 1 && toks[0].first == 'd' && toks[0].second == 0)) return false;
    sokuon = sok != nullptr;
    return true;
}

ustr kanji(int64_t n) {
    if (n == 0) return U"〇";
    ustr out;
    const int64_t bigs[4] = {1000000000000LL, 100000000LL, 10000LL, 1};
    const char32_t* names[4] = {U"兆", U"億", U"万", U""};
    const int64_t units[4] = {1000, 100, 10, 1};
    const char32_t* un[4] = {U"千", U"百", U"十", U""};
    for (int b = 0; b < 4; b++) {
        int64_t g = n / bigs[b]; n %= bigs[b];
        if (!g) continue;
        ustr s;
        for (int u = 0; u < 4; u++) {
            int64_t d = g / units[u]; g %= units[u];
            if (d) { if (!(d == 1 && units[u] > 1)) s += KANJI[d]; s += un[u]; }
        }
        out += s + names[b];
    }
    return out;
}

ustr digits(int64_t v, bool full) {
    std::string a = std::to_string(v);
    ustr o;
    for (char c : a) o += full ? char32_t(0xFF10 + (c - '0')) : char32_t(c);
    return o;
}

std::vector<size_t> boundaries(const ustr& r, size_t s) {
    std::vector<size_t> out;
    size_t i = s;
    while (i < r.size()) {
        bool hit = false;
        for (auto& p : PIECES) if (starts_with(r, i, p.k)) { i += p.k.size(); out.push_back(i); hit = true; break; }
        if (!hit) {
            for (auto& k : SOKUON) if (starts_with(r, i, k.k)) out.push_back(i + k.k.size());
            break;
        }
    }
    return out;
}

void number_edges(const Lex& L, const ustr& r, std::vector<Edge>& out) {
    const int base = 4000, per_char = -150;
    for (size_t s = 0; s < r.size(); s++) {
        for (size_t e : boundaries(r, s)) {
            if (e - s < 2 || e - s > 24) continue;
            int64_t v; bool sk;
            if (!parse(r.substr(s, e - s), v, sk)) continue;
            int c = std::max(3000, base + per_char * int(e - s));
            out.push_back({int(s), int(e), digits(v, false), L.num_arabic, L.num_arabic, c, K_NUM});
            out.push_back({int(s), int(e), digits(v, true), L.num_arabic, L.num_arabic, c + 2000, K_NUM});
            out.push_back({int(s), int(e), kanji(v), L.num_kanji, L.num_kanji, c + 500, K_NUM});
        }
    }
}

void special_edges(const Lex& L, const ustr& r, std::vector<Edge>& out) {
    const int cost = 4500;
    const std::vector<std::pair<ustr, ustr>> fixed = {{U"ひとり", U"1人"}, {U"ふたり", U"2人"}, {U"はたち", U"20歳"}};
    for (auto& f : fixed) {
        size_t i = r.find(f.first);
        while (i != ustr::npos) {
            out.push_back({int(i), int(i + f.first.size()), f.second, L.noun, L.noun, cost + 2000, K_NUM});
            i = r.find(f.first, i + 1);
        }
    }
    const std::vector<std::pair<ustr, int>> days = {
        {U"ついたち", 1}, {U"ふつか", 2}, {U"みっか", 3}, {U"よっか", 4}, {U"いつか", 5}, {U"むいか", 6}, {U"なのか", 7},
        {U"ようか", 8}, {U"ここのか", 9}, {U"とおか", 10}, {U"はつか", 20}};
    for (auto& w : days) {
        size_t e0 = r.find(w.first);
        while (e0 != ustr::npos) {
            size_t e = e0 + w.first.size();
            std::vector<std::pair<size_t, int64_t>> starts = {{e0, w.second}};
            if (w.second < 10) {
                for (size_t s = (e0 >= 12 ? e0 - 12 : 0); s < e0; s++) {
                    int64_t t; bool sk;
                    if (parse(r.substr(s, e0 - s), t, sk) && !sk && t % 10 == 0 && t > 0 && t <= 30)
                        starts.push_back({s, t + w.second});
                }
            }
            for (auto& sv : starts) {
                if (sv.second > 31) continue;
                int span = int(e - sv.first);
                out.push_back({int(sv.first), int(e), digits(sv.second, false) + U"日", L.noun, L.noun, cost + 200 * span, K_NUM});
                out.push_back({int(sv.first), int(e), digits(sv.second, true) + U"日", L.noun, L.noun, cost + 2000 + 200 * span, K_NUM});
                out.push_back({int(sv.first), int(e), kanji(sv.second) + U"日", L.noun, L.noun, cost + 300 + 200 * span, K_NUM});
            }
            e0 = r.find(w.first, e0 + 1);
        }
    }
}

std::vector<Edge> edges(const Lex& L, const ustr& r, const std::vector<UserWord>* user = nullptr) {
    std::vector<Edge> out;
    int n = int(r.size());
    std::vector<uint16_t> key;
    for (int s = 0; s < n; s++) {
        if (!is_kana(r[s])) { out.push_back({s, s + 1, r.substr(s, 1), L.noun, L.noun, L.pass, K_PASS}); continue; }
        key.clear();
        for (int e = s + 1; e <= std::min(n, s + L.max_word); e++) {
            if (!is_kana(r[e - 1])) break;
            key.push_back(uint16_t(r[e - 1]));   // かなは BMP
            uint32_t a, b;
            if (L.find(key.data(), int(key.size()), a, b)) {
                for (uint32_t j = a; j < b; j++) {
                    const Ent& en = L.ents[j];
                    out.push_back({s, e, from16(L.s_blob + en.soff, en.slen), en.lid, en.rid, en.cost, K_DICT});
                }
            }
            if (e - s == 1) {
                out.push_back({s, e, r.substr(s, 1), L.noun, L.noun, L.oov, K_KANA});
                if (r[s] != 0x30FC) out.push_back({s, e, ustr(1, kata(r[s])), L.noun, L.noun, L.kata + L.kata_per, K_KATA});
            } else if (e - s <= 12) {
                out.push_back({s, e, to_kata(r.substr(s, e - s)), L.noun, L.noun, L.kata + L.kata_per * (e - s), K_KATA});
            }
        }
    }
    // ユーザー辞書: 読みが現れる所すべてに辞書の語として置く
    if (user) {
        for (const UserWord& w : *user) {
            if (w.r.empty()) continue;
            for (size_t i = r.find(w.r); i != ustr::npos; i = r.find(w.r, i + 1))
                out.push_back({int(i), int(i + w.r.size()), w.s, w.lid, w.rid, w.cost, K_DICT});
        }
    }
    std::vector<Edge> num;
    number_edges(L, r, num);
    special_edges(L, r, num);
    for (auto& ed : num) {
        bool ok = true;
        for (int i = ed.s; i < ed.e; i++) if (!is_kana(r[i])) { ok = false; break; }
        if (ok) out.push_back(std::move(ed));
    }
    return out;
}

ustr best_path(const Lex& L, const std::vector<Edge>& E, int n) {
    int M = int(E.size());
    if (!M) return ustr();
    std::vector<int> order(M);
    for (int i = 0; i < M; i++) order[i] = i;
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return E[a].s < E[b].s; });
    std::vector<int> ptr(n + 2, 0), by_end(M);
    for (auto& e : E) ptr[e.e + 1]++;
    for (int p = 0; p <= n; p++) ptr[p + 1] += ptr[p];
    std::vector<int> fill(ptr);
    for (int i = 0; i < M; i++) by_end[fill[E[i].e]++] = i;
    std::vector<double> best(M, 1e18);
    std::vector<int> prev(M, -1);
    for (int t = 0; t < M; t++) {
        int i = order[t], s = E[i].s;
        if (s == 0) { best[i] = double(L.conn(0, E[i].lid)) + E[i].cost; continue; }
        for (int q = ptr[s]; q < ptr[s + 1]; q++) {
            int j = by_end[q];
            if (best[j] >= 1e17) continue;
            double v = best[j] + L.conn(E[j].rid, E[i].lid) + E[i].cost;
            if (v < best[i]) { best[i] = v; prev[i] = j; }
        }
    }
    int bi = -1; double bv = 1e18;
    for (int q = ptr[n]; q < ptr[n + 1]; q++) {
        int j = by_end[q];
        double v = best[j] + L.conn(E[j].rid, 0);
        if (v < bv) { bv = v; bi = j; }
    }
    std::vector<int> path;
    while (bi >= 0) { path.push_back(bi); bi = prev[bi]; }
    ustr out;
    for (auto it = path.rbegin(); it != path.rend(); ++it) out += E[*it].surf;
    return out;
}

// ---------------------------------------------------------------- 採点器
struct LayerW { const float *ln1w, *ln1b, *inw, *inb, *outw, *outb, *ln2w, *ln2b, *l1w, *l1b, *l2w, *l2b; };

struct Model {
    int V, d, layers, heads, ff, dk, max_len, n_seg, ctx, draft_max, draft;
    float beta, gamma;
    std::unordered_map<char32_t, int> vocab;
    const float *emb, *seg, *pos;
    std::vector<LayerW> L;
    const float *normw, *normb, *end, *q1w, *q1b, *q2w, *q2b, *Pa, *Pb, *Pc, *Kkind, *Klen, *k1b, *k2w, *k2b;
    int vid(char32_t c) const { auto it = vocab.find(c); return it == vocab.end() ? UNK : it->second; }
};

inline float gelu(float x) { return 0.5f * x * (1.0f + std::erf(x * 0.70710678118654752f)); }

// 使い回すスレッド (打鍵ごとにスレッドを作ると、その分だけ遅い)
struct Pool {
    std::vector<std::thread> th;
    std::mutex mu;
    std::condition_variable cv, done;
    std::function<void(int)> job;
    int n = 1, gen = 0, pending = 0;
    bool stop = false;
    void resize(int k) {
        shutdown();
        n = std::max(1, k);
        stop = false;
        for (int i = 1; i < n; i++)
            th.emplace_back([this, i] {
                int seen = 0;
                for (;;) {
                    std::function<void(int)> f;
                    {
                        std::unique_lock<std::mutex> lk(mu);
                        cv.wait(lk, [&] { return stop || gen != seen; });
                        if (stop) return;
                        seen = gen;
                        f = job;
                    }
                    f(i);
                    std::lock_guard<std::mutex> lk(mu);
                    if (--pending == 0) done.notify_one();
                }
            });
    }
    // f(0..n-1) を全スレッドで 1 回ずつ
    void run(const std::function<void(int)>& f) {
        if (n <= 1) { f(0); return; }
        {
            std::lock_guard<std::mutex> lk(mu);
            job = f;
            pending = n - 1;
            gen++;
        }
        cv.notify_all();
        f(0);
        std::unique_lock<std::mutex> lk(mu);
        done.wait(lk, [&] { return pending == 0; });
    }
    void shutdown() {
        {
            std::lock_guard<std::mutex> lk(mu);
            stop = true;
        }
        cv.notify_all();
        for (auto& t : th) t.join();
        th.clear();
    }
    ~Pool() { shutdown(); }
};

// Y[t][o] = Σ_i X[t][i] · WT[i][o] + B[o] の、出力 [o0, o1) の分。WT は (入力, 出力) の向き (出力方向に連続)。
// 出力 16 本 × 行 4 本を一度に計算する (NEON / AVX で 16 本がベクトル 4 本 / 2 本になる)。
// 出力のかたまりを外側に回すので、重みはメモリから 1 回だけ読まれる (行のほうは L1/L2 に載っている)。
void lin_part(const float* X, int T, int in, const float* WT, int ldw, const float* B, float* Y, int ldy, int o0, int o1) {
    int o = o0;
    for (; o + 16 <= o1; o += 16) {
        for (int t = 0; t < T; t += 4) {
            const int tn = std::min(4, T - t);
            const float* x0 = X + size_t(t) * in;
            const float* x1 = tn > 1 ? x0 + in : x0;
            const float* x2 = tn > 2 ? x0 + 2 * size_t(in) : x0;
            const float* x3 = tn > 3 ? x0 + 3 * size_t(in) : x0;
            float a0[16], a1[16], a2[16], a3[16];
            for (int j = 0; j < 16; j++) a0[j] = a1[j] = a2[j] = a3[j] = B ? B[o + j] : 0.0f;
            for (int i = 0; i < in; i++) {
                const float* w = WT + size_t(i) * ldw + o;
                const float v0 = x0[i], v1 = x1[i], v2 = x2[i], v3 = x3[i];
                for (int j = 0; j < 16; j++) {
                    const float wj = w[j];
                    a0[j] += v0 * wj; a1[j] += v1 * wj; a2[j] += v2 * wj; a3[j] += v3 * wj;
                }
            }
            float* y = Y + size_t(t) * ldy + o;
            for (int j = 0; j < 16; j++) y[j] = a0[j];
            if (tn > 1) for (int j = 0; j < 16; j++) y[ldy + j] = a1[j];
            if (tn > 2) for (int j = 0; j < 16; j++) y[2 * ldy + j] = a2[j];
            if (tn > 3) for (int j = 0; j < 16; j++) y[3 * ldy + j] = a3[j];
        }
    }
    for (; o < o1; o++)   // 16 で割り切れない残り (今のモデルでは起きない)
        for (int t = 0; t < T; t++) {
            float s = B ? B[o] : 0.0f;
            for (int i = 0; i < in; i++) s += X[size_t(t) * in + i] * WT[size_t(i) * ldw + o];
            Y[size_t(t) * ldy + o] = s;
        }
}

#if KKC_X86
// この CPU で AVX2 と FMA が使えるか (OS がレジスタの保存に対応しているかも見る)
bool cpu_has_avx2() {
#if defined(_MSC_VER) && !defined(__clang__)
    int r[4];
    __cpuid(r, 0);
    if (r[0] < 7) return false;
    __cpuid(r, 1);
    const bool fma = (r[2] >> 12) & 1, osxsave = (r[2] >> 27) & 1, avx = (r[2] >> 28) & 1;
    if (!fma || !osxsave || !avx || (_xgetbv(0) & 6) != 6) return false;
    __cpuidex(r, 7, 0);
    return (r[1] >> 5) & 1;
#else
    __builtin_cpu_init();
    return __builtin_cpu_supports("avx2") && __builtin_cpu_supports("fma");
#endif
}
#endif

// 環境変数 KKC_NO_SIMD=1 で、速い版を使わない (比べるため)
bool use_avx2() {
#if KKC_X86
    static const bool on = cpu_has_avx2() && !getenv("KKC_NO_SIMD");
    return on;
#else
    return false;
#endif
}

void lin_any(const float* X, int T, int in, const float* WT, int ldw, const float* B, float* Y, int ldy, int o0, int o1) {
#if KKC_X86
    if (use_avx2()) {
        const int o16 = o0 + (o1 - o0) / 16 * 16;
        kkc_avx2_lin(X, T, in, WT, ldw, B, Y, ldy, o0, o16);
        if (o16 < o1) lin_part(X, T, in, WT, ldw, B, Y, ldy, o16, o1);   // 16 で割り切れない残り
        return;
    }
#endif
    lin_part(X, T, in, WT, ldw, B, Y, ldy, o0, o1);
}

void gelu_all(float* v, size_t n) {
#if KKC_X86
    if (use_avx2()) { kkc_avx2_gelu(v, n); return; }
#endif
    for (size_t i = 0; i < n; i++) v[i] = gelu(v[i]);
}

// 整数に丸めた全結合の重み (engine_simd.h の詰め方)。読み込むときに float の重みから作る
struct QW {
    int in = 0, inp = 0, out = 0;
    std::vector<short> w;     // 出力 16 本 × 入力 2 つずつの組
    std::vector<float> s;     // 出力ごとの倍率 (元の重み = 整数 × 倍率)
};

#if KKC_X86
#ifndef KKC_QW
#define KKC_QW 511    // engine_simd.h と同じ
#endif
// WT (入力, 出力) を出力ごとに ±KKC_QW に丸めて詰める
QW quantize(const float* WT, int in, int out) {
    QW q;
    q.in = in; q.inp = (in + 1) & ~1; q.out = out;
    q.s.assign(size_t(out), 1.0f);
    for (int o = 0; o < out; o++) {
        float m = 0;
        for (int i = 0; i < in; i++) m = std::max(m, std::fabs(WT[size_t(i) * out + o]));
        if (m > 0) q.s[o] = m / KKC_QW;
    }
    q.w.assign(size_t(out / 16) * q.inp * 16, 0);
    for (int o = 0; o < out; o++) {
        short* tile = q.w.data() + size_t(o / 16) * q.inp * 16;
        const int lane = (o % 16) / 8, j = o % 8;
        for (int i = 0; i < in; i++) {
            const float v = WT[size_t(i) * out + o] / q.s[o];
            tile[size_t(i / 2) * 32 + lane * 16 + j * 2 + (i & 1)] = short(std::lround(v));
        }
    }
    return q;
}
#endif

// 整数版を使うか (AVX2 のときだけ。環境変数 KKC_NO_QUANT=1 で使わない)
bool use_quant() {
#if KKC_X86
    static const bool on = use_avx2() && !getenv("KKC_NO_QUANT");
    return on;
#else
    return false;
#endif
}

// 出力を 16 本単位でスレッドに分ける
void linear(Pool* P, const float* X, int T, int in, const float* WT, int ldw, const float* B, int out, float* Y) {
    const int nth = P ? P->n : 1;
    if (nth <= 1 || out < 64 || T * out < 4096) { lin_any(X, T, in, WT, ldw, B, Y, out, 0, out); return; }
    const int tiles = (out + 15) / 16, per = (tiles + nth - 1) / nth;
    P->run([&](int k) {
        const int a = std::min(out, k * per * 16), b = std::min(out, (k + 1) * per * 16);
        if (a < b) lin_any(X, T, in, WT, ldw, B, Y, out, a, b);
    });
}

// linear と同じ計算を整数で。入力は最初に 1 回だけ丸める (xq・xs は作業場所)
void linear_q(Pool* P, const float* X, int T, const QW& q, const float* B, float* Y, std::vector<short>& xq, std::vector<float>& xs) {
#if KKC_X86
    xq.resize(size_t(T) * q.inp);
    xs.resize(size_t(T));
    kkc_avx2_quant_rows(X, T, q.in, q.inp, xq.data(), xs.data());
    const int out = q.out, nth = P ? P->n : 1;
    if (nth <= 1 || out < 64 || T * out < 4096) { kkc_avx2_lin_q(xq.data(), xs.data(), T, q.inp, q.w.data(), q.s.data(), B, Y, out, 0, out); return; }
    const int tiles = out / 16, per = (tiles + nth - 1) / nth;
    P->run([&](int k) {
        const int a = std::min(out, k * per * 16), b = std::min(out, (k + 1) * per * 16);
        if (a < b) kkc_avx2_lin_q(xq.data(), xs.data(), T, q.inp, q.w.data(), q.s.data(), B, Y, out, a, b);
    });
#else
    (void)P; (void)X; (void)T; (void)q; (void)B; (void)Y; (void)xq; (void)xs;
#endif
}

void layernorm(const float* x, int T, int d, const float* w, const float* b, float* y) {
    for (int t = 0; t < T; t++) {
        const float* v = x + size_t(t) * d;
        float m = 0, s = 0;
        for (int i = 0; i < d; i++) m += v[i];
        m /= d;
        for (int i = 0; i < d; i++) { float z = v[i] - m; s += z * z; }
        const float r = 1.0f / std::sqrt(s / d + 1e-5f);
        float* o = y + size_t(t) * d;
        for (int i = 0; i < d; i++) o[i] = (v[i] - m) * r * w[i] + b[i];
    }
}

}  // namespace

struct kkc_engine {
    Lex lex;
    Model m;
    std::vector<uint8_t> own_lex, own_model;   // kkc_open_files のときだけ中身を持つ
    Pool pool;
    double times[5] = {0, 0, 0, 0, 0};
    // 語の k は文脈に依らないので、打鍵をまたいで取っておく (表記+種別 -> K の行)。多くなったら捨てる
    std::unordered_map<ustr, int> kcache;
    std::vector<float> K;
    std::vector<float> last_u;
    std::vector<SegInfo> last_segs;   // 直前の変換の 1 位の語の区切り
    std::vector<UserWord> user;                   // ユーザー辞書の語 (kkc_user_add_like で足す)
    // 整数に丸めた重み (層ごとに inw, outw, l1w, l2w)。空なら float のまま
    std::vector<QW> qw;
    // 作業用
    std::vector<float> x, xn, qkv, att, tmp, ffb, h, xs;
    std::vector<short> xq;
};

namespace {

bool load_lex(Lex& L, const void* data, size_t size) {
    Reader r{static_cast<const uint8_t*>(data), static_cast<const uint8_t*>(data) + size};
    if (size < 4 || memcmp(data, "KKL2", 4)) return false;
    r.off = 4;
    int32_t ver = r.val<int32_t>();
    if (ver != 1) return false;
    L.noun = r.val<int32_t>(); L.num_arabic = r.val<int32_t>(); L.num_kanji = r.val<int32_t>(); L.max_word = r.val<int32_t>();
    L.oov = r.val<int32_t>(); L.kata = r.val<int32_t>(); L.kata_per = r.val<int32_t>(); L.pass = r.val<int32_t>();
    L.nconn = r.val<int32_t>(); L.conn16 = r.val<int32_t>(); L.nread = r.val<int32_t>(); L.nent = r.val<int32_t>();
    int64_t nr16 = r.val<int64_t>(), ns16 = r.val<int64_t>();
    size_t nc = size_t(L.nconn) * L.nconn;
    if (L.conn16) L.c16 = r.arr<int16_t>(nc); else L.c32 = r.arr<int32_t>(nc);
    L.r_off = r.arr<uint32_t>(L.nread + 1);
    L.e_first = r.arr<uint32_t>(L.nread + 1);
    L.ents = r.arr<Ent>(L.nent);
    L.r_blob = r.arr<uint16_t>(size_t(nr16));
    L.s_blob = r.arr<uint16_t>(size_t(ns16));
    return r.ok;
}

bool load_model(Model& M, const void* data, size_t size) {
    Reader r{static_cast<const uint8_t*>(data), static_cast<const uint8_t*>(data) + size};
    if (size < 4 || memcmp(data, "KKM1", 4)) return false;
    r.off = 4;
    if (r.val<int32_t>() != 2) return false;   // 版 2: 全結合の重みは (入力, 出力)
    M.V = r.val<int32_t>(); M.d = r.val<int32_t>(); M.layers = r.val<int32_t>(); M.heads = r.val<int32_t>();
    M.ff = r.val<int32_t>(); M.dk = r.val<int32_t>(); M.max_len = r.val<int32_t>(); M.n_seg = r.val<int32_t>();
    M.ctx = r.val<int32_t>(); M.draft_max = r.val<int32_t>(); M.draft = r.val<int32_t>();
    M.beta = r.val<float>(); M.gamma = r.val<float>();
    int nch = r.val<int32_t>();
    for (int i = 0; i < nch; i++) M.vocab[char32_t(r.val<uint32_t>())] = 4 + i;
    const int d = M.d, ff = M.ff, dk = M.dk, V = M.V;
    M.emb = r.arr<float>(size_t(V) * d); M.seg = r.arr<float>(size_t(M.n_seg) * d); M.pos = r.arr<float>(size_t(M.max_len) * d);
    for (int l = 0; l < M.layers; l++) {
        LayerW w;
        w.ln1w = r.arr<float>(d); w.ln1b = r.arr<float>(d);
        w.inw = r.arr<float>(size_t(3) * d * d); w.inb = r.arr<float>(3 * d);
        w.outw = r.arr<float>(size_t(d) * d); w.outb = r.arr<float>(d);
        w.ln2w = r.arr<float>(d); w.ln2b = r.arr<float>(d);
        w.l1w = r.arr<float>(size_t(ff) * d); w.l1b = r.arr<float>(ff);
        w.l2w = r.arr<float>(size_t(d) * ff); w.l2b = r.arr<float>(d);
        M.L.push_back(w);
    }
    M.normw = r.arr<float>(d); M.normb = r.arr<float>(d); M.end = r.arr<float>(d);
    M.q1w = r.arr<float>(size_t(d) * 3 * d); M.q1b = r.arr<float>(d); M.q2w = r.arr<float>(size_t(dk) * d); M.q2b = r.arr<float>(dk);
    M.Pa = r.arr<float>(size_t(V) * d); M.Pb = r.arr<float>(size_t(V) * d); M.Pc = r.arr<float>(size_t(V) * d);
    M.Kkind = r.arr<float>(size_t(5) * d); M.Klen = r.arr<float>(size_t(17) * d);
    M.k1b = r.arr<float>(d); M.k2w = r.arr<float>(size_t(dk) * d); M.k2b = r.arr<float>(dk);
    return r.ok;
}

// エンコーダ。tokens/segs (T) → h (T×d)
void encode(kkc_engine* E, const std::vector<int>& tok, const std::vector<int>& seg) {
    const Model& M = E->m;
    const int T = int(tok.size()), d = M.d, H = M.heads, dh = d / H, ff = M.ff;
    auto& x = E->x; auto& xn = E->xn; auto& qkv = E->qkv; auto& att = E->att; auto& tmp = E->tmp; auto& fb = E->ffb;
    x.assign(size_t(T) * d, 0); xn.resize(size_t(T) * d); qkv.resize(size_t(T) * 3 * d); att.resize(size_t(T) * d);
    tmp.resize(size_t(T) * d); fb.resize(size_t(T) * ff);
    for (int t = 0; t < T; t++) {
        const float *a = M.emb + size_t(tok[t]) * d, *b = M.seg + size_t(seg[t]) * d, *c = M.pos + size_t(t) * d;
        for (int i = 0; i < d; i++) x[size_t(t) * d + i] = a[i] + b[i] + c[i];
    }
    std::vector<float> sc(size_t(T) + 8);   // AVX2 版は 8 本単位で使う
    const float scale = 1.0f / std::sqrt(float(dh));
    for (int li = 0; li < M.layers; li++) {
        const LayerW& w = M.L[size_t(li)];
        layernorm(x.data(), T, d, w.ln1w, w.ln1b, xn.data());
        const QW* q = E->qw.empty() ? nullptr : &E->qw[size_t(li) * 4];
        if (q) linear_q(&E->pool, xn.data(), T, q[0], w.inb, qkv.data(), E->xq, E->xs);
        else linear(&E->pool, xn.data(), T, d, w.inw, 3 * d, w.inb, 3 * d, qkv.data());
#if KKC_X86
        if (use_avx2() && dh % 8 == 0) {
            for (int hh = 0; hh < H; hh++) kkc_avx2_attend(qkv.data(), T, d, dh, hh, scale, sc.data(), att.data());
        } else
#endif
        for (int hh = 0; hh < H; hh++) {
            for (int t = 0; t < T; t++) {
                const float* q = qkv.data() + size_t(t) * 3 * d + hh * dh;
                float mx = -1e30f;
                for (int u = 0; u < T; u++) {
                    const float* k = qkv.data() + size_t(u) * 3 * d + d + hh * dh;
                    float s = 0;
                    for (int i = 0; i < dh; i++) s += q[i] * k[i];
                    sc[u] = s * scale;
                    mx = std::max(mx, sc[u]);
                }
                float z = 0;
                for (int u = 0; u < T; u++) { sc[u] = std::exp(sc[u] - mx); z += sc[u]; }
                float* o = att.data() + size_t(t) * d + hh * dh;
                for (int i = 0; i < dh; i++) o[i] = 0;
                for (int u = 0; u < T; u++) {
                    const float p = sc[u] / z;
                    const float* v = qkv.data() + size_t(u) * 3 * d + 2 * d + hh * dh;
                    for (int i = 0; i < dh; i++) o[i] += p * v[i];
                }
            }
        }
        if (q) linear_q(&E->pool, att.data(), T, q[1], w.outb, tmp.data(), E->xq, E->xs);
        else linear(&E->pool, att.data(), T, d, w.outw, d, w.outb, d, tmp.data());
        for (size_t i = 0; i < x.size(); i++) x[i] += tmp[i];
        layernorm(x.data(), T, d, w.ln2w, w.ln2b, xn.data());
        if (q) linear_q(&E->pool, xn.data(), T, q[2], w.l1b, fb.data(), E->xq, E->xs);
        else linear(&E->pool, xn.data(), T, d, w.l1w, ff, w.l1b, ff, fb.data());
        gelu_all(fb.data(), fb.size());
        if (q) linear_q(&E->pool, fb.data(), T, q[3], w.l2b, tmp.data(), E->xq, E->xs);
        else linear(&E->pool, fb.data(), T, ff, w.l2w, d, w.l2b, d, tmp.data());
        for (size_t i = 0; i < x.size(); i++) x[i] += tmp[i];
    }
    E->h.resize(size_t(T) * d);
    layernorm(x.data(), T, d, M.normw, M.normb, E->h.data());
}

// 辺ごとの u (学習側の forward_u と同じ)
void scores(kkc_engine* E, int rstart, int n, const std::vector<Edge>& ed, std::vector<float>& u) {
    const Model& M = E->m;
    const int d = M.d, dk = M.dk;
    const float* h = E->h.data();
    // 境界 p (0..n) の状態と、読みの各文字の状態
    std::vector<float> Bd(size_t(n + 1) * d), QA(size_t(n + 1) * d), QB(size_t(n + 1) * d), QC(size_t(std::max(n, 1)) * d);
    for (int p = 0; p <= n; p++) {
        const float* left = h + size_t(rstart + p - 1) * d;
        const float* right = p < n ? h + size_t(rstart + p) * d : M.end;
        for (int i = 0; i < d; i++) Bd[size_t(p) * d + i] = (left[i] + right[i]) * 0.5f;
    }
    // q の最初の層 (3d, d) を [境界 s | 境界 e | 区間の平均] の 3 つに分けて、位置ごとに掛けておく
    linear(nullptr, Bd.data(), n + 1, d, M.q1w, d, nullptr, d, QA.data());
    linear(nullptr, Bd.data(), n + 1, d, M.q1w + size_t(d) * d, d, nullptr, d, QB.data());
    linear(nullptr, h + size_t(rstart) * d, n, d, M.q1w + 2 * size_t(d) * d, d, nullptr, d, QC.data());
    std::vector<double> CQ(size_t(n + 1) * d, 0.0);   // QC の累積和
    for (int i = 0; i < n; i++)
        for (int j = 0; j < d; j++) CQ[size_t(i + 1) * d + j] = CQ[size_t(i) * d + j] + QC[size_t(i) * d + j];
    // 区間ごとの q
    std::unordered_map<int, int> span_id;
    std::vector<float> Q;
    std::vector<float> hid(d);
    auto span_q = [&](int s, int e) {
        int key = s * 4096 + e;
        auto it = span_id.find(key);
        if (it != span_id.end()) return it->second;
        const float inv = 1.0f / float(std::max(e - s, 1));
        for (int j = 0; j < d; j++)
            hid[j] = QA[size_t(s) * d + j] + QB[size_t(e) * d + j] + float(CQ[size_t(e) * d + j] - CQ[size_t(s) * d + j]) * inv + M.q1b[j];
        gelu_all(hid.data(), size_t(d));
        int id = int(Q.size() / dk);
        Q.resize(Q.size() + dk);
        linear(nullptr, hid.data(), 1, d, M.q2w, dk, M.q2b, dk, Q.data() + size_t(id) * dk);
        span_id[key] = id;
        return id;
    };
    // 語ごとの k (表記と種別で 1 つ。打鍵をまたいで取っておく)
    auto& word_id = E->kcache;
    auto& K = E->K;
    if (word_id.size() > 30000) { word_id.clear(); K.clear(); }
    auto word_k = [&](const Edge& e) {
        ustr key = e.surf;
        key.push_back(char32_t(0x110000 + e.kind));
        auto it = word_id.find(key);
        if (it != word_id.end()) return it->second;
        const int nc = int(e.surf.size());
        for (int j = 0; j < d; j++) hid[j] = 0;
        for (char32_t c : e.surf) {
            const float* p = M.Pa + size_t(M.vid(c)) * d;
            for (int j = 0; j < d; j++) hid[j] += p[j];
        }
        const float inv = 1.0f / float(std::max(nc, 1));
        const float* pb = M.Pb + size_t(M.vid(e.surf.front())) * d;
        const float* pc = M.Pc + size_t(M.vid(e.surf.back())) * d;
        const float* kk = M.Kkind + size_t(e.kind) * d;
        const float* kl = M.Klen + size_t(std::min(nc, 16)) * d;
        for (int j = 0; j < d; j++) hid[j] = hid[j] * inv + pb[j] + kk[j] + pc[j] + kl[j] + M.k1b[j];
        gelu_all(hid.data(), size_t(d));
        int id = int(K.size() / dk);
        K.resize(K.size() + dk);
        linear(nullptr, hid.data(), 1, d, M.k2w, dk, M.k2b, dk, K.data() + size_t(id) * dk);
        word_id[key] = id;
        return id;
    };
    u.resize(ed.size());
    const float sc = 1.0f / std::sqrt(float(dk));
    for (size_t i = 0; i < ed.size(); i++) {
        const int a = span_q(ed[i].s, ed[i].e), b = word_k(ed[i]);
        const float *q = Q.data() + size_t(a) * dk, *k = K.data() + size_t(b) * dk;
        float s = 0;
        for (int j = 0; j < dk; j++) s += q[j] * k[j];
        u[i] = s * sc;
    }
}

// 上位 k (lattice.nbest / kkcnative の kkc_nbest と同じ)
int nbest(const Lex& L, const std::vector<Edge>& E, int n, const float* u, double beta, double gamma, int k, int maxout,
          std::vector<ustr>& res, std::vector<SegInfo>* segs = nullptr) {
    const int M = int(E.size());
    std::vector<std::vector<int>> by_start(n + 1), by_end(n + 1);
    for (int i = 0; i < M; i++) { by_start[E[i].s].push_back(i); by_end[E[i].e].push_back(i); }
    struct Cand { double c; int j, r; };
    std::vector<std::vector<Cand>> best(M);
    std::vector<char> has(M, 0);
    std::vector<Cand> cands;
    std::vector<int> idx;
    for (int pos = 0; pos < n; pos++) {
        for (int i : by_start[pos]) {
            const Edge& ed = E[i];
            double own = u ? double(float(beta * ed.cost) - 1000.0f * u[i]) : beta * ed.cost;
            cands.clear();
            if (pos == 0) {
                cands.push_back({gamma * L.conn(0, ed.lid) + own, -1, 0});
            } else {
                for (int j : by_end[pos]) {
                    if (!has[j]) continue;
                    double t = gamma * L.conn(E[j].rid, ed.lid) + own;
                    for (int r = 0; r < int(best[j].size()); r++) cands.push_back({best[j][r].c + t, j, r});
                }
                if (cands.empty()) continue;
            }
            // 上位 k だけを選ぶ (全部を並べ替えない)。同点は元の順 = 安定ソートして先頭 k 個と同じ結果
            const int nc = int(cands.size());
            if (nc > k) {
                idx.resize(nc);
                for (int q = 0; q < nc; q++) idx[q] = q;
                std::partial_sort(idx.begin(), idx.begin() + k, idx.end(), [&](int x, int y) {
                    return cands[x].c < cands[y].c || (cands[x].c == cands[y].c && x < y);
                });
                auto& dst = best[i];
                dst.resize(k);
                for (int q = 0; q < k; q++) dst[q] = cands[idx[q]];
            } else {
                std::stable_sort(cands.begin(), cands.end(), [](const Cand& a, const Cand& b) { return a.c < b.c; });
                best[i] = cands;
            }
            has[i] = 1;
        }
    }
    std::vector<Cand> fin;
    for (int j : by_end[n])
        for (int r = 0; r < int(best[j].size()); r++) fin.push_back({best[j][r].c + gamma * L.conn(E[j].rid, 0), j, r});
    std::stable_sort(fin.begin(), fin.end(), [](const Cand& a, const Cand& b) { return a.c < b.c; });
    std::unordered_set<ustr> seen;
    std::vector<int> path;
    res.clear();
    for (auto& f : fin) {
        path.clear();
        int j = f.j, r = f.r;
        while (j >= 0) { path.push_back(j); const Cand& c = best[j][r]; j = c.j; r = c.r; }
        ustr surf;
        for (auto it = path.rbegin(); it != path.rend(); ++it) surf += E[*it].surf;
        if (!seen.insert(surf).second) continue;
        if (res.empty() && segs) {   // 1 位の語の区切り: (読みの終わりの位置, 表記の長さ UTF-16)
            segs->clear();
            for (auto it = path.rbegin(); it != path.rend(); ++it) {
                int l16 = 0;
                for (char32_t c : E[*it].surf) l16 += c >= 0x10000 ? 2 : 1;
                segs->push_back({E[*it].e, l16, E[*it].lid, E[*it].rid});
            }
        }
        res.push_back(surf);
        if (int(res.size()) >= maxout) break;
    }
    return int(res.size());
}

double ms_since(std::chrono::steady_clock::time_point t) {
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t).count();
}

}  // namespace

KKC_API kkc_engine* kkc_open(const void* lex, size_t lex_size, const void* model, size_t model_size) {
    init_numbers();
    auto* e = new kkc_engine();
    if (!load_lex(e->lex, lex, lex_size) || !load_model(e->m, model, model_size)) { delete e; return nullptr; }
#if KKC_X86
    // 整数版の重み (16 出力単位・入力の数が 2048 以下のときだけ。合計が 32 ビットに収まる範囲)
    const Model& M = e->m;
    if (use_quant() && M.d % 16 == 0 && M.ff % 16 == 0 && M.ff <= 2048 && M.d <= 2048) {
        for (const LayerW& w : M.L) {
            e->qw.push_back(quantize(w.inw, M.d, 3 * M.d));
            e->qw.push_back(quantize(w.outw, M.d, M.d));
            e->qw.push_back(quantize(w.l1w, M.d, M.ff));
            e->qw.push_back(quantize(w.l2w, M.ff, M.d));
        }
    }
#endif
    return e;
}

KKC_API kkc_engine* kkc_open_files(const char* lex_path, const char* model_path) {
    auto rd = [](const char* p, std::vector<uint8_t>& buf) {
        FILE* f = fopen(p, "rb");
        if (!f) return false;
        fseek(f, 0, SEEK_END);
        long n = ftell(f);
        fseek(f, 0, SEEK_SET);
        buf.resize(size_t(n));
        bool ok = fread(buf.data(), 1, size_t(n), f) == size_t(n);
        fclose(f);
        return ok;
    };
    std::vector<uint8_t> a, b;
    if (!rd(lex_path, a) || !rd(model_path, b)) return nullptr;
    kkc_engine* e = kkc_open(a.data(), a.size(), b.data(), b.size());
    if (!e) return nullptr;
    // 中身のポインタは a, b を指しているので、エンジンに持たせる (vector の移動ではバッファの位置は変わらない)
    e->own_lex = std::move(a);
    e->own_model = std::move(b);
    return e;
}

KKC_API void kkc_close(kkc_engine* e) { delete e; }
KKC_API void kkc_set_threads(kkc_engine* e, int n) { if (e) e->pool.resize(n); }

KKC_API int kkc_convert(kkc_engine* e, const uint16_t* ctx, int nctx, const uint16_t* kana, int nk,
                        int maxout, int use_model, uint16_t* out, int cap) {
    if (!e) return -2;
    const Model& M = e->m;
    auto t0 = std::chrono::steady_clock::now();
    ustr r = from16(kana, size_t(nk));
    const int n = int(r.size());
    std::vector<Edge> E = edges(e->lex, r, &e->user);
    e->times[0] = ms_since(t0);
    std::vector<ustr> res;
    e->last_u.clear();
    e->last_segs.clear();
    if (!use_model || n == 0) {
        for (int i = 1; i < 5; i++) e->times[i] = 0;
        t0 = std::chrono::steady_clock::now();
        nbest(e->lex, E, n, nullptr, 1.0, 1.0, 10, maxout, res, &e->last_segs);
        e->times[4] = ms_since(t0);
    } else {
        // 入力: [文脈] SEP [読み] (SEP [下書き])
        t0 = std::chrono::steady_clock::now();
        ustr c = from16(ctx, size_t(nctx));
        if (int(c.size()) > M.ctx) c = c.substr(c.size() - M.ctx);
        std::vector<int> tok, seg;
        for (char32_t ch : c) { tok.push_back(M.vid(ch)); seg.push_back(0); }
        tok.push_back(SEP); seg.push_back(0);
        const int rstart = int(tok.size());
        for (char32_t ch : r) { tok.push_back(M.vid(ch)); seg.push_back(1); }
        if (M.draft) {
            ustr dr = best_path(e->lex, E, n);
            int room = M.max_len - int(tok.size()) - 1;
            int lim = std::min(M.draft_max, std::max(room, 0));
            if (int(dr.size()) > lim) dr.resize(size_t(lim));
            if (room > 0) {
                tok.push_back(SEP); seg.push_back(2);
                for (char32_t ch : dr) { tok.push_back(M.vid(ch)); seg.push_back(2); }
            }
        }
        if (int(tok.size()) > M.max_len) return -3;   // 読みが長すぎる
        e->times[1] = ms_since(t0);
        t0 = std::chrono::steady_clock::now();
        encode(e, tok, seg);
        e->times[2] = ms_since(t0);
        t0 = std::chrono::steady_clock::now();
        scores(e, rstart, n, E, e->last_u);
        e->times[3] = ms_since(t0);
        t0 = std::chrono::steady_clock::now();
        nbest(e->lex, E, n, e->last_u.data(), M.beta, M.gamma, 10, maxout, res, &e->last_segs);
        e->times[4] = ms_since(t0);
    }
    std::vector<uint16_t> buf;
    for (auto& s : res) { to16(s, buf); buf.push_back(0); }
    if (int(buf.size()) > cap) return -1;
    std::copy(buf.begin(), buf.end(), out);
    return int(res.size());
}

KKC_API void kkc_last_times(kkc_engine* e, double* t5) { for (int i = 0; i < 5; i++) t5[i] = e ? e->times[i] : 0; }

KKC_API int kkc_last_scores(kkc_engine* e, float* u, int cap) {
    if (!e) return -2;
    int n = int(e->last_u.size());
    if (n > cap) return -1;
    std::copy(e->last_u.begin(), e->last_u.end(), u);
    return n;
}

KKC_API int kkc_last_segments(kkc_engine* e, int32_t* ends, int32_t* lens, int cap) {
    if (!e) return -2;
    int n = int(e->last_segs.size());
    if (n > cap) return -1;
    for (int i = 0; i < n; i++) { ends[i] = e->last_segs[i].e; lens[i] = e->last_segs[i].l16; }
    return n;
}

KKC_API int kkc_last_segment_pos(kkc_engine* e, int32_t* lids, int32_t* rids, int cap) {
    if (!e) return -2;
    int n = int(e->last_segs.size());
    if (n > cap) return -1;
    for (int i = 0; i < n; i++) { lids[i] = e->last_segs[i].lid; rids[i] = e->last_segs[i].rid; }
    return n;
}

KKC_API void kkc_user_clear(kkc_engine* e) {
    if (e) e->user.clear();
}

KKC_API int kkc_user_add_like(kkc_engine* e, const uint16_t* r, int nr, const uint16_t* s, int ns, const uint16_t* tr, int ntr,
                              const uint16_t* ts, int nts, int bonus) {
    if (!e || nr <= 0 || ns <= 0) return 0;
    uint32_t a, b;
    if (!e->lex.find(tr, ntr, a, b)) return 0;
    const ustr want = from16(ts, size_t(nts));
    const Ent* best = nullptr;
    for (uint32_t j = a; j < b; j++) {
        const Ent& en = e->lex.ents[j];
        if (from16(e->lex.s_blob + en.soff, en.slen) == want && (!best || en.cost < best->cost)) best = &en;
    }
    if (!best) return 0;
    e->user.push_back({from16(r, size_t(nr)), from16(s, size_t(ns)), best->lid, best->rid, best->cost - bonus});
    return 1;
}

#ifndef KKC_FRAG
#define KKC_FRAG 4500   // 「ね」へのつながりのコストがこれより高い語は、言い切れない形として予測に出さない
#endif

KKC_API int kkc_complete(kkc_engine* e, const uint16_t* prefix, int np, int max_extra, int maxout, uint16_t* out, int cap) {
    if (!e || np <= 0) return 0;
    const Lex& L = e->lex;
    // 読みは辞書の中で並んでいるので、prefix で始まる読みの範囲の先頭を二分探索で探す
    int lo = 0, hi = L.nread;
    while (lo < hi) {
        int mid = (lo + hi) >> 1;
        const uint16_t* r = L.r_blob + L.r_off[mid];
        int rn = int(L.r_off[mid + 1] - L.r_off[mid]);
        int m = std::min(rn, np), c = 0;
        for (int i = 0; i < m && !c; i++) c = int(r[i]) - int(prefix[i]);
        if (!c) c = rn - np;
        if (c < 0) lo = mid + 1; else hi = mid;
    }
    // 終助詞「ね」の左 ID (読み ね・表記 ね の語のうちコストのいちばん低いもの)
    int ne_lid = 0;
    {
        const uint16_t ne = 0x306D;
        uint32_t a, b;
        int32_t best = INT32_MAX;
        if (L.find(&ne, 1, a, b))
            for (uint32_t j = a; j < b; j++)
                if (L.ents[j].slen == 1 && L.s_blob[L.ents[j].soff] == ne && L.ents[j].cost < best) best = L.ents[j].cost, ne_lid = L.ents[j].lid;
    }
    struct C { int32_t cost; uint32_t ent; };
    std::vector<C> found;
    for (int i = lo, scanned = 0; i < L.nread && scanned < 50000; i++, scanned++) {
        const uint16_t* r = L.r_blob + L.r_off[i];
        int rn = int(L.r_off[i + 1] - L.r_off[i]);
        if (rn < np || memcmp(r, prefix, size_t(np) * 2)) break;          // prefix で始まる読みが尽きた
        if (rn == np || rn > np + max_extra) continue;                      // 打った読みそのもの・長すぎる読みは除く
        // 順位は語のコスト (よく使う語ほど低い)。ただし後ろに終助詞「ね」が付きにくい語 (よろしけれ・いただい など
        // 活用の途中の形) は、言い切れないので除く
        for (uint32_t j = L.e_first[i]; j < L.e_first[i + 1]; j++)
            if (L.conn(L.ents[j].rid, ne_lid) <= KKC_FRAG) found.push_back({L.ents[j].cost, j});
    }
    std::sort(found.begin(), found.end(), [](const C& a, const C& b) { return a.cost < b.cost; });
    std::vector<uint16_t> buf;
    std::unordered_set<ustr> seen;
    int n = 0;
    for (const C& c : found) {
        if (n >= maxout) break;
        const Ent& en = L.ents[c.ent];
        ustr sf = from16(L.s_blob + en.soff, en.slen);
        // 言い切れない形を表記の終わりで除く (ありゃ・すみゃ・ありがたかっ・よろしけれ・よろしかろ)
        const char32_t last = sf.back();
        if (last == U'ゃ' || last == U'ゅ' || last == U'ょ' || last == U'っ') continue;
        if (sf.size() >= 2 && (sf.compare(sf.size() - 2, 2, U"けれ") == 0 || sf.compare(sf.size() - 2, 2, U"かろ") == 0)) continue;
        if (!seen.insert(sf).second) continue;
        to16(sf, buf);
        buf.push_back(0);
        n++;
    }
    if (int(buf.size()) > cap) return -1;
    std::copy(buf.begin(), buf.end(), out);
    return n;
}
