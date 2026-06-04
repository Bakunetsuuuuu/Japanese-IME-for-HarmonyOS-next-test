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
    matrix.json        — number[][] (15×15 macro-class connection cost matrix)

POS macro-class IDs (must match KanaKanjiConverter.ets constants):
    0  unknown / other
    1  名詞-一般
    2  名詞-固有名詞
    3  動詞
    4  形容詞 / 形容動詞
    5  副詞
    6  助詞
    7  助動詞
    8  接続詞
    9  感動詞
    10 記号
    11 名詞-数
    12 接尾詞
    13 接頭詞
    14 BOS/EOS (reserved — not emitted in cost data)
"""

import csv
import glob
import json
import os
import sys

# ---------- POS macro-class mapping ----------
# Maps (品詞, 品詞細分類1) → macro-class ID.
# Falls back to 品詞 alone if sub-class is not in the table.
_POS1_MAP: dict = {
    '名詞': {
        '一般':       1,
        '代名詞':     1,
        '副詞可能':   1,
        '固有名詞':   2,
        '数':        11,
        '接続詞的':   8,
        '接尾':      12,
        '非自立':     1,
        '特殊':       1,
    },
    '動詞':       {None: 3},
    '形容詞':     {None: 4},
    '形容動詞':   {None: 4},
    '副詞':       {None: 5},
    '助詞':       {None: 6},
    '助動詞':     {None: 7},
    '接続詞':     {None: 8},
    '感動詞':     {None: 9},
    '記号':       {None: 10},
    '接尾詞':     {None: 12},
    '接頭詞':     {None: 13},
    'フィラー':   {None: 0},
    'その他':     {None: 0},
}

def pos_to_class(pos1: str, pos2: str) -> int:
    mapping = _POS1_MAP.get(pos1)
    if mapping is None:
        return 0
    sub = mapping.get(pos2) if pos2 else None
    if sub is not None:
        return sub
    return mapping.get(None, 0)


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
    We keep only the lowest-cost entry per reading.
    """
    csv_files = glob.glob(os.path.join(ipadic_dir, '*.csv'))
    if not csv_files:
        raise FileNotFoundError(f'No CSV files found in {ipadic_dir}')

    entries: dict = {}
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
                pos1 = row[4] if len(row) > 4 else ''
                pos2 = row[5] if len(row) > 5 else ''
                kata_reading = row[11] if len(row) > 11 else ''
                if not kata_reading:
                    continue
                reading = kata_to_hira(kata_reading)
                # Keep the lowest-cost entry per reading
                if reading not in entries or cost < entries[reading][0]:
                    entries[reading] = (cost, left_id, right_id, pos1, pos2)
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
NUM_CLASSES = 15

def build_class_matrix(
    size_left: int,
    size_right: int,
    raw_costs: dict,
    ipadic_dir: str,
) -> list:
    """
    Builds a NUM_CLASSES×NUM_CLASSES matrix by averaging raw costs
    within the same (leftClass, rightClass) macro-class pair.
    Requires pos_class_for_id() to map leftId/rightId to macro-class.
    """
    # To map contextId → macro-class we need to know which POS each contextId belongs to.
    # IPAdic's left/right context IDs are assigned per dictionary entry; we build a
    # reverse mapping from the same CSV entries.
    left_class_of_id:  dict = {}
    right_class_of_id: dict = {}

    csv_files = glob.glob(os.path.join(ipadic_dir, '*.csv'))
    for csv_path in csv_files:
        with open(csv_path, encoding='euc-jp', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(rows := row) < 6:
                    continue
                try:
                    left_id  = int(rows[1])
                    right_id = int(rows[2])
                except ValueError:
                    continue
                pos1 = rows[4] if len(rows) > 4 else ''
                pos2 = rows[5] if len(rows) > 5 else ''
                cls = pos_to_class(pos1, pos2)
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
    for reading, (cost, left_id, right_id, pos1, pos2) in ipadic_entries.items():
        if reading not in known_readings:
            continue
        lc = pos_to_class(pos1, pos2)
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

    print('Building 15×15 macro-class connection matrix …')
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

    print('\nMacro-class matrix (15×15) — rows=prevRightClass, cols=curLeftClass:')
    header = '    ' + ' '.join(f'{c:5d}' for c in range(NUM_CLASSES))
    print(header)
    for r, row in enumerate(class_matrix):
        cells = ' '.join(f'{v:5d}' for v in row)
        print(f'  {r:2d}: {cells}')


if __name__ == '__main__':
    main()
