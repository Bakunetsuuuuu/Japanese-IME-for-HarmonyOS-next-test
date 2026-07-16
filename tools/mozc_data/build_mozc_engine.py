#!/usr/bin/env python3
"""
Build the "track B" mozc-derived conversion engine data from the raw files
fetched by fetch_mozc.py, and write the small derived assets this app ships.

Inputs (tools/mozc_data/cache/, populated by fetch_mozc.py):
  - dictionary00.txt .. dictionary09.txt  (reading \t leftId \t rightId \t cost \t surface)
  - id.def                                ("<id> <pos1>,<pos2>,...,<pos7>")
  - connection_single_column.txt          (first line N; then N*N cost ints,
                                            row-major, connection[left][right])

Class reduction
----------------
mozc's raw POS space has 2,672 ids (id.def), which is far more granular than
useful for a from-scratch reduced connection matrix here. We fold ids into
"reduced classes" by grouping on their first SIX comma-separated POS fields
(major POS, two POS subtypes, conjugation TYPE, conjugation FORM) and
dropping only the seventh field (the literal lexeme, e.g. which specific
auxiliary a suffix attaches to -- mostly "*" anyway). This keeps the
grammatically load-bearing distinction the hand-written engine structurally
lacks -- verb/adjective CONJUGATION FORM (未然形/連用形/仮定形/...), which
drives most of real Japanese connection grammar -- while still cutting
2,672 raw ids down to ~585 reduced classes. See mozc_classes_reference.json
(not shipped in the app; kept here for maintainers) for the id->group
mapping actually produced.

Reduced connection costs are the mean of all underlying raw (left, right)
cell costs falling in each (reducedLeft, reducedRight) bucket. This is a
simplification -- mozc's raw matrix also encodes hard "this connection is
impossible" cells via a large sentinel cost, and averaging softens those --
but it is deterministic, reproducible from the source data, and requires no
hand-tuning, which is the entire point of this track (see the plan doc).

Known data quirk (intentionally left as-is)
---------------------------------------------
Because this track deliberately ships mozc's own statistics unmodified (see
the plan doc: track A stays the hand-tuned dictionary, track B is meant to
be a genuine, un-hand-patched second opinion), some per-reading top picks
reflect mozc's own cost model rather than "what a casual user usually
means." E.g. かん's cheapest entry is 澗 (cost 0, POS 名詞,数,漢数字 --
mozc gives cost 0 to kanji-numeral counter units the same way it does to
function words), ahead of the far more commonly-intended 間/感/関. This is
not a bug in this pipeline; it is mozc's real data. Leaving it alone is the
point of having an independent second engine. If this specific class of
counter-unit skew turns out to matter in practice, revisit with a narrow,
documented filter -- but do not start a general hand-patching loop here,
that is what track A is for.

Node cost / class per reading
-------------------------------
The Viterbi DP in KanaKanjiConverter.segment() calls getWordInfo(sub) for a
reading SPAN and gets back one [nodeCost, leftClass, rightClass] triple --
it is not aware of which candidate surface will eventually be chosen. So for
each reading we take the single cheapest (cost, leftId, rightId) entry
across every dictionary row sharing that reading as this engine's node-cost
signal; candidate SURFACES for that reading (mozc_dict.json) are still every
surface mozc has for it, ordered by ascending cost.

Outputs (entry/src/main/resources/rawfile/, shipped in the app):
  - mozc_dict.json    { reading: [surface, ...] }            ascending cost
  - mozc_costs.json   { reading: [nodeCost, leftClass, rightClass] }
  - mozc_matrix.json  { size: N, matrix: [cost, ...] }        N*N, row-major

Usage:
    python3 tools/mozc_data/build_mozc_engine.py
"""
import json
import os

import numpy as np

HERE = os.path.dirname(__file__)
CACHE = os.path.join(HERE, "cache")
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAWFILE_DIR = os.path.join(ROOT, "entry/src/main/resources/rawfile")

DICT_SHARDS = [f"dictionary{i:02d}.txt" for i in range(10)]
GROUP_FIELDS = 6  # POS fields to keep when reducing (drop only the 7th: lexeme)

# mozc's raw dictionary has 745,964 distinct readings -- far more than a
# phone IME needs (the existing hand-built dict.json has 78,562 keys;
# global_dict.json, the largest existing shipped asset, has 280,351 and is
# 12.9MB). mozc cost is inversely related to frequency, so we prune the very
# rare/obscure tail by cost and cap per-reading candidate count (median is 1
# candidate/reading, so this mainly trims pathological outliers like a
# single mora with 261 homophone-kanji candidates -- the same class of
# scrape-order noise track A's reorder_kana_dumps.py cleans up separately).
# MAX_COST=6000 keeps ~138k readings (18.5% of the raw set, empirically
# checked against the cost percentile table) -- comparable in scale to the
# existing hand-built dict.json (78,562 keys) while cutting the bulk of the
# long, rarely-typed tail (obscure place names, technical terms). Raise this
# if validation (tools/ime-eval) shows real coverage gaps.
MAX_COST = 6000
MAX_CANDIDATES_PER_READING = 30


def load_id_def():
    """Returns (raw_id -> full pos fields list, raw_id -> reduced_class_id, num_reduced)."""
    raw_pos = {}
    with open(os.path.join(CACHE, "id.def"), encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            rid_str, pos = line.split(" ", 1)
            raw_pos[int(rid_str)] = pos.split(",")

    group_key_to_reduced = {}
    raw_to_reduced = {}
    for rid in sorted(raw_pos):
        key = ",".join(raw_pos[rid][:GROUP_FIELDS])
        if key not in group_key_to_reduced:
            group_key_to_reduced[key] = len(group_key_to_reduced)
        raw_to_reduced[rid] = group_key_to_reduced[key]

    return raw_pos, raw_to_reduced, group_key_to_reduced


def build_reduced_matrix(raw_to_reduced: dict, num_reduced: int) -> np.ndarray:
    path = os.path.join(CACHE, "connection_single_column.txt")
    with open(path, encoding="utf-8") as f:
        n = int(f.readline())
        raw = np.loadtxt(f, dtype=np.int64)
    assert raw.size == n * n, f"expected {n*n} costs, got {raw.size}"
    raw_matrix = raw.reshape(n, n)

    # raw_to_reduced as an array for vectorized bincount-based grouping.
    r2r = np.zeros(n, dtype=np.int64)
    for rid, red in raw_to_reduced.items():
        r2r[rid] = red

    # MIN (not mean) over each (reducedLeft, reducedRight) bucket. Tried mean
    # first; it systematically broke very common, grammatically central
    # connections -- e.g. 名詞(noun) -> です(copula) reduced-cost came out
    # *worse* than 名詞->で (a much rarer continuation) purely because です's
    # reduced group also absorbed some unrelated, costlier raw sub-variants,
    # dragging the average up. Each reduced group here is deliberately
    # fine-grained (POS + conjugation form, see GROUP_FIELDS), so within a
    # group the raw sub-variants are already grammatically near-identical --
    # taking the cheapest one is a reasonable "this connection IS good in at
    # least one real realization" signal rather than diluting it with worse
    # siblings. Concretely verified fixing 名詞+です vs 名詞+で after this
    # change (was mis-segmenting いいてんき+です+ね as いいてんき+で+すね).
    left_reduced = r2r[:, None] * num_reduced  # (n,1)
    right_reduced = r2r[None, :]  # (1,n)
    flat_idx = (left_reduced + right_reduced).reshape(-1)

    mins = np.full(num_reduced * num_reduced, raw_matrix.max(), dtype=np.int64)
    np.minimum.at(mins, flat_idx, raw_matrix.reshape(-1))
    return mins.reshape(num_reduced, num_reduced)


def build_dict_and_costs(raw_to_reduced: dict, raw_pos: dict):
    # reading -> list of (cost, surface), append order preserved for stable tie-break
    per_reading = {}
    for shard in DICT_SHARDS:
        path = os.path.join(CACHE, shard)
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 5:
                    continue
                reading, left_id, right_id, cost, surface = parts
                try:
                    left_id = int(left_id)
                    right_id = int(right_id)
                    cost = int(cost)
                except ValueError:
                    continue
                per_reading.setdefault(reading, []).append((cost, left_id, right_id, surface))

    mozc_dict = {}
    mozc_costs = {}
    for reading, entries in per_reading.items():
        entries.sort(key=lambda e: e[0])  # ascending cost, stable
        # Prefer the cheapest entry whose sense ISN'T 文語 (classical/literary
        # Japanese) for the node-cost/class representative, if a modern sense
        # is available at all. getWordInfo(sub) collapses every sense sharing
        # a reading down to one representative (cost, class) triple -- it has
        # no idea which literal candidate the caller will eventually pick --
        # so when a reading has both a modern and a classical sense (e.g. し:
        # modern する-stem vs. classical auxiliary き's conjugated form), and
        # the classical one happens to be cheaper, blindly taking the global
        # min silently made the whole engine model 1200+ years out of date
        # for that reading's edge-cost behavior (verified case: じゅんびした
        # mis-segmenting because classical し didn't connect naturally after
        # a noun the way modern し does). This is a generic, POS-driven
        # filter, not a per-word patch -- it applies uniformly to every
        # reading with this classical/modern ambiguity, not just this one.
        best_cost, best_left, best_right, _ = entries[0]
        if best_cost > MAX_COST:
            continue  # prune the long rare/obscure tail (see MAX_COST comment above)
        for cost, left_id, right_id, _ in entries:
            if cost > MAX_COST:
                break
            if '文語' not in ','.join(raw_pos[left_id]):
                best_cost, best_left, best_right = cost, left_id, right_id
                break

        seen = set()
        surfaces = []
        for cost, _, _, surface in entries:
            if surface in seen:
                continue
            seen.add(surface)
            surfaces.append(surface)
            if len(surfaces) >= MAX_CANDIDATES_PER_READING:
                break
        mozc_dict[reading] = surfaces
        mozc_costs[reading] = [best_cost, raw_to_reduced[best_left], raw_to_reduced[best_right]]

    return mozc_dict, mozc_costs


def main():
    print("loading id.def and reducing POS classes...")
    raw_pos, raw_to_reduced, group_key_to_reduced = load_id_def()
    num_reduced = len(group_key_to_reduced)
    print(f"  {len(raw_pos)} raw ids -> {num_reduced} reduced classes")

    print("building reduced connection matrix (this takes a bit)...")
    matrix = build_reduced_matrix(raw_to_reduced, num_reduced)
    print(f"  matrix shape: {matrix.shape}")

    # segment()'s Viterbi DP (KanaKanjiConverter.ets) needs two extra things
    # this matrix alone doesn't carry:
    #  - a BOS/EOS class to seed the sentence-boundary edge cost (mirrors
    #    track A's VC_BOS) -- this is just raw id 0's own reduced class,
    #    already produced by the grouping above, nothing extra to compute.
    #  - an UNKNOWN class for single characters with no dictionary entry
    #    (mirrors track A's VC_UNKNOWN) -- id.def has no such catch-all
    #    entry (mozc handles OOV via a separate mechanism this pipeline
    #    doesn't pull in), so we append one synthetic extra
    #    class/row/column whose connection cost to everything is a fixed,
    #    strongly-discouraging value (the observed max cost in the reduced
    #    matrix), so it only ever wins the DP when nothing real fits --
    #    the same role VN_UNKNOWN_SINGLE/VC_UNKNOWN play in track A.
    bos_class = raw_to_reduced[0]
    unknown_class = num_reduced
    discourage_cost = int(matrix.max())
    padded = np.full((num_reduced + 1, num_reduced + 1), discourage_cost, dtype=np.int64)
    padded[:num_reduced, :num_reduced] = matrix
    matrix = padded
    num_reduced += 1
    print(f"  + BOS/EOS class {bos_class}, + synthetic UNKNOWN class {unknown_class} "
          f"(discourage cost {discourage_cost}) -> final size {num_reduced}")

    print("parsing dictionary shards and building dict/costs tables...")
    mozc_dict, mozc_costs = build_dict_and_costs(raw_to_reduced, raw_pos)
    print(f"  {len(mozc_dict)} distinct readings")

    os.makedirs(RAWFILE_DIR, exist_ok=True)
    with open(os.path.join(RAWFILE_DIR, "mozc_dict.json"), "w", encoding="utf-8") as f:
        json.dump(mozc_dict, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(RAWFILE_DIR, "mozc_costs.json"), "w", encoding="utf-8") as f:
        json.dump(mozc_costs, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(RAWFILE_DIR, "mozc_matrix.json"), "w", encoding="utf-8") as f:
        json.dump({
            "size": num_reduced,
            "bosClass": bos_class,
            "unknownClass": unknown_class,
            "matrix": matrix.reshape(-1).tolist(),
        }, f, separators=(",", ":"))

    # Reference-only (not shipped in the app): reduced-class id -> label, for
    # maintainers who want to inspect what a given class id means.
    reduced_labels = [None] * num_reduced
    for key, red in group_key_to_reduced.items():
        reduced_labels[red] = key
    with open(os.path.join(HERE, "mozc_classes_reference.json"), "w", encoding="utf-8") as f:
        json.dump(reduced_labels, f, ensure_ascii=False, indent=1)

    for name in ("mozc_dict.json", "mozc_costs.json", "mozc_matrix.json"):
        path = os.path.join(RAWFILE_DIR, name)
        print(f"  {name}: {os.path.getsize(path):,} bytes")

    print("done.")


if __name__ == "__main__":
    main()
