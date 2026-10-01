// x86 (PC) の AVX2 + FMA 版の計算。engine.cpp が、CPU が AVX2 と FMA を持っているときだけ使う。
// GCC / Clang では engine.cpp がこのまま読む (関数ごとに target("avx2,fma") を付けるので、ほかの部分は古い命令のまま)。
// MSVC では engine_avx2.cpp (/arch:AVX2 でビルド) だけが読む。そのとき、ここで標準ライブラリの関数やテンプレートを使うと、
// AVX2 で作られた同じ名前の関数がほかのファイルの呼び出しにも使われて古い CPU で落ちることがあるので、
// ここでは組み込み命令 (intrinsics) だけを使い、関数はすべて static にする。
// どれも engine.cpp の普通の版と同じ計算 (足す順と FMA の丸めの違いで最後の桁が違うことはある)。
#pragma once
#include <immintrin.h>
#include <stddef.h>

#ifndef KKC_AVX2_FN
#define KKC_AVX2_FN
#endif

// e^x を 8 本ずつ (Cephes の expf と同じ式。誤差は float の丸めと同じくらい)
static KKC_AVX2_FN inline __m256 kkc_exp8(__m256 x) {
    x = _mm256_min_ps(_mm256_max_ps(x, _mm256_set1_ps(-87.3f)), _mm256_set1_ps(88.3f));
    const __m256 fx = _mm256_floor_ps(_mm256_fmadd_ps(x, _mm256_set1_ps(1.44269504088896341f), _mm256_set1_ps(0.5f)));
    x = _mm256_fnmadd_ps(fx, _mm256_set1_ps(0.693359375f), x);
    x = _mm256_fnmadd_ps(fx, _mm256_set1_ps(-2.12194440e-4f), x);
    __m256 y = _mm256_set1_ps(1.9875691500e-4f);
    y = _mm256_fmadd_ps(y, x, _mm256_set1_ps(1.3981999507e-3f));
    y = _mm256_fmadd_ps(y, x, _mm256_set1_ps(8.3334519073e-3f));
    y = _mm256_fmadd_ps(y, x, _mm256_set1_ps(4.1665795894e-2f));
    y = _mm256_fmadd_ps(y, x, _mm256_set1_ps(1.6666665459e-1f));
    y = _mm256_fmadd_ps(y, x, _mm256_set1_ps(5.0000001201e-1f));
    y = _mm256_fmadd_ps(y, _mm256_mul_ps(x, x), _mm256_add_ps(x, _mm256_set1_ps(1.0f)));
    const __m256i e = _mm256_slli_epi32(_mm256_add_epi32(_mm256_cvtps_epi32(fx), _mm256_set1_epi32(127)), 23);
    return _mm256_mul_ps(y, _mm256_castsi256_ps(e));
}

static KKC_AVX2_FN inline float kkc_hsum8(__m256 a) {
    __m128 s = _mm_add_ps(_mm256_castps256_ps128(a), _mm256_extractf128_ps(a, 1));
    s = _mm_add_ps(s, _mm_movehl_ps(s, s));
    s = _mm_add_ss(s, _mm_shuffle_ps(s, s, 1));
    return _mm_cvtss_f32(s);
}

// lin_part と同じ: Y[t][o] = Σ_i X[t][i] · WT[i][o] + B[o]。出力は [o0, o0 + 16·k) の 16 本単位の所だけ (残りは呼ぶ側)。
// 行は 6 本ずつ (積み上げ 12 本 + 重み 2 本 + 入力 1 本 = 16 本のレジスタに収まる)。行が 1 本のとき (区間・語ごとの小さい掛け算) は
// 入力を 2 つずつ進めて、積み上げを 2 組にする (足し算の待ちを減らす)
static KKC_AVX2_FN void kkc_simd_lin(const float* X, int T, int in, const float* WT, int ldw, const float* B, float* Y, int ldy,
                                     int o0, int o1) {
    for (int o = o0; o + 16 <= o1; o += 16) {
        const __m256 b0 = B ? _mm256_loadu_ps(B + o) : _mm256_setzero_ps();
        const __m256 b1 = B ? _mm256_loadu_ps(B + o + 8) : _mm256_setzero_ps();
        if (T == 1) {
            __m256 a0 = b0, a1 = b1, c0 = _mm256_setzero_ps(), c1 = _mm256_setzero_ps();
            int i = 0;
            for (; i + 2 <= in; i += 2) {
                const float* w = WT + (size_t)i * ldw + o;
                const __m256 v = _mm256_broadcast_ss(X + i), u = _mm256_broadcast_ss(X + i + 1);
                a0 = _mm256_fmadd_ps(v, _mm256_loadu_ps(w), a0);
                a1 = _mm256_fmadd_ps(v, _mm256_loadu_ps(w + 8), a1);
                c0 = _mm256_fmadd_ps(u, _mm256_loadu_ps(w + ldw), c0);
                c1 = _mm256_fmadd_ps(u, _mm256_loadu_ps(w + ldw + 8), c1);
            }
            for (; i < in; i++) {
                const float* w = WT + (size_t)i * ldw + o;
                const __m256 v = _mm256_broadcast_ss(X + i);
                a0 = _mm256_fmadd_ps(v, _mm256_loadu_ps(w), a0);
                a1 = _mm256_fmadd_ps(v, _mm256_loadu_ps(w + 8), a1);
            }
            _mm256_storeu_ps(Y + o, _mm256_add_ps(a0, c0));
            _mm256_storeu_ps(Y + o + 8, _mm256_add_ps(a1, c1));
            continue;
        }
        for (int t = 0; t < T; t += 6) {
            const int tn = T - t < 6 ? T - t : 6;
            const float* x[6];
            for (int r = 0; r < 6; r++) x[r] = X + (size_t)(t + (r < tn ? r : tn - 1)) * in;
            __m256 a00 = b0, a01 = b1, a10 = b0, a11 = b1, a20 = b0, a21 = b1;
            __m256 a30 = b0, a31 = b1, a40 = b0, a41 = b1, a50 = b0, a51 = b1;
            for (int i = 0; i < in; i++) {
                const float* w = WT + (size_t)i * ldw + o;
                const __m256 w0 = _mm256_loadu_ps(w), w1 = _mm256_loadu_ps(w + 8);
                __m256 v = _mm256_broadcast_ss(x[0] + i); a00 = _mm256_fmadd_ps(v, w0, a00); a01 = _mm256_fmadd_ps(v, w1, a01);
                v = _mm256_broadcast_ss(x[1] + i); a10 = _mm256_fmadd_ps(v, w0, a10); a11 = _mm256_fmadd_ps(v, w1, a11);
                v = _mm256_broadcast_ss(x[2] + i); a20 = _mm256_fmadd_ps(v, w0, a20); a21 = _mm256_fmadd_ps(v, w1, a21);
                v = _mm256_broadcast_ss(x[3] + i); a30 = _mm256_fmadd_ps(v, w0, a30); a31 = _mm256_fmadd_ps(v, w1, a31);
                v = _mm256_broadcast_ss(x[4] + i); a40 = _mm256_fmadd_ps(v, w0, a40); a41 = _mm256_fmadd_ps(v, w1, a41);
                v = _mm256_broadcast_ss(x[5] + i); a50 = _mm256_fmadd_ps(v, w0, a50); a51 = _mm256_fmadd_ps(v, w1, a51);
            }
            float* y = Y + (size_t)t * ldy + o;
            const __m256 acc[12] = {a00, a01, a10, a11, a20, a21, a30, a31, a40, a41, a50, a51};
            for (int r = 0; r < tn; r++) {
                _mm256_storeu_ps(y + (size_t)r * ldy, acc[2 * r]);
                _mm256_storeu_ps(y + (size_t)r * ldy + 8, acc[2 * r + 1]);
            }
        }
    }
}

// gelu(x) = x/2 · (1 + erf(x/√2)) を 8 本ずつ。erf は Abramowitz & Stegun 7.1.26 (誤差 1.5e-7、float の丸めと同じくらい)
static KKC_AVX2_FN inline __m256 kkc_gelu8(__m256 x) {
    const __m256 sign = _mm256_set1_ps(-0.0f), one = _mm256_set1_ps(1.0f);
    const __m256 z = _mm256_mul_ps(x, _mm256_set1_ps(0.70710678118654752f));
    const __m256 a = _mm256_andnot_ps(sign, z);
    const __m256 t = _mm256_div_ps(one, _mm256_fmadd_ps(a, _mm256_set1_ps(0.3275911f), one));
    __m256 p = _mm256_set1_ps(1.061405429f);
    p = _mm256_fmadd_ps(p, t, _mm256_set1_ps(-1.453152027f));
    p = _mm256_fmadd_ps(p, t, _mm256_set1_ps(1.421413741f));
    p = _mm256_fmadd_ps(p, t, _mm256_set1_ps(-0.284496736f));
    p = _mm256_fmadd_ps(p, t, _mm256_set1_ps(0.254829592f));
    p = _mm256_mul_ps(p, t);
    const __m256 ea = _mm256_fnmadd_ps(p, kkc_exp8(_mm256_sub_ps(_mm256_setzero_ps(), _mm256_mul_ps(a, a))), one);   // erf(|z|)
    const __m256 erf = _mm256_or_ps(ea, _mm256_and_ps(z, sign));
    return _mm256_mul_ps(_mm256_mul_ps(_mm256_set1_ps(0.5f), x), _mm256_add_ps(one, erf));
}

static KKC_AVX2_FN void kkc_simd_gelu(float* v, size_t n) {
    size_t i = 0;
    for (; i + 8 <= n; i += 8) _mm256_storeu_ps(v + i, kkc_gelu8(_mm256_loadu_ps(v + i)));
    if (i < n) {   // 端は 8 本に詰めて同じ式で
        float buf[8] = {0, 0, 0, 0, 0, 0, 0, 0};
        for (size_t j = i; j < n; j++) buf[j - i] = v[j];
        _mm256_storeu_ps(buf, kkc_gelu8(_mm256_loadu_ps(buf)));
        for (size_t j = i; j < n; j++) v[j] = buf[j - i];
    }
}

// 1 つの頭の自己注意 (engine.cpp の encode の中の計算と同じ。dh は 8 の倍数)。sc は T 本 + 8 本の作業場所
static KKC_AVX2_FN void kkc_simd_attend(const float* qkv, int T, int d, int dh, int hh, float scale, float* sc, float* att) {
    const size_t ld = (size_t)3 * d;
    for (int t = 0; t < T; t++) {
        const float* q = qkv + (size_t)t * ld + hh * dh;
        float mx = -1e30f;
        for (int u = 0; u < T; u++) {
            const float* k = qkv + (size_t)u * ld + d + hh * dh;
            __m256 acc = _mm256_setzero_ps();
            for (int i = 0; i < dh; i += 8) acc = _mm256_fmadd_ps(_mm256_loadu_ps(q + i), _mm256_loadu_ps(k + i), acc);
            const float s = kkc_hsum8(acc) * scale;
            sc[u] = s;
            mx = s > mx ? s : mx;
        }
        // e^(s - 最大) と合計。端の 8 本未満は -1e30 で埋めて同じ式で (e^ が 0 になる)
        for (int u = T; u < ((T + 7) & ~7); u++) sc[u] = -1e30f;
        const __m256 m8 = _mm256_set1_ps(mx);
        __m256 z8 = _mm256_setzero_ps();
        for (int u = 0; u < T; u += 8) {
            const __m256 p = kkc_exp8(_mm256_sub_ps(_mm256_loadu_ps(sc + u), m8));
            _mm256_storeu_ps(sc + u, p);
            z8 = _mm256_add_ps(z8, p);
        }
        const float iz = 1.0f / kkc_hsum8(z8);
        float* o = att + (size_t)t * d + hh * dh;
        for (int i = 0; i < dh; i += 8) _mm256_storeu_ps(o + i, _mm256_setzero_ps());
        for (int u = 0; u < T; u++) {
            const __m256 p = _mm256_set1_ps(sc[u] * iz);
            const float* v = qkv + (size_t)u * ld + 2 * d + hh * dh;
            for (int i = 0; i < dh; i += 8) _mm256_storeu_ps(o + i, _mm256_fmadd_ps(p, _mm256_loadu_ps(v + i), _mm256_loadu_ps(o + i)));
        }
    }
}
