#!/usr/bin/env python3
"""
Generate a hand-crafted 100×100 Phase-2.5 POS connection-cost matrix.

Usage:
    python3 tools/gen_matrix_default.py [out_dir]

Output:
    <out_dir>/matrix.json   — number[][] (100×100)

Class IDs (must match KanaKanjiConverter.ets and build_viterbi_dict.py):

  NOUNS (0-13)
    0  N_GENERAL      名詞-一般
    1  N_SAHEN        名詞-サ変接続 (勉強, 運動)
    2  N_KEIYODOSHI   名詞-形容動詞語幹 (静か, 必要)
    3  N_PRONOUN      代名詞 (私, あなた)
    4  N_PROPER_P     固有名詞-人名
    5  N_PROPER_L     固有名詞-地域
    6  N_PROPER_O     固有名詞-組織/一般
    7  N_NUMBER       名詞-数 (一, 二, 三)
    8  N_COUNTER      助数詞 (個, 本, 冊)
    9  N_NONSELF      名詞-非自立 (こと, もの, とき)
   10  N_ADVERBNOUN   名詞-副詞可能 (今, 前, 後)
   11  N_VERBALNOUN   動詞連用名詞化 (読み, 書き)
   12  N_ABBREV       略語/外来語名詞 (アプリ, ファイル)
   13  N_COMPOUND     複合名詞後半

  VERBS (14-33)
   14  V5_BASE        五段-基本形/連体形 (書く, 読む)
   15  V5_RENYOU      五段-連用形 (書き)
   16  V5_RENYOU_ON   五段-連用形音便 (書い)
   17  V5_TE          五段-て形 (書いて)
   18  V5_TA          五段-た形 (書いた)
   19  V5_NAI         五段-未然形 (書か)
   20  V5_COND        五段-仮定形 (書け)
   21  V5_IMP         五段-命令形
   22  V1_BASE        一段-基本形/連体形 (食べる)
   23  V1_RENYOU      一段-連用形 (食べ)
   24  V1_TE          一段-て形 (食べて)
   25  V1_TA          一段-た形 (食べた)
   26  V1_NAI         一段-未然形 (食べ)
   27  V1_COND        一段-仮定形 (食べれ)
   28  VSURU_BASE     サ変-基本形 (する)
   29  VSURU_RENYOU   サ変-連用形 (し)
   30  VSURU_TE       サ変-て形 (して)
   31  VSURU_NAI      サ変-未然形 (さ/せ)
   32  VKURU_BASE     カ変-基本形 (来る)
   33  VKURU_RENYOU   カ変-連用/て (来て)

  ADJECTIVES (34-41)
   34  ADJ_BASE       い形-基本形 (高い)
   35  ADJ_KU         い形-く形 (高く)
   36  ADJ_TE         い形-くて形 (高くて)
   37  ADJ_TA         い形-かった (高かった)
   38  ADJ_NAI_KU     い形-くない (高く+ない)
   39  KADJ_STEM      な形-語幹 (静か, 便利)
   40  KADJ_NA        な形-な接続 (静かな)
   41  KADJ_NI        な形-に接続 (静かに)

  ADVERBS (42-47)
   42  ADV_DEGREE     程度副詞 (とても, 非常に)
   43  ADV_TIME       時間副詞 (もう, まだ)
   44  ADV_FREQ       頻度副詞 (よく, いつも)
   45  ADV_MANNER     様態副詞 (ゆっくり)
   46  ADV_NEGCORR    呼応副詞 (けっして)
   47  ADV_MODAL      様相副詞 (たぶん)

  CASE PARTICLES (48-57)
   48  P_GA           が
   49  P_WO           を
   50  P_NI           に
   51  P_DE           で
   52  P_TO           と
   53  P_NO           の
   54  P_HE           へ
   55  P_YORI         より
   56  P_KARA         から
   57  P_MADE         まで

  TOPIC/FOCUS/EXTENT (58-62)
   58  P_WA           は
   59  P_MO           も
   60  P_FOCUS        こそ, だけ, しか, さえ
   61  P_HODO         ほど, くらい, など, ばかり
   62  P_YA           や, とか

  CONJUNCTIVE PARTICLES (63-68)
   63  P_TE           て (接続助詞)
   64  P_BA           ば
   65  P_NODE         ので
   66  P_NONI         のに
   67  P_NAGARA       ながら
   68  P_TEMO         ても, でも, たり

  SENTENCE-FINAL PARTICLES (69-72)
   69  P_KA           か, かな
   70  P_NE           ね, な (終助詞)
   71  P_YO           よ
   72  P_ZO           ぞ, ぜ, わ

  AUXILIARY VERBS (73-86)
   73  AUX_TA         た (過去)
   74  AUX_TEIRU      ている/てある (アスペクト助動詞)
   75  AUX_NAI        ない (否定)
   76  AUX_NAKU       なく/なかった (否定連用)
   77  AUX_MASU       ます (丁寧現在/未来)
   78  AUX_MASEN      ません (丁寧否定)
   79  AUX_MASHITA    ました (丁寧過去)
   80  AUX_DESU       です (丁寧断定)
   81  AUX_DA         だ (平叙断定)
   82  AUX_DARO       だろう/でしょう (推量)
   83  AUX_SERU       せる/させる (使役)
   84  AUX_RERU       れる/られる (受身/可能/尊敬)
   85  AUX_TAI        たい (希望)
   86  AUX_SOUDA      そうだ/らしい/みたい (様態/伝聞)

  CONJUNCTIONS (87-89)
   87  CONJ_CAUSE     だから, したがって
   88  CONJ_CONTRAST  しかし, でも, ところが
   89  CONJ_ADD       また, そして, さらに

  INTERJECTION/SYMBOL/OTHER (90-97)
   90  INTJ           感動詞 (あ, はい)
   91  FILLER         フィラー (えーと)
   92  SYMBOL_G       記号-一般
   93  SYMBOL_P       記号-句点/読点
   94  NUM_ARABIC     算用数字
   95  PREFIX_N       接頭詞-名詞的
   96  PREFIX_V       接頭詞-動詞的
   97  SUFFIX_G       接尾詞-一般

  SPECIAL (98-99)
   98  UNKNOWN        不明/その他
   99  BOS_EOS        文頭/文末
"""

import json
import os
import sys

# ---------- class IDs ----------
NUM_CLASSES = 100

N_GENERAL, N_SAHEN, N_KEIYODOSHI, N_PRONOUN       = 0, 1, 2, 3
N_PROPER_P, N_PROPER_L, N_PROPER_O                = 4, 5, 6
N_NUMBER, N_COUNTER, N_NONSELF                     = 7, 8, 9
N_ADVERBNOUN, N_VERBALNOUN, N_ABBREV, N_COMPOUND   = 10, 11, 12, 13

V5_BASE, V5_RENYOU, V5_RENYOU_ON                  = 14, 15, 16
V5_TE, V5_TA, V5_NAI, V5_COND, V5_IMP             = 17, 18, 19, 20, 21
V1_BASE, V1_RENYOU, V1_TE, V1_TA, V1_NAI, V1_COND = 22, 23, 24, 25, 26, 27
VSURU_BASE, VSURU_RENYOU, VSURU_TE, VSURU_NAI      = 28, 29, 30, 31
VKURU_BASE, VKURU_RENYOU                           = 32, 33

ADJ_BASE, ADJ_KU, ADJ_TE, ADJ_TA, ADJ_NAI_KU      = 34, 35, 36, 37, 38
KADJ_STEM, KADJ_NA, KADJ_NI                        = 39, 40, 41

ADV_DEGREE, ADV_TIME, ADV_FREQ                     = 42, 43, 44
ADV_MANNER, ADV_NEGCORR, ADV_MODAL                 = 45, 46, 47

P_GA, P_WO, P_NI, P_DE, P_TO, P_NO                = 48, 49, 50, 51, 52, 53
P_HE, P_YORI, P_KARA, P_MADE                      = 54, 55, 56, 57

P_WA, P_MO, P_FOCUS, P_HODO, P_YA                 = 58, 59, 60, 61, 62
P_TE, P_BA, P_NODE, P_NONI, P_NAGARA, P_TEMO      = 63, 64, 65, 66, 67, 68
P_KA, P_NE, P_YO, P_ZO                            = 69, 70, 71, 72

AUX_TA, AUX_TEIRU, AUX_NAI, AUX_NAKU              = 73, 74, 75, 76
AUX_MASU, AUX_MASEN, AUX_MASHITA                  = 77, 78, 79
AUX_DESU, AUX_DA, AUX_DARO                        = 80, 81, 82
AUX_SERU, AUX_RERU, AUX_TAI, AUX_SOUDA            = 83, 84, 85, 86

CONJ_CAUSE, CONJ_CONTRAST, CONJ_ADD                = 87, 88, 89
INTJ, FILLER                                       = 90, 91
SYMBOL_G, SYMBOL_P, NUM_ARABIC                     = 92, 93, 94
PREFIX_N, PREFIX_V, SUFFIX_G                       = 95, 96, 97
UNKNOWN, BOS_EOS                                   = 98, 99

# ---------- class groups ----------
NOUNS       = list(range(0, 14))
ALL_NOUNS   = NOUNS  # alias
VERBS_ALL   = list(range(14, 34))
V_BASE      = [V5_BASE, V1_BASE, VSURU_BASE, VKURU_BASE]
V_RENYOU    = [V5_RENYOU, V5_RENYOU_ON, V1_RENYOU, VSURU_RENYOU, VKURU_RENYOU]
V_TE_FORMS  = [V5_TE, V1_TE, VSURU_TE, VKURU_RENYOU]  # て forms (VKURU_RENYOU=来て)
V_TA_FORMS  = [V5_TA, V1_TA]
V_NAI_STEMS = [V5_NAI, V1_NAI, VSURU_NAI]
V_COND      = [V5_COND, V1_COND]
V_IMP       = [V5_IMP]
ADJ_ALL     = list(range(34, 42))
ADV_ALL     = list(range(42, 48))
CASE_P      = list(range(48, 58))
TOPIC_P     = list(range(58, 63))
CONJ_P      = list(range(63, 69))
FINAL_P     = list(range(69, 73))
ALL_P       = CASE_P + TOPIC_P + CONJ_P + FINAL_P
AUXS        = list(range(73, 87))
CONJS       = list(range(87, 90))
VSURU_ALL   = [VSURU_BASE, VSURU_RENYOU, VSURU_TE, VSURU_NAI]

# ---------- matrix helper ----------
def make_matrix() -> list:
    return [[0] * NUM_CLASSES for _ in range(NUM_CLASSES)]


def fill(m: list, prev_list, cur_list, value: int) -> None:
    for p in prev_list:
        for c in cur_list:
            m[p][c] = value


def add(m: list, prev_list, cur_list, delta: int) -> None:
    for p in prev_list:
        for c in cur_list:
            m[p][c] += delta


def build_matrix() -> list:
    m = make_matrix()

    # ── baseline ──────────────────────────────────────────────────────────────
    # Default 300: slight cost for any unspecified transition.
    # Natural transitions will subtract from this; unnatural ones add to it.
    fill(m, list(range(NUM_CLASSES)), list(range(NUM_CLASSES)), 300)

    # BOS row: starting a sentence costs 0 regardless of what follows
    fill(m, [BOS_EOS], list(range(NUM_CLASSES)), 0)

    # BOS col: a word with BOS class never appears mid-sentence
    fill(m, list(range(NUM_CLASSES)), [BOS_EOS], 3000)
    m[BOS_EOS][BOS_EOS] = 0  # BOS→BOS: before first word

    # UNKNOWN: neutral — no class signal
    fill(m, [UNKNOWN], list(range(NUM_CLASSES)), 300)
    fill(m, list(range(NUM_CLASSES)), [UNKNOWN], 300)

    # ── NOUNS as PREV ─────────────────────────────────────────────────────────

    # N → Case particle: most natural Japanese transition
    fill(m, NOUNS, CASE_P, -2500)
    # N → Topic / focus / extent
    fill(m, NOUNS, TOPIC_P, -2000)
    # N → Copula
    fill(m, NOUNS, [AUX_DA, AUX_DESU], -1800)
    fill(m, NOUNS, [AUX_DARO, AUX_SOUDA], -1000)
    # N → Sentence-final (copula elided: 明日か？など)
    fill(m, NOUNS, FINAL_P, -700)
    # N → Suffix (N-的, N-的に, N-さ etc.)
    fill(m, NOUNS, [SUFFIX_G], -1500)
    # N → Verb base (subject/topic before verb with particle omitted in telegraphic style)
    fill(m, NOUNS, V_BASE, 100)
    # N-SAHEN → する conjugations
    fill(m, [N_SAHEN], VSURU_ALL, -2800)
    # N-KEIYODOSHI → な/に/だ
    fill(m, [N_KEIYODOSHI], [KADJ_NA, KADJ_NI, AUX_DA, AUX_DESU], -2500)
    # N → N (compound nouns): allow but with light cost
    fill(m, NOUNS, NOUNS, 200)
    # N-proper types before themselves: expensive (固有名詞が連続は不自然)
    fill(m, [N_PROPER_P, N_PROPER_L, N_PROPER_O], [N_PROPER_P, N_PROPER_L, N_PROPER_O], 800)
    # N → Conjunctive particles: rare but possible (彼女で + Vmain, etc.)
    fill(m, NOUNS, CONJ_P, 400)
    # N → Adverb: unusual without particle
    fill(m, NOUNS, ADV_ALL, 800)
    # N → Adj: unusual without particle (relative clause ends usually have の)
    fill(m, NOUNS, ADJ_ALL, 500)

    # ── VERBS as PREV ─────────────────────────────────────────────────────────

    # V-RENYOU → ます family: the canonical polite form
    fill(m, V_RENYOU, [AUX_MASU, AUX_MASEN, AUX_MASHITA], -3000)
    # V-RENYOU → た (plain past, for 一段 and some 五段 forms)
    fill(m, V_RENYOU, [AUX_TA], -2500)
    # V-RENYOU → ない (negative: 食べ + ない)
    fill(m, V_RENYOU, [AUX_NAI, AUX_NAKU], -2500)
    # V-RENYOU → たい (desiderative)
    fill(m, V_RENYOU, [AUX_TAI], -2000)
    # V-RENYOU → て (conjunctive: 行き+て unusual, but 来+て valid for VKURU_RENYOU)
    fill(m, V_RENYOU, [P_TE], -1500)
    # V-RENYOU → Nouns (verbal noun use: 読み方 etc.)
    fill(m, V_RENYOU, NOUNS, -500)
    # V-RENYOU → せる/させる/れる/られる
    fill(m, V_RENYOU, [AUX_SERU, AUX_RERU], -1800)

    # V-TE → Auxiliaries (ている, てある, ておく, てしまう etc.)
    fill(m, V_TE_FORMS, AUXS, -1500)
    # V-TE → Verbs (compound verb: 食べて+行く)
    fill(m, V_TE_FORMS, V_BASE + V_RENYOU, -1200)
    # V-TE → Function nouns (てこと, てもの etc.)
    fill(m, V_TE_FORMS, [N_NONSELF], -1200)
    # V-TE → Nouns (nominalization via の: 食べて+の → rare, but て+N happens)
    fill(m, V_TE_FORMS, NOUNS, -300)

    # V-TA → particles, conjunctions
    fill(m, V_TA_FORMS, CASE_P + TOPIC_P, -1200)
    fill(m, V_TA_FORMS, FINAL_P, -1200)
    fill(m, V_TA_FORMS, NOUNS, -800)  # 食べた+こと
    fill(m, V_TA_FORMS, CONJ_P, -500)  # 食べた+のに

    # V-NAI-STEM → ない/なく
    fill(m, V_NAI_STEMS, [AUX_NAI, AUX_NAKU], -3000)
    # V-NAI-STEM → せる/させる (未然+使役)
    fill(m, V_NAI_STEMS, [AUX_SERU], -2500)
    # V-NAI-STEM → れる/られる (未然+受身)
    fill(m, V_NAI_STEMS, [AUX_RERU], -2500)

    # V-COND → ば (仮定形+ば)
    fill(m, V_COND, [P_BA], -3000)

    # V-BASE → の (nominalization)
    fill(m, V_BASE, [P_NO], -1800)
    # V-BASE → case/topic/final particles (relative clause ending)
    fill(m, V_BASE, CASE_P + TOPIC_P, -800)
    fill(m, V_BASE, FINAL_P, -1500)
    # V-BASE → Nouns (relative clause modifying noun: 食べる+人)
    fill(m, V_BASE, NOUNS, -500)
    # V-BASE → AUX_TA (only valid for some cases: base+た not usually)
    fill(m, V_BASE, [AUX_TA], 200)  # slightly unfavorable
    # V-BASE → Conjunctive
    fill(m, V_BASE, CONJ_P, -500)

    # V-IMP: sentence-final (costly to have much after)
    fill(m, V_IMP, list(range(NUM_CLASSES)), 1500)
    fill(m, V_IMP, FINAL_P, -500)  # 命令+よ/ね is OK

    # ── ADJECTIVES as PREV ────────────────────────────────────────────────────

    # ADJ_BASE → Nouns (高い+本: adjectival noun modifier)
    fill(m, [ADJ_BASE], NOUNS, -1800)
    # ADJ_BASE → Copula / polite
    fill(m, [ADJ_BASE], [AUX_DESU, AUX_DA], -1500)
    fill(m, [ADJ_BASE], FINAL_P, -1000)
    # ADJ_BASE → の (高いのに, 高いのは)
    fill(m, [ADJ_BASE], [P_NO], -1200)
    # ADJ_BASE → Conj (高いので, 高いのに)
    fill(m, [ADJ_BASE], CONJ_P, -800)
    # ADJ_BASE → KADJ_NA: unusual (い形+な form? No)
    fill(m, [ADJ_BASE], ADJ_ALL, 600)  # adj→adj unusual

    # ADJ_KU → て (連用くて: 高くて)
    fill(m, [ADJ_KU], [P_TE], -2800)
    # ADJ_KU → ない/なく (高くない)
    fill(m, [ADJ_KU], [AUX_NAI, AUX_NAKU], -2500)
    # ADJ_KU → Verb base (高くなる, 高くする)
    fill(m, [ADJ_KU], V_BASE, -1500)
    # ADJ_KU → AUX_MASU (高くなります via verb, not direct)
    fill(m, [ADJ_KU], [AUX_MASU], 200)

    # ADJ_TE → Nouns / verbs (after くて: 高くて + きれいな...)
    fill(m, [ADJ_TE, ADJ_NAI_KU], NOUNS, -800)
    fill(m, [ADJ_TE, ADJ_NAI_KU], V_BASE, -800)

    # ADJ_TA (かった) → particles
    fill(m, [ADJ_TA], CASE_P + TOPIC_P, -1200)
    fill(m, [ADJ_TA], FINAL_P, -1200)
    fill(m, [ADJ_TA], NOUNS, -1000)  # 高かった+こと
    fill(m, [ADJ_TA], [AUX_DESU], -800)  # 高かったです

    # KADJ_STEM → な/に/だ/です (most common after な形語幹)
    fill(m, [KADJ_STEM], [KADJ_NA], -3000)
    fill(m, [KADJ_STEM], [KADJ_NI], -3000)
    fill(m, [KADJ_STEM], [AUX_DA, AUX_DESU], -2500)
    fill(m, [KADJ_STEM], FINAL_P, -800)
    fill(m, [KADJ_STEM], [AUX_DARO, AUX_SOUDA], -1000)
    # KADJ_STEM → case particle (語幹+は/が unusual without な/に)
    fill(m, [KADJ_STEM], CASE_P + TOPIC_P, 600)

    # KADJ_NA → Nouns (静かな+場所)
    fill(m, [KADJ_NA], NOUNS, -2800)
    # KADJ_NA → の (静かなの)
    fill(m, [KADJ_NA], [P_NO], -1500)

    # KADJ_NI → Verbs (静かに+話す/なる)
    fill(m, [KADJ_NI], V_BASE, -1800)
    fill(m, [KADJ_NI], AUXS, -800)

    # ── ADVERBS as PREV ───────────────────────────────────────────────────────

    # ADV → Verbs / Adj: the main purpose of adverbs
    fill(m, ADV_ALL, V_BASE + VERBS_ALL, -1200)
    fill(m, ADV_ALL, ADJ_ALL, -1200)
    # ADV → ない (negation correlative: まったく+ない)
    fill(m, ADV_ALL, [AUX_NAI, AUX_NAKU], -1500)
    # ADV → ADV (adverb stacking: とても+よく)
    fill(m, ADV_ALL, ADV_ALL, -500)
    # ADV → Nouns: unusual (adverbs don't usually precede nouns)
    fill(m, ADV_ALL, NOUNS, 400)

    # ── CASE PARTICLES as PREV ────────────────────────────────────────────────

    # Case-P → Nouns: natural in SOV structure (が+N, を+N etc.)
    fill(m, CASE_P, NOUNS, -1000)
    # Case-P → Verb forms: natural (を+食べる; broad, then refine V_BASE)
    fill(m, CASE_P, VERBS_ALL, -800)
    fill(m, CASE_P, V_BASE, -1500)   # override: V_BASE cheaper than non-base forms
    # Case-P → Adj (が+大きい: subject + predicate)
    fill(m, CASE_P, ADJ_ALL, -1000)
    # Case-P → ADV (が+よく: subject + adverb + verb)
    fill(m, CASE_P, ADV_ALL, -500)
    # Case-P → Case-P: double particle (unusual)
    fill(m, CASE_P, CASE_P, 1800)
    # Natural particle-topic combinations
    m[P_TO][P_WA] = -1200    # とは (as for... / what is...?)
    m[P_TO][P_MO] = -800     # とも
    m[P_NO][P_GA] = -800     # のが
    m[P_NO][P_WO] = -800     # のを
    m[P_NO][P_NI] = -600     # のに
    m[P_NO][P_DE] = -600     # ので (but のでis CONJ_P, so this is splitting of compound)
    m[P_NO][P_WA] = -800     # のは

    # ── TOPIC/FOCUS PARTICLES as PREV ─────────────────────────────────────────

    fill(m, TOPIC_P, NOUNS, -800)
    fill(m, TOPIC_P, V_BASE, -1200)
    fill(m, TOPIC_P, VERBS_ALL, -800)
    fill(m, TOPIC_P, ADJ_ALL, -1200)
    fill(m, TOPIC_P, ADV_ALL, -600)
    fill(m, TOPIC_P, AUXS, -600)
    fill(m, TOPIC_P, TOPIC_P, 1500)  # double topic: unusual

    # ── CONJUNCTIVE PARTICLES as PREV ─────────────────────────────────────────

    fill(m, CONJ_P, NOUNS, -600)
    fill(m, CONJ_P, V_BASE, -1000)
    fill(m, CONJ_P, VERBS_ALL, -800)
    fill(m, CONJ_P, ADJ_ALL, -800)
    fill(m, CONJ_P, ADV_ALL, -500)
    fill(m, CONJ_P, AUXS, -800)
    # Conjunctive particle followed by another particle: unusual
    fill(m, CONJ_P, ALL_P, 1200)
    # て+V (V-てV chain)
    m[P_TE][V5_BASE] = -1500
    m[P_TE][V1_BASE] = -1500
    m[P_TE][VSURU_BASE] = -1500
    m[P_TE][VKURU_BASE] = -1500
    # ば → V/Adj (仮定+主節)
    fill(m, [P_BA], V_BASE + ADJ_ALL, -1200)
    # のに → V/Adj (逆接主節)
    fill(m, [P_NONI], V_BASE + ADJ_ALL, -1000)

    # ── SENTENCE-FINAL PARTICLES as PREV ──────────────────────────────────────

    # After sentence-final particles, almost nothing natural follows
    fill(m, FINAL_P, list(range(NUM_CLASSES)), 2500)
    # Exception: か+ね (ですかね is natural)
    m[P_KA][P_NE] = -500
    # End of string (BOS_EOS)
    fill(m, FINAL_P, [BOS_EOS], 0)

    # ── AUXILIARIES as PREV ───────────────────────────────────────────────────

    # AUX_TA → particles, nouns, conjunctive
    fill(m, [AUX_TA], CASE_P + TOPIC_P, -1200)
    fill(m, [AUX_TA], FINAL_P, -1200)
    fill(m, [AUX_TA], NOUNS, -800)
    fill(m, [AUX_TA], CONJ_P, -600)
    fill(m, [AUX_TA], [AUX_DESU], -800)  # たです (colloquial?)

    # AUX_TEIRU (ている/てある/...)
    fill(m, [AUX_TEIRU], CASE_P + TOPIC_P, -1200)
    fill(m, [AUX_TEIRU], FINAL_P, -1200)
    fill(m, [AUX_TEIRU], [AUX_MASU, AUX_DA, AUX_DESU], -1500)  # ています
    fill(m, [AUX_TEIRU], NOUNS, -600)

    # AUX_NAI → particles, final
    fill(m, [AUX_NAI], CASE_P + TOPIC_P, -1000)
    fill(m, [AUX_NAI], FINAL_P, -1200)
    fill(m, [AUX_NAI], [AUX_DESU, AUX_DA], -800)  # ないです
    fill(m, [AUX_NAI], CONJ_P, -600)

    # AUX_NAKU → て/V
    fill(m, [AUX_NAKU], [P_TE], -2000)  # なくて
    fill(m, [AUX_NAKU], V_BASE, -1000)  # なくなる

    # AUX_MASU → final-P (ますか, ますね)
    fill(m, [AUX_MASU], FINAL_P, -1500)
    # AUX_MASU → CASE_P (ますが... unusual direct particle follow)
    fill(m, [AUX_MASU], CASE_P, 400)

    # AUX_MASEN (ません)
    fill(m, [AUX_MASEN], FINAL_P, -1200)
    fill(m, [AUX_MASEN], [P_WA], -800)  # ませんは? rare

    # AUX_MASHITA (ました)
    fill(m, [AUX_MASHITA], FINAL_P, -1200)
    fill(m, [AUX_MASHITA], CASE_P + TOPIC_P, -800)

    # AUX_DESU (です)
    fill(m, [AUX_DESU], FINAL_P, -1500)
    fill(m, [AUX_DESU], CASE_P + TOPIC_P, -500)  # ですが (contrast)
    fill(m, [AUX_DESU], CONJS, -800)

    # AUX_DA (だ)
    fill(m, [AUX_DA], FINAL_P, -1200)
    fill(m, [AUX_DA], CASE_P + TOPIC_P, -500)
    fill(m, [AUX_DA], CONJS, -800)
    fill(m, [AUX_DA], [P_TE], -800)  # だ+て=で

    # AUX_DARO (だろう) — usually sentence-final
    fill(m, [AUX_DARO], FINAL_P, -1200)
    fill(m, [AUX_DARO], list(range(NUM_CLASSES)), 1000)  # costly: conjecture is usually final
    fill(m, [AUX_DARO], FINAL_P, -1200)  # reinstate sentence-final cheapness

    # AUX_SERU / AUX_RERU: these are verb-like, can take further suffixes
    fill(m, [AUX_SERU, AUX_RERU], V_RENYOU, -1500)
    fill(m, [AUX_SERU, AUX_RERU], [AUX_MASU, AUX_TA, AUX_NAI], -1500)
    fill(m, [AUX_SERU, AUX_RERU], CASE_P + TOPIC_P + FINAL_P, -1000)

    # AUX_TAI (たい) — often sentence-final or precedes です/ですね
    fill(m, [AUX_TAI], FINAL_P, -1200)
    fill(m, [AUX_TAI], [AUX_DESU, AUX_DA], -1000)
    fill(m, [AUX_TAI], CASE_P + TOPIC_P, -800)

    # AUX_SOUDA (そうだ/らしい/みたい) — usually sentence-final or precedes です
    fill(m, [AUX_SOUDA], FINAL_P, -1200)
    fill(m, [AUX_SOUDA], [AUX_DESU, AUX_DA], -1000)

    # ── CONJUNCTIONS as PREV ──────────────────────────────────────────────────

    # Conjunctions begin new clauses: can precede most content
    fill(m, CONJS, NOUNS + VERBS_ALL + ADJ_ALL + ADV_ALL, -700)
    fill(m, CONJS, ALL_P, 800)  # conj + particle: unusual

    # ── INTERJECTION / FILLER as PREV ─────────────────────────────────────────

    # Interjection/filler: neutral, sentence-start-like
    fill(m, [INTJ, FILLER], list(range(NUM_CLASSES)), 0)

    # ── SYMBOLS / NUMBERS as PREV ─────────────────────────────────────────────

    # Punctuation (SYMBOL_P): similar to BOS — can restart with anything
    fill(m, [SYMBOL_P], list(range(NUM_CLASSES)), 0)

    # SYMBOL_G: default (left as 300 from baseline)

    # NUM_ARABIC → N_COUNTER: very natural (3冊, 5本)
    m[NUM_ARABIC][N_COUNTER] = -2500
    m[NUM_ARABIC][N_NUMBER] = -1500
    # NUM → case particles
    fill(m, [NUM_ARABIC], CASE_P, -1500)
    # NUM → copula
    fill(m, [NUM_ARABIC], [AUX_DA, AUX_DESU], -1200)

    # ── PREFIXES as PREV ──────────────────────────────────────────────────────

    # PREFIX_N → Nouns: very natural (お名前, ご連絡, 超大型)
    fill(m, [PREFIX_N], NOUNS, -2500)
    fill(m, [PREFIX_N], ADJ_ALL, -1500)
    # PREFIX_V → Verbs
    fill(m, [PREFIX_V], V_BASE, -2000)

    # ── SUFFIX as PREV ────────────────────────────────────────────────────────

    # SUFFIX → Case / Topic particles (N-的 + が/は, N-さ + は)
    fill(m, [SUFFIX_G], CASE_P + TOPIC_P, -1800)
    fill(m, [SUFFIX_G], [AUX_DA, AUX_DESU], -1200)
    fill(m, [SUFFIX_G], FINAL_P, -800)
    fill(m, [SUFFIX_G], NOUNS, 200)   # suffix + noun: possible (後輩たち + の)

    # ── global particle-particle penalty (override specific naturals above) ───
    # Double case-particle stacking: bad
    fill(m, CASE_P, CASE_P, 2000)
    # But leave specific natural ones (set earlier with m[p][c] = ...)
    m[P_TO][P_WA] = -1200
    m[P_TO][P_MO] = -800
    m[P_NO][P_GA] = -800
    m[P_NO][P_WO] = -800
    m[P_NO][P_NI] = -600
    m[P_NO][P_WA] = -800

    # ── clamp ─────────────────────────────────────────────────────────────────
    for i in range(NUM_CLASSES):
        for j in range(NUM_CLASSES):
            m[i][j] = max(-4000, min(4000, m[i][j]))

    return m


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir)
    out_dir    = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        repo_root, 'entry/src/main/resources/rawfile')

    print(f'Generating {NUM_CLASSES}×{NUM_CLASSES} Phase-2.5 connection matrix …')
    matrix = build_matrix()

    out_path = os.path.join(out_dir, 'matrix.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(matrix, f, separators=(',', ':'))
    size_kb = os.path.getsize(out_path) / 1024
    print(f'Written: {out_path}  ({size_kb:.1f} KB)')

    # Spot-check a few transitions
    checks = [
        ('N_GENERAL→P_GA',    N_GENERAL, P_GA),
        ('N_GENERAL→P_WA',    N_GENERAL, P_WA),
        ('N_GENERAL→AUX_DESU',N_GENERAL, AUX_DESU),
        ('V5_RENYOU→AUX_MASU',V5_RENYOU, AUX_MASU),
        ('V1_RENYOU→AUX_NAI', V1_RENYOU, AUX_NAI),
        ('V5_NAI→AUX_NAI',    V5_NAI, AUX_NAI),
        ('ADJ_BASE→N_GENERAL', ADJ_BASE, N_GENERAL),
        ('KADJ_STEM→KADJ_NA', KADJ_STEM, KADJ_NA),
        ('V5_TE→AUXS[0]',     V5_TE, AUX_TA),
        ('N_SAHEN→VSURU_BASE',N_SAHEN, VSURU_BASE),
        ('P_GA→N_GENERAL',    P_GA, N_GENERAL),
        ('P_KA→N_GENERAL',    P_KA, N_GENERAL),   # sentence-final → N: costly
    ]
    print('\nSpot-checks (row=prevRight, col=curLeft):')
    for label, r, c in checks:
        print(f'  {label:30s} = {matrix[r][c]:5d}')

    print(f'\n{NUM_CLASSES}×{NUM_CLASSES} = {NUM_CLASSES*NUM_CLASSES} cells')


if __name__ == '__main__':
    main()
