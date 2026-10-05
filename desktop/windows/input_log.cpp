// 入力の記録の書き出し (デバッグ用のビルドだけ。説明は input_log.h)
#include "input_log.h"

#ifdef SHUNTI_INPUT_LOG

#include <windows.h>

#include <chrono>

#include "../core/json.h"
#include "globals.h"

namespace shunti {
namespace win {

namespace {
std::string join(const std::vector<u16>& v, const char* sep, size_t max) {
    std::string o;
    for (size_t i = 0; i < v.size() && i < max; i++) {
        if (i) o += sep;
        std::string s = to_utf8(v[i]);
        for (char& c : s) if (c == sep[0]) c = ' ';   // 区切りの字は候補の中から消す
        o += s;
    }
    return o;
}

// 打っているアプリ (exe の名前)。IME はアプリの中に読み込まれて動くので、自分のプロセスの名前がそのアプリ。
// チャットと文書で口調が違うのを後で分けられるように、全部の行に付ける ("a")
const std::string& app_name() {
    static const std::string name = [] {
        wchar_t buf[MAX_PATH] = {};
        GetModuleFileNameW(nullptr, buf, MAX_PATH);
        const wchar_t* base = wcsrchr(buf, L'\\');
        std::wstring w = base ? base + 1 : buf;
        return to_utf8(u16(w.begin(), w.end()));
    }();
    return name;
}

void append(const std::string& line, const wchar_t* file = L"debug_input_log.jsonl") {
    // 変換の計測 (shuntllim の ime_bench.exe) が打ち込む問題は、本人の入力ではないので書かない
    if (app_name() == "ime_bench.exe") return;
    std::wstring path = (user_dir() / file).wstring();
    CreateDirectoryW(user_dir().wstring().c_str(), nullptr);
    // 別のアプリのプロセスからも同じファイルに足すので、足すたびに開いて閉じる (1 行ずつなので混ざらない)
    HANDLE f = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD w;
    WriteFile(f, line.data(), DWORD(line.size()), &w, nullptr);
    CloseHandle(f);
}

long long now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string tail_fields() { return ",\"a\":" + json::quote(app_name()) + ",\"v\":\"win\"}\n"; }

// ---- ミスの記録 (debug_mistakes.jsonl)。上の記録は全部の入力 (学習の教材) で大きく、変換の弱点を探すたびに
// 正解した入力まで読むことになる。ミスらしいものだけを別のファイルに小さく書く:
//   pick   = 1 位以外の候補を選んで確定した (r 読み・top 1 位・s 選んだもの・b 左の文脈)
//   bseg   = 文節を選び直した (r・top・s)
//   cancel = 変換を取り消してかなに戻した (r・s = 出ていた変換)
//   redo   = 確定 (自動確定・かなのまま確定も) の 5 秒以内に 2 字以上消し、1 分以内に打ち直して確定した
//            (r0・s0 = 元の確定、del = 消した字数、r・s = 打ち直した確定)。確定してから間違いに気づいたもの
struct LastCommit {
    long long t = 0;
    std::string r, s, kind;
    int del = 0;
};
LastCommit g_last;   // IME はアプリごとのプロセスに読み込まれるので、アプリごとに持つ

std::string short_ctx(const u16& c) { return to_utf8(c.size() > 20 ? c.substr(c.size() - 20) : c); }

void mistake(const std::string& body) {
    append("{\"t\":" + std::to_string(now_ms()) + "," + body + tail_fields(), L"debug_mistakes.jsonl");
}

void watch_mistakes(const LogEvent& e) {
    const std::string kind = e.kind;
    const std::string r = to_utf8(e.reading), s = to_utf8(e.surface);
    const std::string top = e.cands.empty() ? "" : to_utf8(e.cands[0]);
    if (kind == "commit" || kind == "auto" || kind == "raw") {
        const long long now = now_ms();
        if (kind == "commit" && e.index > 0)
            mistake("\"k\":\"pick\",\"r\":" + json::quote(r) + ",\"top\":" + json::quote(top) + ",\"s\":" + json::quote(s) +
                    ",\"b\":" + json::quote(short_ctx(e.ctx)));
        if (g_last.t && g_last.del >= 2 && now - g_last.t <= 60000)
            mistake("\"k\":\"redo\",\"r0\":" + json::quote(g_last.r) + ",\"s0\":" + json::quote(g_last.s) + ",\"k0\":" +
                    json::quote(g_last.kind) + ",\"del\":" + std::to_string(g_last.del) + ",\"r\":" + json::quote(r) +
                    ",\"s\":" + json::quote(s));
        g_last = {now, r, s, kind, 0};
    } else if (kind == "bseg" && e.index > 0) {
        mistake("\"k\":\"bseg\",\"r\":" + json::quote(r) + ",\"top\":" + json::quote(top) + ",\"s\":" + json::quote(s));
    } else if (kind == "cancel") {
        mistake("\"k\":\"cancel\",\"r\":" + json::quote(r) + ",\"s\":" + json::quote(s));
    }
}
}  // namespace

void input_log(const LogEvent& e) {
    std::string o = "{\"t\":" + std::to_string(now_ms()) + ",\"k\":" + json::quote(e.kind) +
                    ",\"r\":" + json::quote(to_utf8(e.reading)) + ",\"s\":" + json::quote(to_utf8(e.surface)) +
                    ",\"i\":" + std::to_string(e.index) + ",\"n\":" + std::to_string(e.cands.size()) +
                    ",\"x\":" + json::quote(e.extra);
    if (!e.cands.empty()) o += ",\"c\":" + json::quote(join(e.cands, ",", 10));
    if (!e.ctx.empty()) o += ",\"b\":" + json::quote(to_utf8(e.ctx));
    if (!e.segs.empty()) o += ",\"g\":" + json::quote(join(e.segs, "|", 64));
    append(o + tail_fields());
    watch_mistakes(e);
}

void input_log_simple(const char* kind, const std::string& extra) {
    // 確定の 5 秒以内に消し始めたら、打ち直し (redo) の候補として消した字数を数える。入力欄が変わったら忘れる
    if (std::string(kind) == "delchar" && g_last.t && (g_last.del > 0 || now_ms() - g_last.t <= 5000)) g_last.del++;
    if (std::string(kind) == "field") g_last = {};
    append("{\"t\":" + std::to_string(now_ms()) + ",\"k\":" + json::quote(kind) + ",\"r\":\"\",\"s\":\"\",\"i\":-1,\"n\":0,\"x\":" +
           json::quote(extra) + tail_fields());
}

void input_log_key(const std::string& key, const u16& shown) {
    append("{\"t\":" + std::to_string(now_ms()) + ",\"k\":\"key\",\"r\":" + json::quote(to_utf8(shown)) +
           ",\"s\":\"\",\"i\":-1,\"n\":0,\"x\":" + json::quote(key) + tail_fields());
}

}  // namespace win
}  // namespace shunti

#endif
