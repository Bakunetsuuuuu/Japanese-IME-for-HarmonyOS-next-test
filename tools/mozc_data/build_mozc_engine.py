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

Reduced connection costs are the MIN (not mean -- mean was tried first and
reverted, see build_reduced_matrix's own comment for the concrete case that
broke) of all underlying raw (left, right) cell costs falling in each
(reducedLeft, reducedRight) bucket. This is a simplification -- mozc's raw
matrix also encodes hard "this connection is impossible" cells via a large
sentinel cost -- but it is deterministic, reproducible from the source
data, and requires no hand-tuning, which is the entire point of this track
(see the plan doc).

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

Node cost / class per reading -- MULTIPLE senses, not one
-----------------------------------------------------------
Earlier versions of this pipeline collapsed every dictionary entry sharing a
reading down to a single representative (cost, leftClass, rightClass)
triple (the global cheapest). That was found to be the primary cause of
track B's poor connected-sentence accuracy: many readings genuinely have
several distinct senses with different grammatical roles (e.g. し is both
する's 連用形 -- a verb continuation, cheap after a サ変 noun like 準備 --
and a classical/literary auxiliary conjugated form -- a completely
different, much rarer continuation). Collapsing to one triple picks
whichever sense happened to be cheapest in isolation, with no way for
segment()'s Viterbi DP to ever consider the other -- concretely, this
caused じゅんびした ("prepared") to mis-segment as 準備+した(→下) instead of
準備+し+た, because the wrong sense of し won the single-representative slot.

mozc_costs.json now stores every DISTINCT (reducedLeftClass, reducedRightClass)
sense a reading has, not just the cheapest overall: entries are grouped by
that class pair, the cheapest cost within each pair is kept (ties within the
same grammatical role don't matter -- only cross-role ambiguity does), capped
at MAX_SENSES_PER_READING senses (sorted by ascending cost, so cheapest/most
representative senses are kept if a reading somehow has more distinct roles
than the cap). segment()'s DP (KanaKanjiConverter.ets) now tries every sense
of a span and lets normal Viterbi cost minimization pick whichever actually
fits the surrounding context -- exactly what a real sense-aware tokenizer
does, and no per-word tie-breaking heuristic (like the earlier 文語-avoidance
filter this replaces) is needed anymore: a classical sense simply loses to a
modern one whenever the modern one's edge cost is genuinely better in
context, and can still win in the rare case it's actually intended.

Each sense also carries its own literal `surface` (not just an index into
mozc_dict.json) so that once the DP picks a specific sense for a span, the
caller can show the RIGHT surface for that sense (e.g. 為 for the する-stem
reading of し) rather than mozc_dict[reading][0] (whichever surface is
cheapest for the reading in general, regardless of which sense was chosen --
see KanaKanjiConverter.ets's mozcLastHints).

Connection matrix: merged with real ipadic, not mozc alone
-------------------------------------------------------------
mozc's dictionary_oss is itself IPAdic-derived (see mozc's own
dictionary_oss/README.txt), but its connection-cost matrix
(connection_single_column.txt) turns out NOT to be stock ipadic's own
matrix -- mozc's authors re-trained/re-costed it. Direct comparison against
the real mecab-ipadic source (github.com/taku910/mecab, mecab-ipadic/,
fetched by fetch_ipadic.py -- same NAIST/ICOT license already documented in
../../THIRD_PARTY_NOTICES.md, mozc's own dictionary source lineage) found
mozc's re-training made at least one extremely common, basic grammar
pattern noticeably WORSE: する's 連用形 (conjunctive stem, e.g. the し in
した) connecting to た (past-tense auxiliary) costs 859 in mozc's matrix but
-7956 (i.e. strongly preferred) in real ipadic's matrix.def. Both matrices
are built into the shared reduced-class space (see load_id_def/
build_reduced_class_registry below -- mozc's id.def and ipadic's
left-id.def use the same POS-label-string convention despite different raw
numeric id spaces, so classes align by label, not by number) and merged
with MIN, so a connection gets whichever source found it cheaper. mozc's
own word list / node costs are NOT touched by this merge -- only the
connection (edge-cost) matrix mixes in ipadic's data; see the module
docstring's "Node cost / class per reading" section for why dictionary-side
merging was deliberately NOT attempted this round (mozc's and ipadic's raw
cost scales are not directly comparable -- see the same reading's cost in
each source differing by 1-2 orders of magnitude in spot checks -- and
naively pooling both sources' entries into one cost-sorted list would let
that scale mismatch silently bias which sense wins, which is a worse
failure mode than not merging at all).

Outputs (entry/src/main/resources/rawfile/, shipped in the app). Note this
script always regenerates mozc_dict.json from scratch -- run
build_jmdict_augment.py and/or build_sudachi_augment.py afterward (see
tools/mozc_data/README.md) to re-apply their candidate-surface
augmentation from JMdict/SudachiDict if that's wanted:
  - mozc_dict.json    { reading: [surface, ...] }            ascending cost
  - mozc_costs.json   { reading: [[cost, leftClass, rightClass, surface], ...] }
                        one entry per distinct (leftClass, rightClass) sense,
                        ascending cost, capped at MAX_SENSES_PER_READING
  - mozc_matrix.json  { size: N, matrix: [cost, ...],          N*N, row-major
                         contentClassMask: [0|1, ...] }        length N, see
                        compute_content_class_mask below (single-mora content-
                        word senses get a segment()-side penalty, mirroring
                        track A's singleContentPenalty; a real 1-char
                        particle/auxiliary sense must NOT be penalized)

Usage:
    python3 tools/mozc_data/build_mozc_engine.py
"""
import json
import os

import numpy as np

HERE = os.path.dirname(__file__)
CACHE = os.path.join(HERE, "cache")
CACHE_IPADIC = os.path.join(HERE, "cache_ipadic")
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
# Most readings only have one grammatical sense (median distinct-class-pair
# count is 1), so this cap mainly bounds the rare, genuinely ambiguous
# readings (particles/auxiliaries like し, で, た that serve multiple
# grammatical roles) -- keeps mozc_costs.json from growing large while still
# giving segment()'s DP real alternatives to choose from for exactly the
# readings that need it.
MAX_SENSES_PER_READING = 6


def load_id_def(path: str, encoding: str, group_key_to_reduced: dict):
    """Parses an id.def-style file ("<id> <pos1>,<pos2>,...,<posN>" per
    line) and folds ids into reduced classes by their first GROUP_FIELDS POS
    columns. `group_key_to_reduced` is a SHARED registry across sources
    (mozc's id.def and ipadic's left-id.def both use the same POS-label
    convention despite disjoint raw numeric id spaces) -- mutated in place
    so a class key already assigned an id by one source is reused by the
    other, and any source-only key gets a newly appended id.
    Returns (raw_id -> full pos fields list, raw_id -> reduced_class_id).
    """
    raw_pos = {}
    with open(path, encoding=encoding) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            rid_str, pos = line.split(" ", 1)
            raw_pos[int(rid_str)] = pos.split(",")

    raw_to_reduced = {}
    for rid in sorted(raw_pos):
        key = ",".join(raw_pos[rid][:GROUP_FIELDS])
        if key not in group_key_to_reduced:
            group_key_to_reduced[key] = len(group_key_to_reduced)
        raw_to_reduced[rid] = group_key_to_reduced[key]

    return raw_pos, raw_to_reduced


def _reduce_matrix(raw_matrix: np.ndarray, raw_to_reduced: dict, num_reduced: int) -> np.ndarray:
    """MIN-aggregates a raw n*n connection matrix into num_reduced*num_reduced
    reduced classes. See build_mozc_engine.py's module docstring for why MIN
    (not mean). Cells with no underlying raw data default to this source's
    own max (a neutral "unknown, don't prefer" filler) -- callers merging
    multiple sources' reduced matrices via MIN naturally let a source that
    DOES have real data for a cell override this filler.
    """
    n = raw_matrix.shape[0]
    r2r = np.zeros(n, dtype=np.int64)
    for rid, red in raw_to_reduced.items():
        r2r[rid] = red
    left_reduced = r2r[:, None] * num_reduced
    right_reduced = r2r[None, :]
    flat_idx = (left_reduced + right_reduced).reshape(-1)

    mins = np.full(num_reduced * num_reduced, raw_matrix.max(), dtype=np.int64)
    np.minimum.at(mins, flat_idx, raw_matrix.reshape(-1))
    return mins.reshape(num_reduced, num_reduced)


def build_reduced_matrix(raw_to_reduced: dict, num_reduced: int):
    path = os.path.join(CACHE, "connection_single_column.txt")
    with open(path, encoding="utf-8") as f:
        n = int(f.readline())
        raw = np.loadtxt(f, dtype=np.int64)
    assert raw.size == n * n, f"expected {n*n} costs, got {raw.size}"
    raw_matrix = raw.reshape(n, n)
    return _reduce_matrix(raw_matrix, raw_to_reduced, num_reduced), float(np.median(raw_matrix))


def build_ipadic_reduced_matrix(raw_to_reduced: dict, num_reduced: int, target_median: float) -> np.ndarray:
    # matrix.def is sparse (left, right, cost) triples, one per line, first
    # line "leftSize rightSize" -- unlike mozc's flat row-major dump.
    path = os.path.join(CACHE_IPADIC, "matrix.def")
    with open(path, encoding="ascii") as f:
        dims = f.readline().split()
        n = int(dims[0])
        triples = np.loadtxt(f, dtype=np.int64)
    raw_matrix = np.zeros((n, n), dtype=np.int64)
    raw_matrix[triples[:, 0], triples[:, 1]] = triples[:, 2]
    # Calibration: real ipadic uses mecab's native convention (median ~-115,
    # negative = strongly preferred); mozc shifted its own matrix to be
    # entirely non-negative (median ~8157) during their own re-training/
    # export. Merging the two raw scales directly was tried first and made
    # things dramatically worse (corpus_test10 strict dropped from 20% to
    # 5%) -- ipadic's very negative values made large swaths of the DP
    # artificially cheap regardless of whether the actual span/context made
    # sense, overwhelming node-cost signal from mozc's own (differently
    # scaled) dictionary. Shifting ipadic's raw values by a constant so its
    # median matches mozc's puts both sources on a comparable footing before
    # the per-cell MIN merge, while still preserving *relative* differences
    # within ipadic's own data (a connection ipadic rates unusually cheap
    # relative to its own distribution stays unusually cheap relative to
    # mozc's after the shift).
    ipadic_raw_median = float(np.median(raw_matrix))
    calibration_offset = round(target_median - ipadic_raw_median)
    print(f"  ipadic matrix calibration offset: {calibration_offset:+d} "
          f"(raw median {ipadic_raw_median:.0f} -> target {target_median:.0f})")
    raw_matrix = raw_matrix + calibration_offset
    return _reduce_matrix(raw_matrix, raw_to_reduced, num_reduced)


# Major POS categories (id.def's first comma field) that are open-class
# content words. A single mora almost always has SOME dictionary entry
# (mozc has raw kanji-homophone dumps for hiragana moras just like the
# hand-built dict.json did before tools/reorder_kana_dumps.py cleaned it up
# -- see that script's history), so a lone content-word sense stealing a
# 1-character span from what should be a longer word/phrase is a frequent,
# generic failure mode, not a per-word quirk. track A charges exactly this
# situation a flat singleContentPenalty (KanaKanjiConverter.ets
# getWordInfo); track B's multi-sense senses need the same treatment,
# applied only to content classes -- a real function word/particle sense
# (助詞/助動詞/接続詞/フィラー/記号/感動詞/BOS-EOS/その他) is often
# GENUINELY one character (は/を/に/で/と/し/た/...) and must stay cheap.
#
# 動詞 (verbs) deliberately excluded, unlike track A's blanket
# singleContentPenalty: a short verb span is very often a genuine
# CONJUGATED STEM used as light-verb glue (じゅんびした = 準備(noun) +
# し(する's 連用形, exactly 1-2 characters) + た), not homophone noise the
# way a short bare noun usually is. Penalizing 動詞 here was tried and
# empirically made things worse (corpus_test10 strict dropped from 30% to
# 20%, re-breaking じゅんびした specifically) -- verified before reverting,
# not assumed.
CONTENT_POS_MAJOR = {"名詞", "形容詞", "副詞", "連体詞", "接頭詞"}


def compute_content_class_mask(group_key_to_reduced: dict, num_reduced: int) -> list:
    mask = [0] * num_reduced
    for key, reduced_id in group_key_to_reduced.items():
        major = key.split(",", 1)[0]
        if major in CONTENT_POS_MAJOR:
            mask[reduced_id] = 1
    return mask


def build_dict_and_costs(raw_to_reduced: dict):
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
        if entries[0][0] > MAX_COST:
            continue  # prune the long rare/obscure tail (see MAX_COST comment above)

        # One sense per distinct (reducedLeftClass, reducedRightClass) pair,
        # up to MAX_SENSES_PER_READING -- see the module docstring's "Node
        # cost / class per reading" section for why this replaced the old
        # single-representative-triple design.
        #
        # Within a class, normally take the cheapest entry -- but if the
        # cheapest entry's surface is katakana and another entry IN THE SAME
        # CLASS (same grammatical role) spells the reading in plain
        # hiragana at a comparably low cost (within HIRA_MARGIN), prefer
        # that one instead. E.g. です's copula sense (助動詞,特殊・デス,
        # 基本形) has both a です (cost 40) and デス (cost 0) row -- purely
        # taking cheapest picked デス, so the extremely common polite copula
        # defaulted to katakana. This is a narrow, POS-driven tie-break
        # (same class = same grammatical role by construction, see
        # GROUP_FIELDS), not a per-word patch -- it applies uniformly to
        # every reading with this hiragana/katakana class-mate pattern
        # (~29 reduced-class groups have it, spot-checked: です/デス,
        # べし/ベシ, ござる/ゴザル, ...).
        HIRA_MARGIN = 500
        groups: dict = {}
        group_order = []
        for cost, left_id, right_id, surface in entries:
            if cost > MAX_COST:
                break
            key = (raw_to_reduced[left_id], raw_to_reduced[right_id])
            if key not in groups:
                groups[key] = []
                group_order.append(key)
            groups[key].append((cost, surface))

        reps = []
        for key in group_order:
            items = groups[key]
            best_cost, best_surface = items[0]  # cheapest, since entries was cost-sorted
            for cost, surface in items[1:]:
                if surface == reading and cost <= best_cost + HIRA_MARGIN:
                    best_cost, best_surface = cost, surface
                    break
            reps.append([best_cost, key[0], key[1], best_surface])
        reps.sort(key=lambda r: r[0])
        senses = reps[:MAX_SENSES_PER_READING]
        if not senses:
            continue

        seen_surfaces = set()
        surfaces = []
        for cost, _, _, surface in entries:
            if surface in seen_surfaces:
                continue
            seen_surfaces.add(surface)
            surfaces.append(surface)
            if len(surfaces) >= MAX_CANDIDATES_PER_READING:
                break
        # Integrity: every sense's own surface must appear in mozc_dict[reading]
        # so a caller that resolves a sense via mozc_costs can always find its
        # surface in mozc_dict too. Only matters in the rare case a sense's
        # surface got squeezed out by the MAX_CANDIDATES_PER_READING cap.
        for cost, rl, rr, surface in senses:
            if surface not in seen_surfaces:
                seen_surfaces.add(surface)
                surfaces.insert(0, surface)

        mozc_dict[reading] = surfaces
        mozc_costs[reading] = senses

    return mozc_dict, mozc_costs


def main():
    print("loading id.def / left-id.def, reducing POS classes into a shared registry...")
    group_key_to_reduced = {}
    raw_pos, raw_to_reduced = load_id_def(os.path.join(CACHE, "id.def"), "utf-8", group_key_to_reduced)
    mozc_num_reduced = len(group_key_to_reduced)
    print(f"  mozc: {len(raw_pos)} raw ids -> {mozc_num_reduced} reduced classes")

    have_ipadic = os.path.isdir(CACHE_IPADIC)
    if have_ipadic:
        ipadic_raw_pos, ipadic_raw_to_reduced = load_id_def(
            os.path.join(CACHE_IPADIC, "left-id.def"), "euc-jp", group_key_to_reduced)
        print(f"  + ipadic: {len(ipadic_raw_pos)} raw ids -> "
              f"{len(group_key_to_reduced) - mozc_num_reduced} new reduced classes "
              f"({len(group_key_to_reduced)} total)")
    num_reduced = len(group_key_to_reduced)
    content_class_mask = compute_content_class_mask(group_key_to_reduced, num_reduced)
    print(f"  {sum(content_class_mask)} of {num_reduced} classes are open-class content POS")

    print("building reduced connection matrix (this takes a bit)...")
    matrix, mozc_raw_median = build_reduced_matrix(raw_to_reduced, num_reduced)
    if have_ipadic:
        # Merge mozc's and real ipadic's connection matrices with MIN, in the
        # shared reduced-class space -- see the module docstring's
        # "Connection matrix: merged with real ipadic, not mozc alone"
        # section for why (mozc re-trained its matrix away from stock
        # ipadic, measurably worse for at least one very common pattern),
        # and build_ipadic_reduced_matrix's own comment for the calibration
        # offset this needs first (mozc's and ipadic's raw cost scales
        # differ by a large constant shift, not just noise -- merging
        # without correcting for that made results dramatically worse,
        # confirmed empirically before adding this calibration step).
        ipadic_matrix = build_ipadic_reduced_matrix(ipadic_raw_to_reduced, num_reduced, mozc_raw_median)
        matrix = np.minimum(matrix, ipadic_matrix)
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
    content_class_mask.append(0)  # synthetic UNKNOWN class is not a content class
    print(f"  + BOS/EOS class {bos_class}, + synthetic UNKNOWN class {unknown_class} "
          f"(discourage cost {discourage_cost}) -> final size {num_reduced}")

    print("parsing dictionary shards and building dict/costs tables...")
    mozc_dict, mozc_costs = build_dict_and_costs(raw_to_reduced)
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
            "contentClassMask": content_class_mask,
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
