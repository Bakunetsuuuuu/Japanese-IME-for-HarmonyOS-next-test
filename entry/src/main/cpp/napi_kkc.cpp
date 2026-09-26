// HarmonyOS (ArkTS) から変換エンジン (kkc/engine/engine.cpp) を呼ぶ NAPI の窓口。モジュール名 libkkc.so。
//
//   import kkc from 'libkkc.so';
//   kkc.prepare(context.resourceManager, context.filesDir)   // 初回だけ: rawfile の kkc_lex.bin / kkc_model.bin を filesDir へ写す
//   kkc.open(context.filesDir, 4)                             // 辞書とモデルを mmap して開く (スレッド数)
//   kkc.convert('左の文脈', 'よみ', 10)                        // 候補の配列
//
// IME の拡張はメモリの上限が厳しいので、辞書とモデル (合わせて 100MB 超) を JS に読み込まない。
// 写すのも C++ で少しずつ、開いた後は mmap (必要なページだけが読まれ、他のアプリと同じく OS が管理する)。
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "napi/native_api.h"
#include "rawfile/raw_file.h"
#include "rawfile/raw_file_manager.h"

#include "engine.h"

namespace {

struct Mapped {
    const void* p = nullptr;
    size_t n = 0;
};

const char* LEX = "kkc_lex.bin";     // rawfile の名前 (Mozc の資産と区別する)
const char* MODEL = "kkc_model.bin";
kkc_engine* g_engine = nullptr;
std::mutex g_mu;   // エンジンは同時に 2 つの変換をできないので、呼び出しを 1 つずつにする
Mapped g_lex, g_model;

std::string str_arg(napi_env env, napi_value v) {
    size_t n = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &n);
    std::string s(n, '\0');
    napi_get_value_string_utf8(env, v, s.data(), n + 1, &n);
    return s;
}

std::u16string u16_arg(napi_env env, napi_value v) {
    size_t n = 0;
    napi_get_value_string_utf16(env, v, nullptr, 0, &n);
    std::u16string s(n, u'\0');
    napi_get_value_string_utf16(env, v, s.data(), n + 1, &n);
    return s;
}

napi_value boolean(napi_env env, bool b) {
    napi_value r;
    napi_get_boolean(env, b, &r);
    return r;
}

bool map_file(const std::string& path, Mapped& m) {
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) return false;
    struct stat st;
    if (fstat(fd, &st) != 0) { close(fd); return false; }
    void* p = mmap(nullptr, size_t(st.st_size), PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (p == MAP_FAILED) return false;
    m.p = p;
    m.n = size_t(st.st_size);
    return true;
}

void unmap(Mapped& m) {
    if (m.p) munmap(const_cast<void*>(m.p), m.n);
    m = Mapped();
}

// rawfile を dir/name に写す (同じ大きさのファイルが既にあれば何もしない)
bool copy_raw(NativeResourceManager* mgr, const std::string& dir, const char* name) {
    RawFile* rf = OH_ResourceManager_OpenRawFile(mgr, name);
    if (!rf) return false;
    long size = OH_ResourceManager_GetRawFileSize(rf);
    std::string path = dir + "/" + name;
    struct stat st;
    if (stat(path.c_str(), &st) == 0 && st.st_size == size) {
        // 大きさが同じでも中身が違うことがある (同じ形のモデルの差し替え)。先頭 1MB を比べる
        const size_t n = size_t(std::min<long>(size, 1L << 20));
        std::vector<char> a(n), b(n);
        int got = OH_ResourceManager_ReadRawFile(rf, a.data(), n);
        int fd0 = open(path.c_str(), O_RDONLY);
        bool same = false;
        if (fd0 >= 0) {
            same = got == int(n) && read(fd0, b.data(), n) == ssize_t(n) && memcmp(a.data(), b.data(), n) == 0;
            close(fd0);
        }
        if (same) {
            OH_ResourceManager_CloseRawFile(rf);
            return true;
        }
        OH_ResourceManager_SeekRawFile(rf, 0, SEEK_SET);
    }
    std::string tmp = path + ".tmp";
    int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    bool ok = fd >= 0;
    std::vector<char> buf(1 << 20);
    long left = size;
    while (ok && left > 0) {
        int n = OH_ResourceManager_ReadRawFile(rf, buf.data(), size_t(std::min<long>(left, long(buf.size()))));
        if (n <= 0 || write(fd, buf.data(), size_t(n)) != n) ok = false;
        left -= n;
    }
    if (fd >= 0) close(fd);
    OH_ResourceManager_CloseRawFile(rf);
    if (ok) ok = rename(tmp.c_str(), path.c_str()) == 0;   // 途中で落ちても壊れたファイルを残さない
    else unlink(tmp.c_str());
    return ok;
}

napi_value Prepare(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 2) return boolean(env, false);
    NativeResourceManager* mgr = OH_ResourceManager_InitNativeResourceManager(env, argv[0]);
    std::string dir = str_arg(env, argv[1]);
    bool ok = mgr && copy_raw(mgr, dir, LEX) && copy_raw(mgr, dir, MODEL);
    if (mgr) OH_ResourceManager_ReleaseNativeResourceManager(mgr);
    return boolean(env, ok);
}

struct LoadJob {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    NativeResourceManager* mgr = nullptr;
    std::string dir;
    int32_t threads = 4;
    bool ok = false;
};

// prepare + open を裏のスレッドで。Promise<boolean>
napi_value LoadAsync(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    auto* job = new LoadJob();
    if (argc >= 2) {
        job->mgr = OH_ResourceManager_InitNativeResourceManager(env, argv[0]);
        job->dir = str_arg(env, argv[1]);
    }
    if (argc >= 3) napi_get_value_int32(env, argv[2], &job->threads);
    napi_value promise, name;
    napi_create_promise(env, &job->deferred, &promise);
    napi_create_string_utf8(env, "kkcLoad", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(
        env, nullptr, name,
        [](napi_env, void* data) {
            auto* j = static_cast<LoadJob*>(data);
            if (!j->mgr || !copy_raw(j->mgr, j->dir, LEX) || !copy_raw(j->mgr, j->dir, MODEL)) return;
            std::lock_guard<std::mutex> lk(g_mu);
            if (g_engine) { kkc_close(g_engine); g_engine = nullptr; }
            unmap(g_lex);
            unmap(g_model);
            if (!map_file(j->dir + "/" + LEX, g_lex) || !map_file(j->dir + "/" + MODEL, g_model)) return;
            g_engine = kkc_open(g_lex.p, g_lex.n, g_model.p, g_model.n);
            if (g_engine) kkc_set_threads(g_engine, j->threads);
            j->ok = g_engine != nullptr;
        },
        [](napi_env env, napi_status, void* data) {
            auto* j = static_cast<LoadJob*>(data);
            if (j->mgr) OH_ResourceManager_ReleaseNativeResourceManager(j->mgr);
            napi_resolve_deferred(env, j->deferred, boolean(env, j->ok));
            napi_delete_async_work(env, j->work);
            delete j;
        },
        job, &job->work);
    napi_queue_async_work(env, job->work);
    return promise;
}

napi_value Open(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) return boolean(env, false);
    std::string dir = str_arg(env, argv[0]);
    int32_t threads = 4;
    if (argc >= 2) napi_get_value_int32(env, argv[1], &threads);
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_engine) { kkc_close(g_engine); g_engine = nullptr; }
    unmap(g_lex);
    unmap(g_model);
    if (!map_file(dir + "/" + LEX, g_lex) || !map_file(dir + "/" + MODEL, g_model)) return boolean(env, false);
    g_engine = kkc_open(g_lex.p, g_lex.n, g_model.p, g_model.n);
    if (g_engine) kkc_set_threads(g_engine, threads);
    return boolean(env, g_engine != nullptr);
}

napi_value Convert(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value arr;
    napi_create_array(env, &arr);
    if (!g_engine || argc < 2) return arr;
    std::u16string ctx = u16_arg(env, argv[0]), kana = u16_arg(env, argv[1]);
    int32_t maxout = 10;
    if (argc >= 3) napi_get_value_int32(env, argv[2], &maxout);
    std::vector<uint16_t> out(1 << 15);
    std::lock_guard<std::mutex> lk(g_mu);
    int r = kkc_convert(g_engine, reinterpret_cast<const uint16_t*>(ctx.data()), int(ctx.size()),
                        reinterpret_cast<const uint16_t*>(kana.data()), int(kana.size()), maxout, 1, out.data(), int(out.size()));
    size_t st = 0;
    for (int i = 0; i < r; i++) {
        size_t e = st;
        while (out[e]) e++;
        napi_value s;
        napi_create_string_utf16(env, reinterpret_cast<const char16_t*>(out.data() + st), e - st, &s);
        napi_set_element(env, arr, uint32_t(i), s);
        st = e + 1;
    }
    return arr;
}

// 裏のスレッドで変換して Promise で返す (UI のスレッドを止めない)。古い打鍵の結果は呼ぶ側で捨てる
struct Job {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::u16string ctx, kana;
    int32_t maxout = 10;
    std::vector<std::u16string> res;
    std::vector<int32_t> ends, lens;   // 1 位の候補の語の区切り
    std::chrono::steady_clock::time_point queued, started, done;   // 待ち時間の切り分け用
};

napi_value ConvertAsync(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    auto* job = new Job();
    if (argc >= 2) { job->ctx = u16_arg(env, argv[0]); job->kana = u16_arg(env, argv[1]); }
    if (argc >= 3) napi_get_value_int32(env, argv[2], &job->maxout);
    napi_value promise, name;
    napi_create_promise(env, &job->deferred, &promise);
    job->queued = std::chrono::steady_clock::now();
    napi_create_string_utf8(env, "kkcConvert", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(
        env, nullptr, name,
        [](napi_env, void* data) {
            auto* j = static_cast<Job*>(data);
            j->started = std::chrono::steady_clock::now();
            std::lock_guard<std::mutex> lk(g_mu);
            j->done = j->started;
            if (!g_engine || j->kana.empty()) return;
            std::vector<uint16_t> out(1 << 15);
            int r = kkc_convert(g_engine, reinterpret_cast<const uint16_t*>(j->ctx.data()), int(j->ctx.size()),
                                reinterpret_cast<const uint16_t*>(j->kana.data()), int(j->kana.size()), j->maxout, 1,
                                out.data(), int(out.size()));
            size_t st = 0;
            for (int i = 0; i < r; i++) {
                size_t e = st;
                while (out[e]) e++;
                j->res.emplace_back(reinterpret_cast<const char16_t*>(out.data() + st), e - st);
                st = e + 1;
            }
            j->ends.resize(512);
            j->lens.resize(512);
            int m = kkc_last_segments(g_engine, j->ends.data(), j->lens.data(), 512);
            j->ends.resize(m > 0 ? m : 0);
            j->lens.resize(m > 0 ? m : 0);
            j->done = std::chrono::steady_clock::now();
        },
        [](napi_env env, napi_status, void* data) {
            auto* j = static_cast<Job*>(data);
            napi_value arr, obj, ends, lens;
            napi_create_array(env, &arr);
            for (uint32_t i = 0; i < j->res.size(); i++) {
                napi_value s;
                napi_create_string_utf16(env, j->res[i].data(), j->res[i].size(), &s);
                napi_set_element(env, arr, i, s);
            }
            napi_create_array(env, &ends);
            napi_create_array(env, &lens);
            for (uint32_t i = 0; i < j->ends.size(); i++) {
                napi_value a, b;
                napi_create_int32(env, j->ends[i], &a);
                napi_create_int32(env, j->lens[i], &b);
                napi_set_element(env, ends, i, a);
                napi_set_element(env, lens, i, b);
            }
            napi_create_object(env, &obj);
            napi_set_named_property(env, obj, "cands", arr);
            napi_set_named_property(env, obj, "ends", ends);
            napi_set_named_property(env, obj, "lens", lens);
            // 待ち時間の内訳 (ms): 裏のスレッドの順番待ち / 変換 / 変換が終わってから JS に届くまで
            auto ms = [](std::chrono::steady_clock::time_point a, std::chrono::steady_clock::time_point b) {
                return std::chrono::duration<double, std::milli>(b - a).count();
            };
            napi_value w1, w2, w3;
            auto now = std::chrono::steady_clock::now();
            napi_create_double(env, ms(j->queued, j->started), &w1);
            napi_create_double(env, ms(j->started, j->done), &w2);
            napi_create_double(env, ms(j->done, now), &w3);
            napi_set_named_property(env, obj, "waitMs", w1);
            napi_set_named_property(env, obj, "runMs", w2);
            napi_set_named_property(env, obj, "deliverMs", w3);
            napi_resolve_deferred(env, j->deferred, obj);
            napi_delete_async_work(env, j->work);
            delete j;
        },
        job, &job->work);
    napi_queue_async_work(env, job->work);
    return promise;
}

// 直前の変換の時間の内訳 (ミリ秒): [網, 下書き, エンコーダ, 区間と語, 上位k]
napi_value Times(napi_env env, napi_callback_info) {
    napi_value arr;
    napi_create_array(env, &arr);
    double t[5] = {0, 0, 0, 0, 0};
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_engine) kkc_last_times(g_engine, t);
    for (uint32_t i = 0; i < 5; i++) {
        napi_value v;
        napi_create_double(env, t[i], &v);
        napi_set_element(env, arr, i, v);
    }
    return arr;
}

napi_value Close(napi_env env, napi_callback_info) {
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_engine) kkc_close(g_engine);
    g_engine = nullptr;
    unmap(g_lex);
    unmap(g_model);
    return boolean(env, true);
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"prepare", nullptr, Prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"open", nullptr, Open, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadAsync", nullptr, LoadAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"convert", nullptr, Convert, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"convertAsync", nullptr, ConvertAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"times", nullptr, Times, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"close", nullptr, Close, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

napi_module kkc_module = {1, 0, nullptr, Init, "kkc", nullptr, {0}};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterKkcModule() { napi_module_register(&kkc_module); }
