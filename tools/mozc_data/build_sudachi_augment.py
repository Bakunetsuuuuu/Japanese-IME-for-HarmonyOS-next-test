#!/usr/bin/env python3
"""
Augment track B's candidate-cycling vocabulary with SudachiDict's kanji
spellings, in the same safe mode as build_jmdict_augment.py: this script
ONLY appends extra surface candidates to READINGS THAT ALREADY EXIST in
the already-built mozc_dict.json -- it never adds a new reading key, and
never touches mozc_costs.json/mozc_matrix.json (the DP/Viterbi/
segmentation data). See build_jmdict_augment.py's module docstring for the
full explanation of why this scope specifically preserves the "never
changes DP/segmentation behavior" guarantee (inDict()'s gate on
mozcDict). Run this AFTER build_mozc_engine.py and build_jmdict_augment.py
(order between the two augmentation scripts doesn't matter -- both only
ever append new, not-already-present surfaces -- but both must follow
build_mozc_engine.py, which regenerates mozc_dict.json from scratch).

Why SudachiDict is vocabulary-only here, not a connection-matrix merge
------------------------------------------------------------------------
Unlike real mecab-ipadic (merged into the connection matrix directly, see
build_mozc_engine.py), SudachiDict's own leftId/rightId context space (5981
raw classes, from its own matrix.def) has no published id->POS-label
mapping of its own -- its docs state the ids are UniDic-mecab 2.1.2's
native numbering, but the actual UniDic 2.1.2 id.def (needed to reduce
those 5981 classes into this project's shared label-keyed registry the way
mozc's id.def and real ipadic's left-id.def were) is a separate NINJAL
distribution this pipeline does not have, and UniDic's POS-tagging
convention (short-unit words, different field granularity) is not
confirmed to align cleanly with the IPADIC-derived convention mozc/ipadic
already share. Attempting that merge without directly verifying the label
alignment (the same empirical discipline used before the ipadic matrix
merge, which caught a real calibration bug) would risk silently
mis-aligned classes -- worse than not merging. Restricting to vocabulary
augmentation (this file) captures real, low-risk value (a much larger,
actively-maintained lexicon than mozc's own dictionary_oss) without that
risk. If a future round obtains real UniDic 2.1.2 id.def data and verifies
label alignment, revisit a matrix merge then.

SudachiDict lexicon CSV format (19 fields; see the project's own
docs/file_format.md): index 4 is the entry's own display surface, index 11
is its reading in katakana, index 12 is its normalized (dictionary/base)
form. This script uses index 4 (the surface AS WRITTEN for that specific
reading), not index 12 (which would give the lemma/base form regardless of
the actual reading's conjugation) -- e.g. a conjugated verb form's own
surface, not its dictionary form, matching how mozc_dict.json's own
entries work (see build_dict_and_costs).

Only entries whose POS1 (index 5) is an open-class content-word category
are considered -- SudachiDict's lexicon also carries symbols, whitespace,
particles, and auxiliary verbs (which are not useful "kanji candidates"
for a reading, and would just add noise) -- and only entries whose surface
contains at least one non-ASCII character (filters out stray ASCII/symbol
entries like "$", "torr").

"small" + "core" lexicon tiers are used (not "notcore", the proper-noun-
heavy long tail -- see fetch_sudachi.py's module docstring for why).

Usage:
    python3 tools/mozc_data/build_sudachi_augment.py
"""
import json
import os
import re

HERE = os.path.dirname(__file__)
CACHE_SUDACHI = os.path.join(HERE, "cache_sudachi")
LEX_CSVS = ["small_lex.csv", "core_lex.csv"]
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAWFILE_DIR = os.path.join(ROOT, "entry/src/main/resources/rawfile")
MOZC_DICT_PATH = os.path.join(RAWFILE_DIR, "mozc_dict.json")

CONTENT_POS1 = {"名詞", "動詞", "形容詞", "副詞", "連体詞", "接頭辞", "接尾辞", "感動詞", "形状詞"}
NON_ASCII_RE = re.compile(r"[^\x00-\x7f]")

MAX_TOTAL_CANDIDATES = 40
MAX_NEW_PER_READING = 12


def kata_to_hira(s: str) -> str:
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def iter_reading_to_surface(path: str):
    with open(path, encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split(",")
            if len(fields) != 19:
                continue
            surface, pos1, reading_kata = fields[4], fields[5], fields[11]
            if pos1 not in CONTENT_POS1:
                continue
            if not NON_ASCII_RE.search(surface):
                continue
            reading = kata_to_hira(reading_kata)
            yield reading, surface


def main() -> None:
    csv_paths = [os.path.join(CACHE_SUDACHI, name) for name in LEX_CSVS]
    if not all(os.path.isfile(p) for p in csv_paths):
        print(f"no cache_sudachi/*.csv -- run fetch_sudachi.py first, skipping augmentation.")
        return
    if not os.path.isfile(MOZC_DICT_PATH):
        raise SystemExit(f"{MOZC_DICT_PATH} not found -- run build_mozc_engine.py first.")

    with open(MOZC_DICT_PATH, encoding="utf-8") as f:
        mozc_dict = json.load(f)

    print(f"scanning SudachiDict small+core lexicon for readings already in "
          f"mozc_dict.json ({len(mozc_dict)} candidate readings)...")

    # reading -> ordered list of new surfaces seen (append order = file
    # order = roughly lexicon-internal order; no cost/frequency data to sort
    # by, unlike mozc's own entries).
    additions: dict = {}
    entries_scanned = 0
    for path in csv_paths:
        for reading, surface in iter_reading_to_surface(path):
            entries_scanned += 1
            if reading not in mozc_dict:
                continue
            additions.setdefault(reading, []).append(surface)

    readings_touched = 0
    surfaces_added = 0
    for reading, cands in additions.items():
        existing = mozc_dict[reading]
        existing_set = set(existing)

        new_surfaces = []
        seen_new = set()
        for surface in cands:
            if surface in existing_set or surface in seen_new:
                continue
            seen_new.add(surface)
            new_surfaces.append(surface)
            if len(new_surfaces) >= MAX_NEW_PER_READING:
                break

        if not new_surfaces:
            continue
        room = MAX_TOTAL_CANDIDATES - len(existing)
        if room <= 0:
            continue
        new_surfaces = new_surfaces[:room]

        mozc_dict[reading] = existing + new_surfaces
        readings_touched += 1
        surfaces_added += len(new_surfaces)

    print(f"  scanned {entries_scanned:,} content-word lexicon rows")
    print(f"  augmented {readings_touched:,} readings, "
          f"+{surfaces_added:,} candidate surfaces total")

    with open(MOZC_DICT_PATH, "w", encoding="utf-8") as f:
        json.dump(mozc_dict, f, ensure_ascii=False, separators=(",", ":"))
    print(f"  wrote {os.path.getsize(MOZC_DICT_PATH):,} bytes -> {MOZC_DICT_PATH}")


if __name__ == "__main__":
    main()
