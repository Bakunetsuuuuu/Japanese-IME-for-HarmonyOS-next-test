// MSVC (Windows) 用: engine_simd.h の AVX2 版の計算を /arch:AVX2 でビルドして、engine.cpp から呼べるようにする。
// GCC / Clang (Linux・Android・HarmonyOS) ではこのファイルは要らない (engine.cpp が engine_simd.h を直接読む)。
//   cl /c /O2 /arch:AVX2 engine_avx2.cpp
#if defined(_MSC_VER) && !defined(__clang__) && (defined(_M_X64) || defined(_M_IX86))
#include "engine_simd.h"

extern "C" void kkc_avx2_lin(const float* X, int T, int in, const float* WT, int ldw, const float* B, float* Y, int ldy, int o0, int o1) {
    kkc_simd_lin(X, T, in, WT, ldw, B, Y, ldy, o0, o1);
}
extern "C" void kkc_avx2_gelu(float* v, size_t n) { kkc_simd_gelu(v, n); }
extern "C" void kkc_avx2_attend(const float* qkv, int T, int d, int dh, int hh, float scale, float* sc, float* att) {
    kkc_simd_attend(qkv, T, d, dh, hh, scale, sc, att);
}
#endif
