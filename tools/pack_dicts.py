#!/usr/bin/env python3
"""Pack dict.json / global_dict.json into the binary form the device loads.

Why
---
Measured on device, on a freshly started IME extension process after typing:

| engine | ark ts heap | native heap | PSS |
| --- | --- | --- | --- |
| 独自辞書 (track A only) | 144.5MB | 53.6MB | 231.6MB |
| mozc (track A + B)      | 120.8MB | 131.9MB | 277.2MB |

dict.json (4.7MB) + global_dict.json (11.6MB) held as parsed JSON is **~144MB
of ArkTS heap** -- more than the entire mozc engine, whose 73MB of data lives
in typed arrays on the native heap and whose JS heap footprint is *lower*.
383,383 keys and 594,173 strings as JS objects is simply expensive; the file
size says nothing about it.

So the light engine was the heavy one, and the fix is not to drop anything but
to stop materialising it. Same layout mozc's tables already use
(tools/mozc_data/pack_strings.py): blob + uint8 lengths + a base offset every
32 entries, strings decoded on first touch.

Layout, per dictionary:

    <name>.keys.blob/.len/.base   readings, sorted by UTF-8 bytes
    <name>.vals.blob/.len/.base   every reading's surfaces, concatenated
    <name>.idx.bin                uint32[keys+1]; reading i's surfaces are
                                  vals[idx[i] .. idx[i+1]]

Keys are emitted already sorted so no separate order table is needed --
`MozcStrTable.indexOf` binary-searches the blob directly when its sort array
is empty.

Content is unchanged: same readings, same surfaces, same order within each
reading. `verify_dicts.js` checks that entry by entry.

The JSON originals move to `tools/dict_src/`. Anything left under `rawfile/`
ships inside the HAP whether the app reads it or not.

Usage: python tools/pack_dicts.py
"""

import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAWFILE = os.path.join(HERE, '..', 'entry', 'src', 'main', 'resources', 'rawfile')
SRCDIR = os.path.join(HERE, 'dict_src')
BLOCK = 32   # must match MOZC_STR_BLOCK in KanaKanjiConverter.ets


def write_table(prefix, strings):
    """blob + uint8 lengths + per-BLOCK base offsets. Returns bytes written."""
    encoded = [s.encode('utf-8') for s in strings]
    blob = b''.join(encoded)
    lengths = bytearray(len(encoded))
    bases = []
    pos = 0
    for i, b in enumerate(encoded):
        if len(b) > 255:
            raise SystemExit('too long for a uint8 length: ' + strings[i])
        if i % BLOCK == 0:
            bases.append(pos)
        lengths[i] = len(b)
        pos += len(b)
    out = 0
    for suffix, data in (('.blob', blob), ('.len', bytes(lengths)),
                         ('.base', struct.pack('<%dI' % len(bases), *bases))):
        with open(os.path.join(RAWFILE, prefix + suffix), 'wb') as f:
            f.write(data)
        out += len(data)
    return out


def pack(name):
    src = os.path.join(SRCDIR, name + '.json')
    with open(src, encoding='utf-8') as f:
        d = json.load(f)

    # UTF-8 byte order, matching the device-side comparator exactly (it
    # compares raw blob bytes, not decoded strings).
    keys = sorted(d.keys(), key=lambda k: k.encode('utf-8'))
    vals = []
    idx = [0]
    for k in keys:
        v = d[k]
        if isinstance(v, str):
            v = [v]
        vals.extend(v)
        idx.append(len(vals))

    total = write_table(name + '.keys', keys)
    total += write_table(name + '.vals', vals)
    idx_path = os.path.join(RAWFILE, name + '.idx.bin')
    with open(idx_path, 'wb') as f:
        f.write(struct.pack('<%dI' % len(idx), *idx))
    total += len(idx) * 4

    src_size = os.path.getsize(src)
    print('%-16s %6.2f MB (json) -> %6.2f MB   読み %d 件 / 表記 %d 個'
          % (name, src_size / 1048576, total / 1048576, len(keys), len(vals)))
    return src_size, total


def main():
    if not os.path.isdir(SRCDIR):
        raise SystemExit('missing %s -- the JSON originals live there, not in '
                         'rawfile/ (they would ship in the HAP)' % SRCDIR)
    a = b = 0
    for name in ('dict', 'global_dict'):
        s, o = pack(name)
        a += s
        b += o
    print('-' * 62)
    print('合計 %.2f MB -> %.2f MB' % (a / 1048576, b / 1048576))


if __name__ == '__main__':
    sys.exit(main())
