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

void append(const std::string& line) {
    std::wstring path = (user_dir() / L"debug_input_log.jsonl").wstring();
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
}  // namespace

void input_log(const LogEvent& e) {
    std::string o = "{\"t\":" + std::to_string(now_ms()) + ",\"k\":" + json::quote(e.kind) +
                    ",\"r\":" + json::quote(to_utf8(e.reading)) + ",\"s\":" + json::quote(to_utf8(e.surface)) +
                    ",\"i\":" + std::to_string(e.index) + ",\"n\":" + std::to_string(e.cands.size()) +
                    ",\"x\":" + json::quote(e.extra);
    if (!e.cands.empty()) o += ",\"c\":" + json::quote(join(e.cands, ",", 10));
    if (!e.ctx.empty()) o += ",\"b\":" + json::quote(to_utf8(e.ctx));
    if (!e.segs.empty()) o += ",\"g\":" + json::quote(join(e.segs, "|", 64));
    o += ",\"v\":\"win\"}\n";
    append(o);
}

void input_log_simple(const char* kind, const std::string& extra) {
    append("{\"t\":" + std::to_string(now_ms()) + ",\"k\":" + json::quote(kind) + ",\"r\":\"\",\"s\":\"\",\"i\":-1,\"n\":0,\"x\":" +
           json::quote(extra) + ",\"v\":\"win\"}\n");
}

}  // namespace win
}  // namespace shunti

#endif
