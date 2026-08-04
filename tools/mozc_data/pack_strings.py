#!/usr/bin/env python3
"""Repack the three shipped string tables from JSON into flat binary blobs.

Why this exists
---------------
`convert_to_binary.py` already moved every *numeric* mozc table out of JSON
and into typed-array binaries, which is what fixed the OOM crash. The three
remaining JSON files are pure string tables:

    mozc_readings.json        15.7MB   746k readings
    mozc_dict_surfaces.json   19.3MB   flattened candidate surfaces
    mozc_costs_surfaces.json  14.6MB   flattened per-sense surfaces

They are cheap to *read* but expensive to *parse*. Measured on device
(HarmonyOS, IME extension process), loading the mozc engine cost 1990ms:

    file reads (76MB, all files)          139ms    7%
    JSON.parse of the three tables       1456ms   73%
    building Map<reading, index>          395ms   20%

So ~93% of the load is the JS engine materialising 746k+ string objects and
a hash map, not I/O. That cost is paid on *every* start of the IME extension
process -- and the extension is torn down whenever the user leaves a text
field -- which is what kept the mozc engine off by default.

What this writes
----------------
For each table, three files:

    .blob   all strings concatenated as UTF-8, no separators
    .len    uint8 byte length per string
    .base   uint32 blob offset of every 32nd string

A uint32 start offset per string would be the obvious layout, but at 2.96M
strings across the three tables that is 11.3MB of offsets alone -- more than
the JSON it replaces. Every string here is at most 99 bytes (measured), so
the length fits in a byte, and the start offset is recovered by adding at
most 31 lengths to the enclosing block's base. That is a few dozen additions
over a Uint8Array per access, which is nothing next to a JSON parse, and it
makes the packed form *smaller* than the JSON rather than larger.

Readings additionally get a `.srt` (uint32 reading indices sorted by UTF-8
byte order) so the device can binary-search readings directly against the
blob instead of building a Map.

Nothing is dropped, reordered, or rewritten: `.len`/`.base` are in the
original index order, so `mozc_dict_index.bin` / `mozc_costs_index.bin` stay
valid unchanged and conversion results are byte-for-byte identical. This is a
format change only, verified entry-by-entry against the JSON by
`verify_packed.js`.

Sorting for `.srt` is by UTF-8 bytes (not Python str order) so it matches the
device-side comparator exactly, which compares raw bytes.

Usage: python tools/mozc_data/pack_strings.py
"""

import json
import os
import struct
import sys

RAWFILE = os.path.join(os.path.dirname(__file__), '..', '..',
                       'entry', 'src', 'main', 'resources', 'rawfile')
# 元の JSON は rawfile に置くと HAP に同梱されてしまう (rawfile 配下は
# 丸ごと同梱される)。読むのはこのスクリプトと verify_packed.js だけなので、
# 保守用の入力としてこちらに置く。
SRCDIR = os.path.join(os.path.dirname(__file__), 'packed_src')

# Must match MOZC_STR_BLOCK in KanaKanjiConverter.ets.
BLOCK = 32


def pack(name, with_sort=False):
    src = os.path.join(SRCDIR, name + '.json')
    with open(src, 'rb') as f:
        items = json.loads(f.read().decode('utf-8'))
    if not isinstance(items, list):
        raise SystemExit(name + '.json is not a JSON array')

    encoded = [s.encode('utf-8') for s in items]
    blob = b''.join(encoded)
    lengths = bytearray(len(encoded))
    bases = []
    pos = 0
    for i, b in enumerate(encoded):
        if len(b) > 255:
            raise SystemExit('string too long for a uint8 length: ' + items[i])
        if i % BLOCK == 0:
            bases.append(pos)
        lengths[i] = len(b)
        pos += len(b)

    out_blob = os.path.join(RAWFILE, name + '.blob')
    out_len = os.path.join(RAWFILE, name + '.len')
    out_base = os.path.join(RAWFILE, name + '.base')
    with open(out_blob, 'wb') as f:
        f.write(blob)
    with open(out_len, 'wb') as f:
        f.write(bytes(lengths))
    with open(out_base, 'wb') as f:
        f.write(struct.pack('<%dI' % len(bases), *bases))

    written = [(out_blob, len(blob)), (out_len, len(lengths)),
               (out_base, len(bases) * 4)]

    if with_sort:
        # Sort indices by the encoded bytes, not by the str -- the device
        # comparator works on the blob's raw bytes.
        order = sorted(range(len(encoded)), key=lambda i: encoded[i])
        out_srt = os.path.join(RAWFILE, name + '.srt')
        with open(out_srt, 'wb') as f:
            f.write(struct.pack('<%dI' % len(order), *order))
        written.append((out_srt, len(order) * 4))
        # A duplicate reading would make binary search ambiguous (and would
        # mean the upstream build emitted two indices for one key).
        for a, b in zip(order, order[1:]):
            if encoded[a] == encoded[b]:
                raise SystemExit('duplicate reading: ' + items[a])

    src_size = os.path.getsize(src)
    total = sum(sz for _, sz in written)
    print('%-26s %7.2f MB (json) -> %7.2f MB  entries=%d'
          % (name, src_size / 1048576, total / 1048576, len(items)))
    for p, sz in written:
        print('    %-42s %7.2f MB' % (os.path.basename(p), sz / 1048576))
    return src_size, total


def main():
    grand_src = 0
    grand_out = 0
    for name, srt in (('mozc_readings', True),
                      ('mozc_dict_surfaces', False),
                      ('mozc_costs_surfaces', False)):
        s, o = pack(name, srt)
        grand_src += s
        grand_out += o
    print('-' * 64)
    print('合計 %.2f MB -> %.2f MB  (%+.2f MB)'
          % (grand_src / 1048576, grand_out / 1048576,
             (grand_out - grand_src) / 1048576))


if __name__ == '__main__':
    sys.exit(main())
