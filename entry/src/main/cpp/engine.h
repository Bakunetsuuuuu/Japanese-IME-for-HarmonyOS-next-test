// 端末で動くかな漢字変換エンジン (網 + 採点器 + 上位 k)。外部ライブラリなしの C++17。
// shuntelligence の推論エンジン。学習側 (非公開) と同じ計算をし、候補の並びが学習側と一致することを確かめてある。
// Android では JNI、HarmonyOS では NAPI (napi_kkc.cpp) から呼ぶ。
#pragma once
#include <cstddef>
#include <cstdint>

#ifdef _WIN32
#define KKC_API extern "C" __declspec(dllexport)
#else
#define KKC_API extern "C" __attribute__((visibility("default")))
#endif

struct kkc_engine;

// 辞書 (shuntorge, kkc_lex.bin) とモデル (shuntelligence, kkc_model.bin) の中身。呼び出し側が mmap したものをそのまま渡す (エンジンは複製しない)。
KKC_API kkc_engine* kkc_open(const void* lex, size_t lex_size, const void* model, size_t model_size);
// PC 用: ファイルを読み込んで開く
KKC_API kkc_engine* kkc_open_files(const char* lex_path, const char* model_path);
KKC_API void kkc_close(kkc_engine* e);
KKC_API void kkc_set_threads(kkc_engine* e, int n);

// 変換。ctx = 左の文脈 (確定済みの文)、kana = 読み (UTF-16)。上位 maxout 個の表記を 0 区切りの UTF-16 で out に書く。
// 返り値は候補の数 (out が足りなければ -1)。use_model = 0 なら辞書のコストだけ (採点器を通さない)。
KKC_API int kkc_convert(kkc_engine* e, const uint16_t* ctx, int nctx, const uint16_t* kana, int nk,
                        int maxout, int use_model, uint16_t* out, int cap);

// 直前の kkc_convert の時間の内訳 (ミリ秒): [網, 下書き, エンコーダ, 区間と語, 上位 k]
KKC_API void kkc_last_times(kkc_engine* e, double* t5);

// 検証用: 直前の kkc_convert の網の辺ごとの点数 u (辺の順は学習側と同じ)。返り値は辺の数
KKC_API int kkc_last_scores(kkc_engine* e, float* u, int cap);

// 直前の kkc_convert の 1 位の候補の語の区切り。ends[i] = i 語目の読みの終わりの位置 (読みの UTF-16 の字数)、
// lens[i] = i 語目の表記の長さ (UTF-16)。返り値は語の数。長い入力で「前の方を固定して後ろだけ変換する」ために使う
KKC_API int kkc_last_segments(kkc_engine* e, int32_t* ends, int32_t* lens, int cap);

// 直前の kkc_convert の 1 位の候補の語ごとの品詞の左右 ID (辞書の ID。辞書に無い語は名詞の ID)。返り値は語の数。
// PC 版が文節 (自立語 + 付属語) の区切りを決めるのに使う
KKC_API int kkc_last_segment_pos(kkc_engine* e, int32_t* lids, int32_t* rids, int cap);

// ユーザー辞書。登録した語を辞書の語と同じく網に入れ、モデルが文脈で採点する (読みが文の途中に出てきても候補になる)。
// 品詞の左右 ID とコストは、辞書にある「同じ品詞・同じ活用の形の代表語」(読み tr・表記 ts) から写す
// (例: 登録語 ぐぐら/ググら の代表に はしら/走ら)。コストは代表語より bonus だけ下げる (選ばれやすくする)。
// 代表語が辞書に無ければ足さずに 0 を返す。kkc_convert と同じスレッドで呼ぶ
KKC_API void kkc_user_clear(kkc_engine* e);
KKC_API int kkc_user_add_like(kkc_engine* e, const uint16_t* r, int nr, const uint16_t* s, int ns, const uint16_t* tr, int ntr,
                              const uint16_t* ts, int nts, int bonus);

// 予測: 読みが prefix で始まり、prefix より長い (長くても max_extra 字まで) 辞書の語の表記を、コストの低い (よく使う) 順に
// 最大 maxout 個、0 区切りの UTF-16 で out に書く (こん → こんにちは・こんばんは・今度…)。返り値は数 (out が足りなければ -1)。
// 辞書を読むだけなので、変換中の別のスレッドから呼んでもよい
KKC_API int kkc_complete(kkc_engine* e, const uint16_t* prefix, int np, int max_extra, int maxout, uint16_t* out, int cap);
