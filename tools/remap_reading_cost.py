#!/usr/bin/env python3
"""
Remap reading_cost.json from the old 15-class system to the Phase-2.5 100-class system.

Old class IDs (15-class):
    0  unknown/other        → 98 UNKNOWN
    1  名詞-一般             → 0  N_GENERAL
    2  名詞-固有名詞          → 6  N_PROPER_O
    3  動詞                  → 14 V5_BASE  (approximation)
    4  形容詞/形容動詞        → 34 ADJ_BASE (approximation)
    5  副詞                  → 42 ADV_DEGREE
    6  助詞                  → per-reading lookup (fine-grained)
    7  助動詞                → per-reading lookup (fine-grained)
    8  接続詞                → 87 CONJ_CAUSE
    9  感動詞                → 90 INTJ
    10 記号                  → 92 SYMBOL_G
    11 名詞-数               → 7  N_NUMBER
    12 接尾詞                → 97 SUFFIX_G
    13 接頭詞                → 95 PREFIX_N

Usage:
    python3 tools/remap_reading_cost.py [reading_cost.json] [out_reading_cost.json]
"""

import json
import os
import sys

# ── Phase-2.5 class IDs ────────────────────────────────────────────────────
N_GENERAL, N_SAHEN, N_KEIYODOSHI, N_PRONOUN           = 0, 1, 2, 3
N_PROPER_P, N_PROPER_L, N_PROPER_O                    = 4, 5, 6
N_NUMBER, N_COUNTER, N_NONSELF                         = 7, 8, 9
N_ADVERBNOUN                                           = 10
V5_BASE, V5_RENYOU                                     = 14, 15
V1_BASE                                                = 22
VSURU_BASE                                             = 28
VKURU_BASE                                             = 32
ADJ_BASE, ADJ_KU                                       = 34, 35
KADJ_STEM                                              = 39
ADV_DEGREE                                             = 42
P_GA, P_WO, P_NI, P_DE, P_TO, P_NO                   = 48, 49, 50, 51, 52, 53
P_HE, P_YORI, P_KARA, P_MADE                          = 54, 55, 56, 57
P_WA, P_MO, P_FOCUS, P_HODO, P_YA                    = 58, 59, 60, 61, 62
P_TE, P_BA, P_NODE, P_NONI, P_NAGARA, P_TEMO         = 63, 64, 65, 66, 67, 68
P_KA, P_NE, P_YO, P_ZO                               = 69, 70, 71, 72
AUX_TA, AUX_TEIRU, AUX_NAI, AUX_NAKU                 = 73, 74, 75, 76
AUX_MASU, AUX_MASEN, AUX_MASHITA                     = 77, 78, 79
AUX_DESU, AUX_DA, AUX_DARO                           = 80, 81, 82
AUX_SERU, AUX_RERU, AUX_TAI, AUX_SOUDA               = 83, 84, 85, 86
CONJ_CAUSE, CONJ_CONTRAST, CONJ_ADD                   = 87, 88, 89
INTJ, FILLER                                          = 90, 91
SYMBOL_G, SYMBOL_P, NUM_ARABIC                        = 92, 93, 94
PREFIX_N, PREFIX_V, SUFFIX_G                          = 95, 96, 97
UNKNOWN, BOS_EOS                                      = 98, 99

# ── Bulk remap (old class → new class) ────────────────────────────────────
BULK_REMAP = {
    0:  UNKNOWN,      # unknown
    1:  N_GENERAL,    # 名詞-一般
    2:  N_PROPER_O,   # 固有名詞 (lump all proper nouns)
    3:  V5_BASE,      # 動詞 (approximate as V5_BASE — best single class for dict forms)
    4:  ADJ_BASE,     # 形容詞/形容動詞
    5:  ADV_DEGREE,   # 副詞
    # 6 → fine-grained (see PARTICLE_REMAP below)
    # 7 → fine-grained (see AUXILIARY_REMAP below)
    8:  CONJ_CAUSE,   # 接続詞
    9:  INTJ,         # 感動詞
    10: SYMBOL_G,     # 記号
    11: N_NUMBER,     # 名詞-数
    12: SUFFIX_G,     # 接尾詞
    13: PREFIX_N,     # 接頭詞
}

# ── Particle readings → fine-grained class ────────────────────────────────
PARTICLE_REMAP = {
    # Case particles
    'が': P_GA, 'を': P_WO, 'に': P_NI, 'で': P_DE,
    'と': P_TO, 'の': P_NO, 'へ': P_HE, 'より': P_YORI,
    'から': P_KARA, 'まで': P_MADE,
    # Topic / focus / extent
    'は': P_WA, 'も': P_MO,
    'こそ': P_FOCUS, 'だけ': P_FOCUS, 'しか': P_FOCUS,
    'さえ': P_FOCUS, 'のみ': P_FOCUS,
    'ほど': P_HODO, 'くらい': P_HODO, 'ぐらい': P_HODO,
    'ばかり': P_HODO, 'など': P_HODO,
    'や': P_YA, 'とか': P_YA,
    # Conjunctive
    'て': P_TE, 'ば': P_BA, 'ので': P_NODE, 'のに': P_NONI,
    'ながら': P_NAGARA, 'ても': P_TEMO, 'でも': P_TEMO,
    'たり': P_TEMO, 'し': P_TEMO,  # し as listing particle
    # Sentence-final
    'か': P_KA, 'かな': P_KA, 'かね': P_KA,
    'ね': P_NE, 'な': P_NE, 'ねえ': P_NE,
    'よ': P_YO, 'よね': P_YO,
    'ぞ': P_ZO, 'ぜ': P_ZO, 'わ': P_ZO,
}

# ── Auxiliary readings → fine-grained class ───────────────────────────────
AUXILIARY_REMAP = {
    # Past / perfect
    'た': AUX_TA, 'だった': AUX_TA, 'てた': AUX_TA,
    # Progressive / resultant
    'ている': AUX_TEIRU, 'ていた': AUX_TEIRU, 'てある': AUX_TEIRU,
    'ておく': AUX_TEIRU, 'ていく': AUX_TEIRU, 'てくる': AUX_TEIRU,
    'てしまう': AUX_TEIRU, 'てみる': AUX_TEIRU,
    # Negative
    'ない': AUX_NAI, 'ん': AUX_NAI, 'ぬ': AUX_NAI,
    'なく': AUX_NAKU, 'なかった': AUX_NAKU, 'なくて': AUX_NAKU,
    # Polite
    'ます': AUX_MASU,
    'ません': AUX_MASEN, 'ませんでした': AUX_MASEN,
    'ました': AUX_MASHITA,
    # Copula
    'です': AUX_DESU, 'でございます': AUX_DESU,
    'だ': AUX_DA, 'じゃ': AUX_DA,
    'でした': AUX_TA,  # polite past same class as past
    # Conjecture
    'だろう': AUX_DARO, 'だろ': AUX_DARO, 'でしょう': AUX_DARO,
    # Causative
    'せる': AUX_SERU, 'させる': AUX_SERU, 'す': AUX_SERU,
    # Passive / potential / honorific
    'れる': AUX_RERU, 'られる': AUX_RERU,
    # Desiderative
    'たい': AUX_TAI, 'たく': AUX_TAI, 'たかった': AUX_TAI,
    # Evidential / appearance
    'そうだ': AUX_SOUDA, 'らしい': AUX_SOUDA, 'みたい': AUX_SOUDA,
    'そうです': AUX_SOUDA, 'ようだ': AUX_SOUDA,
}


def remap_class(old_class: int, reading: str) -> int:
    if old_class == 6:
        return PARTICLE_REMAP.get(reading, P_WA)  # default to P_WA for unknown particles
    if old_class == 7:
        return AUXILIARY_REMAP.get(reading, AUX_TA)  # default to AUX_TA for unknown aux
    return BULK_REMAP.get(old_class, UNKNOWN)


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir)
    rawfile_dir = os.path.join(repo_root, 'entry/src/main/resources/rawfile')

    in_path  = sys.argv[1] if len(sys.argv) > 1 else os.path.join(rawfile_dir, 'reading_cost.json')
    out_path = sys.argv[2] if len(sys.argv) > 2 else in_path

    print(f'Reading:  {in_path}')
    with open(in_path, encoding='utf-8') as f:
        old_dict: dict = json.load(f)

    print(f'Entries:  {len(old_dict):,}')

    new_dict: dict = {}
    remapped_particles = 0
    remapped_aux = 0
    bulk_remapped = 0

    for reading, v in old_dict.items():
        if len(v) < 3:
            continue
        cost, old_lc, old_rc = v[0], v[1], v[2]
        new_lc = remap_class(old_lc, reading)
        new_rc = remap_class(old_rc, reading)
        new_dict[reading] = [cost, new_lc, new_rc]
        if old_lc == 6:
            remapped_particles += 1
        elif old_lc == 7:
            remapped_aux += 1
        else:
            bulk_remapped += 1

    print(f'Fine-grained particle remaps: {remapped_particles}')
    print(f'Fine-grained auxiliary remaps: {remapped_aux}')
    print(f'Bulk remaps: {bulk_remapped}')

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(new_dict, f, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    size_kb = os.path.getsize(out_path) / 1024
    print(f'Written:  {out_path}  ({size_kb:.0f} KB)')

    # Spot-check
    checks = ['は', 'が', 'を', 'に', 'で', 'ない', 'です', 'ます', 'た', 'て',
              'から', 'まで', 'こそ', 'たい', 'れる']
    print('\nSpot-check:')
    for k in checks:
        v = new_dict.get(k)
        print(f'  {k}: {v}')


if __name__ == '__main__':
    main()
