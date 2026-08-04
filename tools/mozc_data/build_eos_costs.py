#!/usr/bin/env python3
"""Derive a word->EOS cost per class and store it in mozc_matrix.json.

Why this is needed
------------------
segment()'s track-B DP charges each candidate final word an edge cost into
EOS, on the stated assumption that mozc's BOS and EOS share raw id 0 and so
`matrix[cls][0]` is the word->EOS transition. The first half is true; the
second is not. In mozc's own `connection_single_column.txt` (2672x2672),

    row 0    (BOS -> x)   2671 / 2672 non-zero
    column 0 (x -> EOS)      0 / 2672 non-zero

Column 0 is entirely zero in the OSS data -- mozc's own converter decides
sentence-final form elsewhere, not through this matrix. So the DP's EOS term
evaluated to 0 for every class and contributed nothing at all. The signal the
comment describes was simply absent, and any sentence-final choice was made
on word cost alone. That is what produced

    そのほんはわたしのです -> その本は私のデス     (名詞,一般 デス 18384
                                                  beat 助動詞 です 18928
                                                  with both EOS terms 0)

Substitute
----------
What a word can be followed by at the end of a sentence is what it can be
followed by before a 。 -- and the 記号,句点 columns *are* populated. So use

    eos[cls] = min over kuten classes k of matrix[cls][k]

as the EOS transition cost. This is mozc's own measured data for "this POS
is at the end of a sentence", just read from the column that has it:

    助動詞 (です)        1717
    名詞,一般            3117
    助詞,格助詞 (の)    12882      <- a dangling particle, correctly awful

No constant is invented or tuned here; every number comes out of mozc's
matrix.

Writes `eosCosts` (one uint16 per class) into
`entry/src/main/resources/rawfile/mozc_matrix.json`, which the device already
loads. Run after `build_mozc_engine.py` (or any time, since it only reads
mozc_matrix.bin/.json, both of which are committed).

Usage: python tools/mozc_data/build_eos_costs.py
"""

import array
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAWFILE = os.path.join(HERE, '..', '..', 'entry', 'src', 'main',
                       'resources', 'rawfile')


def main():
    with open(os.path.join(HERE, 'mozc_classes_reference.json'),
              encoding='utf-8') as f:
        raw = json.load(f)
    labels = (list(raw) if isinstance(raw, list)
              else [raw.get(str(i)) for i in range(max(int(k) for k in raw) + 1)])

    matrix_json = os.path.join(RAWFILE, 'mozc_matrix.json')
    with open(matrix_json, encoding='utf-8') as f:
        meta = json.load(f)
    n = meta['size']

    cells = array.array('H')
    with open(os.path.join(RAWFILE, 'mozc_matrix.bin'), 'rb') as f:
        cells.frombytes(f.read())
    if len(cells) != n * n:
        raise SystemExit('matrix.bin is %d cells, expected %d' % (len(cells), n * n))

    kuten = [i for i, l in enumerate(labels) if l and l.startswith('記号,句点')]
    if not kuten:
        raise SystemExit('no 記号,句点 classes found in mozc_classes_reference.json')

    eos = [min(cells[c * n + k] for k in kuten) for c in range(n)]
    meta['eosCosts'] = eos
    meta['eosSourceClasses'] = kuten
    with open(matrix_json, 'w', encoding='utf-8') as f:
        json.dump(meta, f, ensure_ascii=False, separators=(',', ':'))

    nonzero = sum(1 for v in eos if v)
    print('句点クラス %d 個から EOS コストを導出: 非ゼロ %d / %d  min=%d max=%d'
          % (len(kuten), nonzero, n, min(eos), max(eos)))
    for cls, name in ((172, '助動詞 です'), (1851, '名詞,一般'),
                      (374, '助詞,格助詞 の')):
        if cls < n:
            print('   %-14s cls=%-5d eos=%d' % (name, cls, eos[cls]))
    print('wrote eosCosts into %s' % matrix_json)


if __name__ == '__main__':
    sys.exit(main())
