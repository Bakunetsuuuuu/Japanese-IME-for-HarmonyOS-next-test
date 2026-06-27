#!/usr/bin/env python3
"""
Build Viterbi cost data from mecab-ipadic for shunti IME.

Usage:
    python3 tools/build_viterbi_dict.py <ipadic_dir> [dict_json] [out_dir]

Defaults:
    ipadic_dir  = /tmp/ipadic/   (unpack mecab-ipadic-2.7.0-20070801.tar.gz here)
    dict_json   = entry/src/main/resources/rawfile/dict.json
    out_dir     = entry/src/main/resources/rawfile/

Download IPAdic (NAIST License — commercial use permitted):
    https://sourceforge.net/projects/mecab/files/mecab-ipadic/2.7.0-20070801/mecab-ipadic-2.7.0-20070801.tar.gz

Output files:
    reading_cost.json  — Record<reading, [nodeCost, leftClass, rightClass]>
    matrix.json        — number[][] (100×100 Phase-2.5 connection cost matrix)

Phase-2.5 POS class IDs (100 classes — see gen_matrix_default.py for full list):
    0-13   名詞系  (N_GENERAL, N_SAHEN, N_KEIYODOSHI, N_PRONOUN, N_PROPER_*, ...)
    14-33  動詞活用形 (V5_BASE, V5_RENYOU, V5_TE, V1_BASE, VSURU_BASE, ...)
    34-41  形容詞  (ADJ_BASE, ADJ_KU, ADJ_TE, ADJ_TA, KADJ_STEM, KADJ_NA, KADJ_NI)
    42-47  副詞    (ADV_DEGREE, ADV_TIME, ADV_FREQ, ADV_MANNER, ADV_NEGCORR, ADV_MODAL)
    48-57  格助詞  (P_GA, P_WO, P_NI, P_DE, P_TO, P_NO, P_HE, P_YORI, P_KARA, P_MADE)
    58-62  係助詞  (P_WA, P_MO, P_FOCUS, P_HODO, P_YA)
    63-68  接続助詞 (P_TE, P_BA, P_NODE, P_NONI, P_NAGARA, P_TEMO)
    69-72  終助詞  (P_KA, P_NE, P_YO, P_ZO)
    73-86  助動詞  (AUX_TA, AUX_TEIRU, AUX_NAI, AUX_NAKU, AUX_MASU, AUX_DESU, ...)
    87-89  接続詞  (CONJ_CAUSE, CONJ_CONTRAST, CONJ_ADD)
    90-97  その他  (INTJ, FILLER, SYMBOL_G/P, NUM_ARABIC, PREFIX_N/V, SUFFIX_G)
    98     UNKNOWN
    99     BOS_EOS (reserved — not emitted in cost data)
"""

import csv
import glob
import json
import os
import sys

# ---------- Phase-2.5 POS class IDs (100 classes) ----------
# Must match KanaKanjiConverter.ets and gen_matrix_default.py.
N_GENERAL, N_SAHEN, N_KEIYODOSHI, N_PRONOUN           = 0, 1, 2, 3
N_PROPER_P, N_PROPER_L, N_PROPER_O                    = 4, 5, 6
N_NUMBER, N_COUNTER, N_NONSELF                         = 7, 8, 9
N_ADVERBNOUN, N_VERBALNOUN, N_ABBREV, N_COMPOUND       = 10, 11, 12, 13
V5_BASE, V5_RENYOU, V5_RENYOU_ON                      = 14, 15, 16
V5_TE, V5_TA, V5_NAI, V5_COND, V5_IMP                = 17, 18, 19, 20, 21
V1_BASE, V1_RENYOU, V1_TE, V1_TA, V1_NAI, V1_COND    = 22, 23, 24, 25, 26, 27
VSURU_BASE, VSURU_RENYOU, VSURU_TE, VSURU_NAI          = 28, 29, 30, 31
VKURU_BASE, VKURU_RENYOU                               = 32, 33
ADJ_BASE, ADJ_KU, ADJ_TE, ADJ_TA, ADJ_NAI_KU          = 34, 35, 36, 37, 38
KADJ_STEM, KADJ_NA, KADJ_NI                            = 39, 40, 41
ADV_DEGREE, ADV_TIME, ADV_FREQ                         = 42, 43, 44
ADV_MANNER, ADV_NEGCORR, ADV_MODAL                     = 45, 46, 47
P_GA, P_WO, P_NI, P_DE, P_TO, P_NO                   = 48, 49, 50, 51, 52, 53
P_HE, P_YORI, P_KARA, P_MADE                          = 54, 55, 56, 57
P_WA, P_MO, P_FOCUS, P_HODO, P_YA                    = 58, 59, 60, 61, 62
P_TE, P_BA, P_NODE, P_NONI, P_NAGARA, P_TEMO         = 63, 64, 65, 66, 67, 68
P_KA, P_NE, P_YO, P_ZO                               = 69, 70, 71, 72
AUX_TA, AUX_TEIRU, AUX_NAI, AUX_NAKU                 = 73, 74, 75, 76
AUX_MASU, AUX_MASEN, AUX_MASHITA                      = 77, 78, 79
AUX_DESU, AUX_DA, AUX_DARO                            = 80, 81, 82
AUX_SERU, AUX_RERU, AUX_TAI, AUX_SOUDA               = 83, 84, 85, 86
CONJ_CAUSE, CONJ_CONTRAST, CONJ_ADD                   = 87, 88, 89
INTJ, FILLER                                          = 90, 91
SYMBOL_G, SYMBOL_P, NUM_ARABIC                        = 92, 93, 94
PREFIX_N, PREFIX_V, SUFFIX_G                          = 95, 96, 97
UNKNOWN, BOS_EOS                                      = 98, 99

# Specific particle class by reading (used to resolve ambiguous 助詞 entries).
_PARTICLE_BY_READING: dict = {
    'が': P_GA, 'を': P_WO, 'に': P_NI, 'で': P_DE,
    'と': P_TO, 'の': P_NO, 'へ': P_HE, 'より': P_YORI,
    'から': P_KARA, 'まで': P_MADE,
    'は': P_WA, 'も': P_MO,
    'こそ': P_FOCUS, 'だけ': P_FOCUS, 'しか': P_FOCUS,
    'さえ': P_FOCUS, 'のみ': P_FOCUS,
    'ほど': P_HODO, 'くらい': P_HODO, 'ぐらい': P_HODO,
    'ばかり': P_HODO, 'など': P_HODO,
    'や': P_YA, 'とか': P_YA,
    'て': P_TE, 'ば': P_BA, 'ので': P_NODE, 'のに': P_NONI,
    'ながら': P_NAGARA, 'ても': P_TEMO, 'でも': P_TEMO,
    'たり': P_TEMO,
    'か': P_KA, 'かな': P_KA,
    'ね': P_NE, 'な': P_NE,
    'よ': P_YO,
    'ぞ': P_ZO, 'ぜ': P_ZO, 'わ': P_ZO,
}

# Specific auxiliary class by reading.
_AUX_BY_READING: dict = {
    'た': AUX_TA, 'だった': AUX_TA, 'でした': AUX_TA,
    'ている': AUX_TEIRU, 'ていた': AUX_TEIRU, 'てある': AUX_TEIRU,
    'ておく': AUX_TEIRU, 'ていく': AUX_TEIRU, 'てくる': AUX_TEIRU,
    'ない': AUX_NAI, 'ぬ': AUX_NAI, 'ん': AUX_NAI,
    'なく': AUX_NAKU, 'なかった': AUX_NAKU, 'なくて': AUX_NAKU,
    'ます': AUX_MASU,
    'ません': AUX_MASEN, 'ませんでした': AUX_MASEN,
    'ました': AUX_MASHITA,
    'です': AUX_DESU,
    'だ': AUX_DA, 'じゃ': AUX_DA,
    'だろう': AUX_DARO, 'だろ': AUX_DARO, 'でしょう': AUX_DARO,
    'せる': AUX_SERU, 'させる': AUX_SERU,
    'れる': AUX_RERU, 'られる': AUX_RERU,
    'たい': AUX_TAI, 'たく': AUX_TAI, 'たかった': AUX_TAI,
    'そうだ': AUX_SOUDA, 'らしい': AUX_SOUDA, 'みたい': AUX_SOUDA,
    'ようだ': AUX_SOUDA, 'そうです': AUX_SOUDA,
}


def _verb_class(conj_type: str, conj_form: str) -> int:
    """Map (活用型, 活用形) → Phase-2.5 verb class."""
    is_go    = '五段' in conj_type
    is_ichi  = '一段' in conj_type
    is_suru  = 'サ変' in conj_type
    is_kuru  = 'カ変' in conj_type

    if '基本形' in conj_form or '体言接続' in conj_form:
        if is_suru: return VSURU_BASE
        if is_kuru: return VKURU_BASE
        if is_ichi: return V1_BASE
        return V5_BASE
    if '連用タ接続' in conj_form or 'ガ行音便' in conj_form or \
       'イ音便' in conj_form or 'ウ音便' in conj_form:
        if is_suru: return VSURU_RENYOU
        if is_kuru: return VKURU_RENYOU
        return V5_RENYOU_ON
    if '連用形' in conj_form:
        if is_suru: return VSURU_RENYOU
        if is_kuru: return VKURU_RENYOU
        if is_ichi: return V1_RENYOU
        return V5_RENYOU
    if '未然' in conj_form:
        if is_suru: return VSURU_NAI
        if is_ichi: return V1_NAI
        return V5_NAI
    if '仮定形' in conj_form or '仮定縮約' in conj_form:
        if is_ichi: return V1_COND
        return V5_COND
    if '命令' in conj_form:
        return V5_IMP
    if is_suru: return VSURU_BASE
    if is_kuru: return VKURU_BASE
    if is_ichi: return V1_BASE
    return V5_BASE


def _aux_class(conj_type: str, conj_form: str) -> int:
    """Map 助動詞 (活用型, 活用形) → Phase-2.5 auxiliary class."""
    ct = conj_type.lower()
    if 'ない' in ct or 'ぬ' in ct:
        return AUX_NAI
    if 'た' in ct and ('過去' in ct or 'た型' in ct or 'たい型' in ct):
        return AUX_TA if 'たい' not in ct else AUX_TAI
    if 'たい' in ct:
        return AUX_TAI
    if 'ます' in ct:
        if 'ませ' in conj_form.lower() or '否定' in conj_form:
            return AUX_MASEN
        if 'た接続' in conj_form or '過去' in conj_form:
            return AUX_MASHITA
        return AUX_MASU
    if 'です' in ct:
        return AUX_DESU
    if 'だ' in ct and '特殊' in ct:
        return AUX_DA
    if 'だろう' in ct or '推量' in ct:
        return AUX_DARO
    if 'せる' in ct or 'させる' in ct:
        return AUX_SERU
    if 'れる' in ct or 'られる' in ct:
        return AUX_RERU
    if 'そうだ' in ct or 'らしい' in ct or 'みたい' in ct or 'ようだ' in ct:
        return AUX_SOUDA
    return AUX_TA


def pos_to_class(pos1: str, pos2: str, pos3: str = '',
                 conj_type: str = '', conj_form: str = '',
                 reading: str = '') -> int:
    """Map IPAdic POS fields to a Phase-2.5 class ID."""
    if pos1 == '名詞':
        if pos2 == 'サ変接続':     return N_SAHEN
        if pos2 == '形容動詞語幹': return N_KEIYODOSHI
        if pos2 == '代名詞':       return N_PRONOUN
        if pos2 == '固有名詞':
            if pos3 == '人名':     return N_PROPER_P
            if pos3 == '地域':     return N_PROPER_L
            return N_PROPER_O
        if pos2 == '数':           return N_NUMBER
        if pos2 == '接尾':
            if pos3 == '助数詞':   return N_COUNTER
            return SUFFIX_G
        if pos2 == '非自立':       return N_NONSELF
        if pos2 == '副詞可能':     return N_ADVERBNOUN
        if pos2 == '接続詞的':     return CONJ_CAUSE
        return N_GENERAL

    if pos1 == '動詞':
        return _verb_class(conj_type, conj_form)

    if pos1 == '形容詞':
        if '基本形' in conj_form or '体言接続' in conj_form: return ADJ_BASE
        if 'タ接続' in conj_form:                            return ADJ_TA
        if 'テ接続' in conj_form or 'くて' in conj_form:    return ADJ_TE
        if '連用形' in conj_form:                            return ADJ_KU
        if '未然形' in conj_form:                            return ADJ_NAI_KU
        return ADJ_BASE

    if pos1 == '形容動詞':
        if 'ナ接続' in conj_form:                            return KADJ_NA
        if 'ニ形' in conj_form or '連用形' in conj_form:    return KADJ_NI
        return KADJ_STEM

    if pos1 == '副詞':
        return ADV_DEGREE  # simplified: all adverbs map to ADV_DEGREE

    if pos1 == '助詞':
        # Use reading for specific particle classes
        if reading:
            cls = _PARTICLE_BY_READING.get(reading)
            if cls is not None:
                return cls
        if pos2 == '格助詞':      return P_NI   # generic case particle
        if pos2 in ('係助詞',):   return P_WA
        if pos2 in ('副助詞',):   return P_HODO
        if pos2 in ('接続助詞',): return P_TE
        if pos2 in ('終助詞',):   return P_KA
        if pos2 in ('並立助詞',): return P_YA
        return P_WA

    if pos1 == '助動詞':
        if reading:
            cls = _AUX_BY_READING.get(reading)
            if cls is not None:
                return cls
        return _aux_class(conj_type, conj_form)

    if pos1 == '接続詞': return CONJ_CAUSE
    if pos1 == '感動詞': return INTJ
    if pos1 == '記号':
        if pos2 in ('句点', '読点', '括弧開', '括弧閉'): return SYMBOL_P
        return SYMBOL_G
    if pos1 == '接尾詞':  return SUFFIX_G
    if pos1 == '接頭詞':
        if pos2 == '動詞接続': return PREFIX_V
        return PREFIX_N
    if pos1 in ('フィラー', 'その他'): return FILLER
    return UNKNOWN


# Selection penalty to break ties when multiple IPAdic entries share a reading.
# Closed-class words (particles/auxiliaries) are preferred for their readings.
def pos_penalty(cls: int) -> int:
    # Particles / auxiliaries: strongly preferred
    if 48 <= cls <= 72:   return -3000  # all particles
    if 73 <= cls <= 86:   return -2500  # all auxiliaries
    # Content words: neutral
    if 0 <= cls <= 13:    return 0      # nouns
    if 14 <= cls <= 33:   return 0      # verbs
    if 34 <= cls <= 41:   return 0      # adjectives
    if 42 <= cls <= 47:   return 0      # adverbs
    # Conjunctions: slight preference
    if 87 <= cls <= 89:   return -500
    # Proper nouns: penalise (over-matches many readings)
    if cls in (N_PROPER_P, N_PROPER_L, N_PROPER_O): return 2000
    # Numbers / counters: slight penalty
    if cls in (N_NUMBER, N_COUNTER): return 1000
    # Suffix/prefix: slight penalty
    if cls in (SUFFIX_G, PREFIX_N, PREFIX_V): return 1500
    # Symbol: heavy penalty
    if cls in (SYMBOL_G, SYMBOL_P): return 3000
    return 1000  # unknown / filler



# ---------- katakana → hiragana ----------
def kata_to_hira(s: str) -> str:
    result = []
    for ch in s:
        cp = ord(ch)
        if 0x30A1 <= cp <= 0x30F6:
            result.append(chr(cp - 0x60))
        else:
            result.append(ch)
    return ''.join(result)


# ---------- parse IPAdic CSVs ----------
def parse_ipadic_csvs(ipadic_dir: str) -> dict:
    """
    Returns: {reading_hira: (min_cost, left_id, right_id, pos1, pos2)}
    For each reading we keep the entry with the best effective score
    (raw cost + pos_penalty); the stored node cost is the chosen entry's RAW cost.
    """
    csv_files = glob.glob(os.path.join(ipadic_dir, '*.csv'))
    if not csv_files:
        raise FileNotFoundError(f'No CSV files found in {ipadic_dir}')

    entries: dict = {}    # reading → (raw_cost, left_id, right_id, pos1,pos2,pos3,ct,cf)
    best_score: dict = {}
    total = 0
    for csv_path in csv_files:
        with open(csv_path, encoding='euc-jp', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 13:
                    continue
                try:
                    left_id  = int(row[1])
                    right_id = int(row[2])
                    cost     = int(row[3])
                except ValueError:
                    continue
                pos1      = row[4]  if len(row) > 4  else ''
                pos2      = row[5]  if len(row) > 5  else ''
                pos3      = row[6]  if len(row) > 6  else ''
                conj_type = row[8]  if len(row) > 8  else ''
                conj_form = row[9]  if len(row) > 9  else ''
                kata_reading = row[11] if len(row) > 11 else ''
                if not kata_reading:
                    continue
                reading = kata_to_hira(kata_reading)
                cls   = pos_to_class(pos1, pos2, pos3, conj_type, conj_form, reading)
                score = cost + pos_penalty(cls)
                if reading not in best_score or score < best_score[reading]:
                    best_score[reading] = score
                    entries[reading] = (cost, left_id, right_id,
                                        pos1, pos2, pos3, conj_type, conj_form)
                total += 1

    print(f'IPAdic entries parsed: {total:,}')
    print(f'Unique readings:       {len(entries):,}')
    return entries


# ---------- parse matrix.def ----------
def parse_matrix(ipadic_dir: str) -> tuple:
    """
    Returns (size_left, size_right, {(left_id, right_id): cost}).
    """
    matrix_path = os.path.join(ipadic_dir, 'matrix.def')
    if not os.path.exists(matrix_path):
        raise FileNotFoundError(f'matrix.def not found in {ipadic_dir}')

    costs: dict = {}
    size_left = 0
    size_right = 0
    with open(matrix_path, encoding='utf-8', errors='replace') as f:
        first = True
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if first:
                first = False
                if len(parts) == 2:
                    size_left  = int(parts[0])
                    size_right = int(parts[1])
                    continue
            if len(parts) < 3:
                continue
            try:
                l, r, c = int(parts[0]), int(parts[1]), int(parts[2])
                costs[(l, r)] = c
            except ValueError:
                continue
    print(f'matrix.def entries:    {len(costs):,}  ({size_left}×{size_right})')
    return size_left, size_right, costs


# ---------- build macro-class matrix ----------
NUM_CLASSES = 100  # Phase-2.5: 100 classes

def build_class_matrix(
    size_left: int,
    size_right: int,
    raw_costs: dict,
    ipadic_dir: str,
) -> list:
    """
    Builds a NUM_CLASSES×NUM_CLASSES matrix by averaging raw IPAdic costs
    within the same (leftClass, rightClass) Phase-2.5 macro-class pair.
    Falls back to the hand-crafted matrix (gen_matrix_default.py) for empty cells.
    """
    left_class_of_id:  dict = {}
    right_class_of_id: dict = {}

    csv_files = glob.glob(os.path.join(ipadic_dir, '*.csv'))
    for csv_path in csv_files:
        with open(csv_path, encoding='euc-jp', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(rows := row) < 10:
                    continue
                try:
                    left_id  = int(rows[1])
                    right_id = int(rows[2])
                except ValueError:
                    continue
                pos1      = rows[4] if len(rows) > 4 else ''
                pos2      = rows[5] if len(rows) > 5 else ''
                pos3      = rows[6] if len(rows) > 6 else ''
                conj_type = rows[8] if len(rows) > 8 else ''
                conj_form = rows[9] if len(rows) > 9 else ''
                kata_reading = rows[11] if len(rows) > 11 else ''
                reading = kata_to_hira(kata_reading) if kata_reading else ''
                cls = pos_to_class(pos1, pos2, pos3, conj_type, conj_form, reading)
                left_class_of_id.setdefault(left_id,  cls)
                right_class_of_id.setdefault(right_id, cls)

    # Aggregate: sum and count per (leftClass, rightClass)
    agg_sum:   list = [[0] * NUM_CLASSES for _ in range(NUM_CLASSES)]
    agg_count: list = [[0] * NUM_CLASSES for _ in range(NUM_CLASSES)]

    for (l, r), c in raw_costs.items():
        lc = left_class_of_id.get(l, 0)
        rc = right_class_of_id.get(r, 0)
        agg_sum[lc][rc]   += c
        agg_count[lc][rc] += 1

    # Average; use 0 for empty cells
    result: list = []
    for row_idx in range(NUM_CLASSES):
        row = []
        for col_idx in range(NUM_CLASSES):
            cnt = agg_count[row_idx][col_idx]
            row.append(round(agg_sum[row_idx][col_idx] / cnt) if cnt > 0 else 0)
        result.append(row)
    return result


# ---------- main ----------
def main() -> None:
    ipadic_dir = sys.argv[1] if len(sys.argv) > 1 else '/tmp/ipadic'
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir)
    dict_json  = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        repo_root, 'entry/src/main/resources/rawfile/dict.json')
    out_dir    = sys.argv[3] if len(sys.argv) > 3 else os.path.join(
        repo_root, 'entry/src/main/resources/rawfile')

    print(f'IPAdic dir:  {ipadic_dir}')
    print(f'dict.json:   {dict_json}')
    print(f'Output dir:  {out_dir}')
    print()

    # Load existing dict.json to restrict output to known readings
    print('Loading dict.json …')
    with open(dict_json, encoding='utf-8') as f:
        known_readings: set = set(json.load(f).keys())
    print(f'Known readings in dict.json: {len(known_readings):,}')
    print()

    # Parse IPAdic
    print('Parsing IPAdic CSVs …')
    ipadic_entries = parse_ipadic_csvs(ipadic_dir)

    # Build reading_cost.json (restrict to dict.json readings)
    print('\nBuilding reading_cost.json …')
    cost_dict: dict = {}
    for reading, entry in ipadic_entries.items():
        if reading not in known_readings:
            continue
        cost = entry[0]
        pos1, pos2, pos3, conj_type, conj_form = entry[3], entry[4], entry[5], entry[6], entry[7]
        lc = pos_to_class(pos1, pos2, pos3, conj_type, conj_form, reading)
        rc = lc  # left and right macro-class are the same for single-morpheme words
        cost_dict[reading] = [cost, lc, rc]

    print(f'Readings with cost data: {len(cost_dict):,} / {len(known_readings):,}')

    out_cost = os.path.join(out_dir, 'reading_cost.json')
    with open(out_cost, 'w', encoding='utf-8') as f:
        json.dump(cost_dict, f, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    size_kb = os.path.getsize(out_cost) / 1024
    print(f'Written: {out_cost}  ({size_kb:.0f} KB)')

    # Parse matrix.def and build macro-class matrix
    print('\nParsing matrix.def …')
    size_left, size_right, raw_costs = parse_matrix(ipadic_dir)

    print(f'Building {NUM_CLASSES}×{NUM_CLASSES} macro-class connection matrix …')
    class_matrix = build_class_matrix(size_left, size_right, raw_costs, ipadic_dir)

    out_matrix = os.path.join(out_dir, 'matrix.json')
    with open(out_matrix, 'w', encoding='utf-8') as f:
        json.dump(class_matrix, f, separators=(',', ':'))
    print(f'Written: {out_matrix}')

    # Spot-check
    print('\nSpot-check reading_cost.json:')
    checks = ['たべる', 'ように', 'は', 'にほん', 'こんにちは', 'する', 'いく']
    for k in checks:
        v = cost_dict.get(k)
        print(f'  {k}: {v}')

    print(f'\nMacro-class matrix ({NUM_CLASSES}×{NUM_CLASSES}) — first 15 rows shown:')
    header = '    ' + ' '.join(f'{c:5d}' for c in range(min(NUM_CLASSES, 15)))
    print(header)
    for r, row in enumerate(class_matrix[:15]):
        cells = ' '.join(f'{v:5d}' for v in row[:15])
        print(f'  {r:2d}: {cells}')


if __name__ == '__main__':
    main()
