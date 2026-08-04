#!/usr/bin/env python3
"""Pack char_lm.tsv into the binary form the device loads.

Same layout as the mozc string tables (see pack_strings.py), plus one
parallel count array:

    char_lm.blob   n-grams concatenated as UTF-8, sorted by UTF-8 bytes
    char_lm.len    uint8 byte length per n-gram
    char_lm.base   uint32 blob offset of every 32nd n-gram
    char_lm.cnt    uint32 count per n-gram
    char_lm.json   {"totalChars": N, "order": M, "count": K}

Sorted by bytes so the device can binary-search an n-gram directly against
the blob, exactly like readings -- no Map, nothing materialised at load.
Lookup happens per character per candidate during rescoring, so it has to be
allocation-free; that is what this layout buys.

Counts are kept raw rather than pre-divided into probabilities because
scoring uses stupid backoff, which needs count(context) as well as
count(context+char), and both live in the same table.

Usage: python tools/mozc_data/pack_char_lm.py [--min-count N]
"""

import argparse
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAWFILE = os.path.join(HERE, '..', '..', 'entry', 'src', 'main',
                       'resources', 'rawfile')
BLOCK = 32   # must match MOZC_STR_BLOCK in KanaKanjiConverter.ets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=os.path.join(HERE, 'char_lm.tsv'))
    ap.add_argument('--min-count', type=int, default=0,
                    help='drop n-grams (order >= 2) below this count')
    args = ap.parse_args()

    total_chars = 0
    order = 0
    items = []
    with open(args.src, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            if line.startswith('#chars\t'):
                total_chars = int(line.split('\t')[1])
                continue
            tab = line.rfind('\t')
            ng = line[:tab]
            cnt = int(line[tab + 1:])
            if len(ng) >= 2 and cnt < args.min_count:
                continue
            order = max(order, len(ng))
            items.append((ng.encode('utf-8'), cnt))

    items.sort(key=lambda x: x[0])
    for a, b in zip(items, items[1:]):
        if a[0] == b[0]:
            raise SystemExit('duplicate n-gram: ' + a[0].decode('utf-8'))

    blob = b''.join(ng for ng, _ in items)
    lengths = bytearray(len(items))
    bases = []
    counts = []
    pos = 0
    for i, (ng, cnt) in enumerate(items):
        if len(ng) > 255:
            raise SystemExit('n-gram too long for a uint8 length')
        if i % BLOCK == 0:
            bases.append(pos)
        lengths[i] = len(ng)
        counts.append(min(cnt, 0xFFFFFFFF))
        pos += len(ng)

    out = {}
    for name, data in (
            ('char_lm.blob', blob),
            ('char_lm.len', bytes(lengths)),
            ('char_lm.base', struct.pack('<%dI' % len(bases), *bases)),
            ('char_lm.cnt', struct.pack('<%dI' % len(counts), *counts))):
        path = os.path.join(RAWFILE, name)
        with open(path, 'wb') as f:
            f.write(data)
        out[name] = len(data)

    meta = {'totalChars': total_chars, 'order': order, 'count': len(items)}
    with open(os.path.join(RAWFILE, 'char_lm.json'), 'w', encoding='utf-8') as f:
        json.dump(meta, f, separators=(',', ':'))

    print('%d n-grams, order %d, %d training chars' % (len(items), order, total_chars))
    total = 0
    for name, size in out.items():
        print('   %-16s %7.2f MB' % (name, size / 1048576))
        total += size
    print('   %-16s %7.2f MB' % ('合計', total / 1048576))


if __name__ == '__main__':
    sys.exit(main())
