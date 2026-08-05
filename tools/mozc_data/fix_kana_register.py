#!/usr/bin/env python3
"""Drop katakana-register senses of words that are normally written in kana.

The problem
-----------
mozc's POS ids (IPADIC's) encode the *written form* of closed-class words in
the id itself, so one word can occupy two ids:

    172  助動詞,*,*,*,特殊・デス,基本形,です    surface です   cost 40
    178  助動詞,*,*,*,特殊・デス,基本形,デス    surface デス   cost  0

The connection matrix cannot separate them: its 助詞,格助詞「の」 row holds
only 217 distinct values across all 2,673 columns, and both ids sit in the
same bucket (`M[の][です] == M[の][デス] == 12882`). With the transition cost
equal, the 40-unit word-cost difference decides, and the katakana id wins.
Every hiragana-typed sentence ending in です then converts to デス:

    そのほんはわたしのです -> その本は私のデス
    このてぶくろわたしのです -> この手袋私のデス

Same shape for ございます -> ゴザイマス (cost 11 vs 969), だけ/など/とか/
ござる/べし/たり and the rest of the 44 id pairs built this way.

`build_mozc_engine.py` already tie-breaks katakana toward hiragana
(HIRA_MARGIN), but only *within* one (leftId, rightId) group -- and these two
sit in different groups by construction, so the gate never fires on exactly
the case it was written for.

The rule
--------
For an all-hiragana reading, drop the sense whose class carries a katakana
base form when a twin class (identical POS fields, hiragana base form) also
has a sense for that same reading **whose surface is the reading itself**.

That last condition is what keeps this from eating real loanwords. Compare:

    です     twin's surface です      == reading  -> です is a kana word,
                                                    デス is a register error
    でかーる  twin's surface でカール  != reading  -> でかーる's katakana
                                                    surface デカール is the
                                                    real word; leave it

Without it the rule would delete デカール/デグレード/デフェンス and every
other loanword mozc happens to file under a 助詞「デ」 id.

Usage (from the repo root):

    python tools/mozc_data/fix_kana_register.py
    python tools/mozc_data/convert_to_binary.py
    python tools/mozc_data/pack_strings.py      # after moving the JSON out
    bun tools/mozc_data/verify_packed.js

Reads `mozc_dict.json.source` / `mozc_costs.json.source` (this directory,
`build_mozc_engine.py`'s own output) and writes the fixed
`mozc_dict.json` / `mozc_costs.json` into rawfile/ for
`convert_to_binary.py` to pick up.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAWFILE = os.path.join(HERE, '..', '..', 'entry', 'src', 'main',
                       'resources', 'rawfile')


def to_hiragana(s):
    return ''.join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c
                   for c in s)


def is_all_hiragana(s):
    return bool(s) and all(0x3041 <= ord(c) <= 0x3096 or c in 'ーぁぃぅぇぉっゃゅょゎ'
                           for c in s)


def build_twin_map(classes):
    """katakana-base-form class id -> its hiragana-base-form twin id."""
    by_prefix = {}
    for cid, label in classes.items():
        if not label:
            continue
        fields = label.split(',')
        if len(fields) < 2:
            continue
        by_prefix.setdefault(tuple(fields[:-1]), []).append((cid, fields[-1]))
    twins = {}
    for group in by_prefix.values():
        if len(group) < 2:
            continue
        for cid, form in group:
            if form == to_hiragana(form):
                continue
            for other_cid, other_form in group:
                if other_cid != cid and other_form == to_hiragana(form):
                    twins[cid] = other_cid
                    break
    return twins


def main():
    with open(os.path.join(HERE, 'mozc_classes_reference.json'),
              encoding='utf-8') as f:
        raw = json.load(f)
    classes = ({int(k): v for k, v in raw.items()} if isinstance(raw, dict)
               else {i: v for i, v in enumerate(raw)})
    twins = build_twin_map(classes)
    print('katakana/hiragana class pairs: %d' % len(twins))

    with open(os.path.join(HERE, 'mozc_costs.json.source'), encoding='utf-8') as f:
        costs = json.load(f)
    with open(os.path.join(HERE, 'mozc_dict.json.source'), encoding='utf-8') as f:
        dicts = json.load(f)

    dropped = 0
    touched_readings = 0
    examples = []
    for reading, senses in costs.items():
        if not is_all_hiragana(reading):
            continue
        # Which twin (hiragana) classes have "this word is written in kana"
        # evidence for this reading?
        kana_written = set()
        for _cost, left, _right, surface in senses:
            if surface == reading:
                kana_written.add(left)
        if not kana_written:
            continue
        keep = []
        removed_surfaces = []
        for sense in senses:
            left = sense[1]
            twin = twins.get(left)
            if twin is not None and twin in kana_written:
                dropped += 1
                removed_surfaces.append(sense[3])
                if len(examples) < 12:
                    examples.append('%s: %s (cost=%d, %s)'
                                    % (reading, sense[3], sense[0], classes[left]))
                continue
            keep.append(sense)
        if len(keep) != len(senses):
            touched_readings += 1
            costs[reading] = keep
            # A surface with no surviving sense should not stay in the
            # candidate list either.
            still = {s[3] for s in keep}
            if reading in dicts:
                dicts[reading] = [s for s in dicts[reading]
                                  if s in still or s not in removed_surfaces]

    print('dropped %d senses across %d readings' % (dropped, touched_readings))
    for e in examples:
        print('   ' + e)

    os.makedirs(RAWFILE, exist_ok=True)
    with open(os.path.join(RAWFILE, 'mozc_costs.json'), 'w', encoding='utf-8') as f:
        json.dump(costs, f, ensure_ascii=False, separators=(',', ':'))
    with open(os.path.join(RAWFILE, 'mozc_dict.json'), 'w', encoding='utf-8') as f:
        json.dump(dicts, f, ensure_ascii=False, separators=(',', ':'))
    print('wrote mozc_costs.json / mozc_dict.json into rawfile/')


if __name__ == '__main__':
    sys.exit(main())
