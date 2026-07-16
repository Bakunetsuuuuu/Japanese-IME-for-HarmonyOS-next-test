#!/usr/bin/env python3
"""
Augment track B's candidate-cycling vocabulary with JMdict's kanji spellings,
in safe mode only: this script ONLY appends extra surface candidates to
READINGS THAT ALREADY EXIST in the already-built mozc_dict.json -- it never
adds a new reading key. mozc_costs.json and mozc_matrix.json (the DP/
Viterbi/segmentation data) are not touched at all.

Why this scope, specifically
-----------------------------
segment()'s DP (KanaKanjiConverter.ets) gates multi-character spans on
inDict(sub), which for track B checks mozcDict directly (see inDict's own
comment). If this script added brand-new reading keys, those spans would
newly become DP-eligible (falling back to the generic UNKNOWN-class
discourage cost in getWordInfoCandidatesMozc, since mozc_costs.json
wouldn't have a real entry for them) -- a real, if minor, change to
segmentation behaviour for sentences containing those readings. Restricting
this script to readings mozc_dict.json already has avoids that entirely:
inDict/getWordInfoCandidatesMozc/segment()'s DP see exactly the same set of
DP-eligible spans as before this script ever runs. Only lookup()/
lookupMozc()'s candidate LIST for an already-recognised reading grows --
e.g. cycling candidates for a reading typed and converted on its own. This
is what "safe mode" means throughout this file and in tools/mozc_data/README.md.

Run this AFTER build_mozc_engine.py (which must be re-run first if mozc's
or ipadic's source data changes -- it always regenerates mozc_dict.json
from scratch, discarding any previous augmentation) and AFTER
fetch_jmdict.py has populated cache_jmdict/JMdict.xml.

JMdict format notes
--------------------
Each <entry> has zero or more <k_ele><keb> (kanji spellings) and one or
more <r_ele><reb> (readings). An <r_ele> applies to every <k_ele> unless it
has one or more <re_restr> children, in which case it only applies to the
listed keb(s). Priority markers (<ke_pri>/<re_pri>: news1/ichi1/spec1/
spec2/gai1, roughly "common word" tags) are used here purely to order
JMdict's own appended candidates among themselves (most-common first) --
JMdict carries no cost/frequency number the way mozc's dictionary does.

Entries with no k_ele at all (pure-kana words) are skipped: this script
only ever adds KANJI candidates, never touches which reading keys exist.

Usage:
    python3 tools/mozc_data/build_jmdict_augment.py
"""
import json
import os
import xml.etree.ElementTree as ET

HERE = os.path.dirname(__file__)
CACHE_JMDICT = os.path.join(HERE, "cache_jmdict")
JMDICT_XML = os.path.join(CACHE_JMDICT, "JMdict.xml")
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAWFILE_DIR = os.path.join(ROOT, "entry/src/main/resources/rawfile")
MOZC_DICT_PATH = os.path.join(RAWFILE_DIR, "mozc_dict.json")

PRIORITY_TAGS = {"news1", "ichi1", "spec1", "spec2", "gai1"}

# Overall cap on candidates per reading after augmentation, so a reading
# with an unusually large number of JMdict kanji variants (rare, but some
# hiragana readings shared by many obscure kanji exist) doesn't balloon the
# candidate-cycling list past what's actually useful to page through.
MAX_TOTAL_CANDIDATES = 40
# Cap on how many NEW (not already present) surfaces this script appends
# per reading, independent of the overall cap above -- keeps any single
# reading's JMdict contribution bounded even for readings starting from a
# small existing candidate count.
MAX_NEW_PER_READING = 12


def iter_reading_to_kanji(path: str):
    """Yields (reading, keb, is_priority) for every kanji spelling JMdict
    associates with every reading, entry by entry (streaming, low memory)."""
    context = ET.iterparse(path, events=("end",))
    for _event, elem in context:
        if elem.tag != "entry":
            continue
        try:
            k_eles = elem.findall("k_ele")
            if not k_eles:
                continue  # pure-kana entry, nothing to add
            kebs = []
            for k in k_eles:
                keb = k.findtext("keb")
                if not keb:
                    continue
                is_pri = any(p.text in PRIORITY_TAGS for p in k.findall("ke_pri"))
                kebs.append((keb, is_pri))
            keb_set = {keb for keb, _ in kebs}

            for r in elem.findall("r_ele"):
                reb = r.findtext("reb")
                if not reb:
                    continue
                restr = {e.text for e in r.findall("re_restr")}
                applicable = [(keb, is_pri) for keb, is_pri in kebs
                              if not restr or keb in restr]
                for keb, is_pri in applicable:
                    yield reb, keb, is_pri
        finally:
            elem.clear()


def main() -> None:
    if not os.path.isfile(JMDICT_XML):
        print(f"no {JMDICT_XML} -- run fetch_jmdict.py first, skipping augmentation.")
        return
    if not os.path.isfile(MOZC_DICT_PATH):
        raise SystemExit(f"{MOZC_DICT_PATH} not found -- run build_mozc_engine.py first.")

    with open(MOZC_DICT_PATH, encoding="utf-8") as f:
        mozc_dict = json.load(f)

    print(f"scanning {JMDICT_XML} for readings already in mozc_dict.json "
          f"({len(mozc_dict)} candidate readings)...")

    # reading -> list of (keb, is_priority), collected only for readings
    # mozc_dict already has (this is the "safe mode" restriction -- see
    # module docstring).
    additions: dict = {}
    entries_scanned = 0
    for reading, keb, is_pri in iter_reading_to_kanji(JMDICT_XML):
        entries_scanned += 1
        if reading not in mozc_dict:
            continue
        additions.setdefault(reading, []).append((keb, is_pri))

    readings_touched = 0
    surfaces_added = 0
    for reading, cands in additions.items():
        existing = mozc_dict[reading]
        existing_set = set(existing)
        # Priority-tagged kanji spellings first among JMdict's own additions,
        # append order preserved otherwise (stable within each priority tier).
        cands.sort(key=lambda c: 0 if c[1] else 1)

        new_surfaces = []
        seen_new = set()
        for keb, _is_pri in cands:
            if keb in existing_set or keb in seen_new:
                continue
            seen_new.add(keb)
            new_surfaces.append(keb)
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

    print(f"  scanned {entries_scanned:,} reading/kanji pairs")
    print(f"  augmented {readings_touched:,} readings, "
          f"+{surfaces_added:,} candidate surfaces total")

    with open(MOZC_DICT_PATH, "w", encoding="utf-8") as f:
        json.dump(mozc_dict, f, ensure_ascii=False, separators=(",", ":"))
    print(f"  wrote {os.path.getsize(MOZC_DICT_PATH):,} bytes -> {MOZC_DICT_PATH}")


if __name__ == "__main__":
    main()
