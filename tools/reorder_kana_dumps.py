#!/usr/bin/env python3
"""Batch-reorder raw on-yomi/kun-yomi kanji dumps in dict.json.

Problem: dict.json has hundreds of short pure-hiragana keys (readings like
かん, さ, し) whose candidate list is a raw dump of every kanji with that
on-yomi/kun-yomi reading, in scrape order rather than frequency order --
e.g. かん -> ['簪','間','感','関',...], the obscure 簪 (hairpin) ahead of
the everyday 間. Since candidate[0] is what the IME shows by default for a
bare reading with no other context, scrape order actively hurts everyday
conversions.

Approach: rather than hand-typing a jouyou-kanji frequency-tier list (risk
of transcription error across ~2,000+ characters typed from memory), derive
a frequency signal directly from this project's own dictionaries: count how
often each kanji character occurs across every candidate string in
dict.json and global_dict.json combined. A kanji that shows up in thousands
of real compound words (人, 日, 大, 間...) is overwhelmingly likely to be
common; a kanji that shows up rarely or never elsewhere (簪, 蕃...) is
overwhelmingly likely to be rare. This is self-consistent with the exact
dictionaries being reordered and carries no manual-transcription risk.

Two earlier attempts were both found to cause real regressions during
validation (tools/ime-eval/regress.js), each traced to the same root cause:
global compound-occurrence frequency measures "how common is this kanji
character in general," not "how likely is THIS reading to actually mean
this kanji," and the two signals diverge often enough to be unsafe:

1. Sorting every single-kanji candidate by descending global frequency
   outright: 前 (freq ~3767, from 名前/午前/前回/...) badly outranks 先
   (freq ~1136) globally, but for the reading さき specifically, 先 is the
   idiomatic default and 前 is essentially never the intended word for a
   bare さき. This promoted 前/八/弥-style globally-common-but-wrong-for-
   this-reading kanji to rank 1 ahead of already-correctly-placed
   先/様/(kana echo).
2. Only ever demoting candidates below a frequency threshold (fixes #1,
   since it never re-ranks two "common enough" candidates against each
   other) still isn't safe at index 0 specifically: some genuinely common,
   already-correctly-first candidates have deceptively low compound
   frequency for their standalone commonness -- 錨 (いかり, "anchor", freq
   19), 絆 (きずな, "bond", freq 28), 痰 (たん, "phlegm", freq 23) -- and
   these sit in the *same numeric band* as genuinely obscure candidates
   this script exists to catch (簪 22, 罐 26, 疳 14). No frequency
   threshold can separate 痰 (23, keep) from 簪 (22, demote) -- they are
   frequency-adjacent. Only real lexical knowledge could, and a hand-typed
   exception list can't be trusted to be exhaustive across 500 entries.

Given that, this script now **never touches index 0** at all. Only
candidates from index 1 onward are eligible for demotion (below
RARE_THRESHOLD), in their original relative order; index 0 -- whatever the
existing default candidate is -- is left exactly as-is, unconditionally.
This makes it structurally impossible for this script to change the
candidate the IME shows by default for any of these ~500 readings, so
every regression class found above is categorically ruled out rather than
patched one exception at a time. The value that remains is real but more
modest: cleaning long-tail noise (JIS-extension/variant-form kanji) out of
the *alternate*-candidate list (what a user sees cycling past the default),
without ever risking the default itself. Where index 0 genuinely is wrong
(the original かん -> 簪 example), fixing it stays a manual, spot-checked
edit -- the same workflow already used for hundreds of other entries this
session -- rather than something this automated pass attempts. No
candidate is ever added or dropped either way -- pure reorder.

Usage:
  python3 tools/reorder_kana_dumps.py --report   # detect + report only (default)
  python3 tools/reorder_kana_dumps.py --apply    # write the reordered dict.json
"""
import argparse
import collections
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DICT_PATH = os.path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json')
GDICT_PATH = os.path.join(ROOT, 'entry/src/main/resources/rawfile/global_dict.json')
SRC_PATH = os.path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets')
REPORT_PATH = os.path.join(ROOT, 'tools', 'reorder_kana_dumps_report.txt')

KANJI_RE = re.compile(r'^[一-鿾々]$')  # single CJK ideograph or 々
HIRA_KEY_RE = re.compile(r'^[ぁ-ゖー]+$')  # pure hiragana (+ ー)

MIN_CANDIDATES = 10
MIN_KANJI_FRACTION = 0.65
RARE_THRESHOLD = 30   # global occurrence count below which a single-kanji
                       # candidate (at index 1+, see NEVER touch index 0
                       # below) is treated as long-tail noise and demoted.


def build_kanji_frequency(dict_data, gdict_data):
    freq = collections.Counter()
    for data in (dict_data, gdict_data):
        for candidates in data.values():
            for cand in candidates:
                for ch in cand:
                    if KANJI_RE.match(ch):
                        freq[ch] += 1
    return freq


def is_raw_dump(key, candidates):
    if not HIRA_KEY_RE.match(key) or len(key) > 3:
        return False
    if len(candidates) < MIN_CANDIDATES:
        return False
    single_kanji = sum(1 for c in candidates if len(c) == 1 and KANJI_RE.match(c))
    return (single_kanji / len(candidates)) >= MIN_KANJI_FRACTION


def reorder_candidates(candidates, freq):
    """Never touch index 0 (the default shown candidate). Among index 1+,
    demote long-tail-rare single-kanji candidates to the end (in their
    original relative order); everything else keeps its exact original
    relative order. See module docstring for why index 0 is off-limits."""
    if len(candidates) <= 1:
        return list(candidates)
    head, tail = candidates[0], candidates[1:]
    kept = []
    rare = []
    for c in tail:
        if len(c) == 1 and KANJI_RE.match(c) and freq.get(c, 0) < RARE_THRESHOLD:
            rare.append(c)
        else:
            kept.append(c)
    return [head] + kept + rare


def load_dictionary_shadow_keys():
    """Extract the set of keys defined in the inline DICTIONARY object
    literal in KanaKanjiConverter.ets (lines ~147-25246), which takes
    lookup priority over dict.json. Used only to annotate the report --
    reordering dict.json is harmless either way, but a shadowed key's
    reorder is cosmetic (invisible to the running app) while a
    non-shadowed key's reorder is live-impacting."""
    with open(SRC_PATH, encoding='utf-8') as f:
        lines = f.readlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith('const DICTIONARY: Record<string, string[]> = {'):
            start = i
            break
    if start is None:
        return set()
    keys = set()
    key_re = re.compile(r"^\s*'((?:[^'\\]|\\.)*)':\s*\[")
    for line in lines[start + 1:]:
        if line.startswith('};'):
            break
        m = key_re.match(line)
        if m:
            keys.add(m.group(1))
    return keys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true', help='write the reordered dict.json (default: report only)')
    args = ap.parse_args()

    with open(DICT_PATH, encoding='utf-8') as f:
        dict_data = json.load(f)
    with open(GDICT_PATH, encoding='utf-8') as f:
        gdict_data = json.load(f)

    freq = build_kanji_frequency(dict_data, gdict_data)
    shadow_keys = load_dictionary_shadow_keys()

    flagged = [(k, v) for k, v in dict_data.items() if is_raw_dump(k, v)]
    flagged.sort(key=lambda kv: kv[0])

    report_lines = []
    report_lines.append(f'{len(flagged)} flagged raw-dump entries '
                         f'(pure hiragana, len<=3, >={MIN_CANDIDATES} candidates, '
                         f'>={MIN_KANJI_FRACTION:.0%} single-kanji)\n')

    changed = 0
    for key, candidates in flagged:
        new_order = reorder_candidates(candidates, freq)
        shadowed = key in shadow_keys
        if new_order == candidates:
            continue
        changed += 1
        tag = 'shadowed — cosmetic only' if shadowed else 'live-impacting'
        report_lines.append(f'{key} [{tag}]')
        report_lines.append(f'  old: {candidates}')
        report_lines.append(f'  new: {new_order}')
        report_lines.append('')

    report_lines.insert(1, f'{changed} of those would actually change order\n')

    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report_lines))
    print(f'Report written to {REPORT_PATH}')
    print(f'{len(flagged)} flagged, {changed} would change order')

    if args.apply:
        for key, candidates in flagged:
            dict_data[key] = reorder_candidates(candidates, freq)
        with open(DICT_PATH, 'w', encoding='utf-8') as f:
            json.dump(dict_data, f, ensure_ascii=False, separators=(',', ':'))
        print(f'Applied: rewrote {DICT_PATH}')
    else:
        print('Report-only pass (pass --apply to write dict.json after review)')


if __name__ == '__main__':
    main()
