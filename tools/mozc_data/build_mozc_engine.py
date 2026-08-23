#!/usr/bin/env python3
"""
Build the "track B" mozc-derived conversion engine data from the raw files
fetched by fetch_mozc.py, and write the small derived assets this app ships.

Inputs (tools/mozc_data/cache/, populated by fetch_mozc.py):
  - dictionary00.txt .. dictionary09.txt  (reading \t leftId \t rightId \t cost \t surface)
  - id.def                                ("<id> <pos1>,<pos2>,...,<pos7>")
  - connection_single_column.txt          (first line N; then N*N cost ints,
                                            row-major, connection[left][right])

No class reduction: mozc's raw 2,672 POS ids are used directly
------------------------------------------------------------------
Earlier versions of this pipeline folded mozc's raw POS space (2,672 ids,
id.def) into ~585-723 "reduced classes" (grouping by the first six
comma-separated POS fields, MIN-aggregating the connection matrix per
reduced-class pair) to keep mozc_matrix.json small and to let ipadic's own
connection matrix be merged in (ipadic and mozc use different raw id
spaces, but the same POS-label-string convention, so classes could align
by label after reduction -- see git history for that implementation).

This was measured, not assumed, to be a significant accuracy cost. Direct
analysis of mozc's raw connection_single_column.txt (2,672x2,672) found
that of the 342,225 reduced (left, right) class-pair buckets, 257,544
(75%) collapsed MORE THAN ONE raw (left, right) cost into a single number
-- among those, the internal spread (max-min) had a median of 3,176 and a
mean of 3,643 cost units (one bucket collapsed 200 raw pairs with min=0,
mean=11,196, max=14,793). Because MIN aggregation always keeps the single
cheapest raw pair in a bucket, this bias is directional: a reduced-class-
pair's stored cost often reflected an atypical best case, not the typical
real cost for most of the specific raw id pairs mapped into it -- so
segment()'s Viterbi DP was frequently pulled toward transitions that only
looked cheap because of the aggregation artifact, not because the actual
words involved connect cheaply.

Rebuilding with mozc's raw 2,672-class id space used directly (no
reduction at all -- mozc_costs.json's leftClass/rightClass are mozc's own
native ids, mozc_matrix.json ships the full unreduced 2,672x2,672 matrix)
and measuring against compare_engines.js confirmed this: corpus_test10.js
strict-match rate went 30.0% (6/20, reduced+ipadic-matrix-merged) -> 60.0%
(12/20, unreduced); corpus_test9.js went 26.5% (13/49) -> 40.8% (20/49).
Remaining misses are now overwhelmingly homophone/vocabulary choices
(とった vs 撮った), not the garbled mis-segmentations the reduced matrix
produced. This is a clear, large win, so the reduced-class-registry /
ipadic-connection-matrix-merge machinery was removed (see git history for
that code if it's ever worth revisiting -- e.g. if a future round wants
to bring back a *vocabulary* merge with real ipadic, which was never
attempted, only its connection matrix).

The tradeoff: mozc_matrix.json grew from ~2.5MB to ~36.5MB (2,672^2 cells,
no longer reducible). This app has no other large bundled assets besides
this and the hand-built dict.json/global_dict.json, and the accuracy gain
was judged worth it -- but it's a real, user-facing app-size cost, flagged
here for anyone reconsidering the tradeoff later.

Real ipadic's connection-matrix merge is gone with the reduction it
depended on; fetch_ipadic.py was removed along with it (nothing else in
this pipeline used real ipadic's data -- JMdict/SudachiDict vocabulary
augmentation, build_jmdict_augment.py/build_sudachi_augment.py, are
unrelated and unaffected by any of this).

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

mozc_costs.json now stores every DISTINCT (leftClass, rightClass) sense a
reading has, not just the cheapest overall: entries are grouped by that
class pair (mozc's own raw ids, used directly), the cheapest cost within
each pair is kept (ties within the
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

Historical note: the real-ipadic connection-matrix merge
------------------------------------------------------------
An earlier round found mozc's connection matrix is NOT stock ipadic's own
(mozc's authors re-trained/re-costed it from ipadic's original data) --
e.g. する's 連用形 -> た cost 859 in mozc's matrix but -7956 (strongly
preferred) in real ipadic's matrix.def -- and merged the two matrices
(MIN, in the shared reduced-class space) to fix specific cases like that
one. That merge is gone now along with the class reduction it depended on
(see the section above) -- superseded, not just removed: the unreduced
mozc-only matrix measured better than the reduced+ipadic-merged one on
both test corpora, and the case that motivated the ipadic merge
(じゅんびした mis-segmenting) is fixed by the unreduced matrix alone.

Outputs (entry/src/main/resources/rawfile/, shipped in the app). Note this
script always regenerates mozc_dict.json from scratch -- run
build_jmdict_augment.py and/or build_sudachi_augment.py afterward (see
tools/mozc_data/README.md) to re-apply their candidate-surface
augmentation from JMdict/SudachiDict if that's wanted:
  - mozc_dict.json    { reading: [surface, ...] }            ascending cost
  - mozc_costs.json   { reading: [[cost, leftClass, rightClass, surface], ...] }
                        one entry per distinct (leftClass, rightClass) sense,
                        ascending cost, capped at MAX_SENSES_PER_READING
  - mozc_matrix.json  { size: N, contentClassMask: [0|1, ...], class-id header
                         bosClass, ... }                       only (no matrix)
  - mozc_matrix.bin   flat uint16 LE connection costs          N*N, row-major
                         (device reads into Uint16Array; contentClassMask, see
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
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAWFILE_DIR = os.path.join(ROOT, "entry/src/main/resources/rawfile")

DICT_SHARDS = [f"dictionary{i:02d}.txt" for i in range(10)]

# "Full spec" mode: no pruning at all, at the user's explicit request
# ("重くなって良いので、mozcはフルスペックを開放" -- app-size cost accepted
# in exchange for full coverage of mozc's own bundled OSS data). Every
# constant below is set to mozc's own true observed maximum (checked
# directly against the raw dictionary shards, not guessed), so nothing is
# silently dropped:
#   - raw entry cost: median 7378, 100th pct (true max) 18318 -- no MAX_COST
#     cap at all keeps every one of the 745,964 distinct readings, not just
#     the ~138k that survived the old MAX_COST=6000 cutoff.
#   - distinct surface candidates per reading: 100th pct (true max) 296.
#   - distinct grammatical senses per reading: 100th pct (true max) 29 --
#     this is the one knob with a real runtime cost beyond static file size
#     (segment()'s Viterbi DP tracks one state per (position, class) it
#     reaches, so more senses per span means more states -- still small in
#     absolute terms since even the worst-case reading only has 29, not
#     thousands, but real on a phone's CPU, unlike the other two which are
#     pure download-size tradeoffs).
# See tools/mozc_data/README.md's "No class reduction" section for the
# matrix.json side of this: that file was already shipped unreduced
# (2,672x2,672, ~36.5MB) before this change, so it doesn't grow further here
# -- this only affects mozc_dict.json/mozc_costs.json's reading coverage.
MAX_COST = None  # no cap: keep every reading regardless of cost
MAX_CANDIDATES_PER_READING = 300  # true observed max is 296
MAX_SENSES_PER_READING = 30  # true observed max is 29

# 同じ (leftId, rightId) の組の中で、何通りの表記まで別々の語義として残すか。
#
# 1 だと「クラスごとに最安の1表記だけ」になり、同じ品詞の同音異字が
# まるごと DP から消える。かみ の 名詞,一般 は 神/髪/紙 が全部同じ組なので、
# 最安の 神 しか残らず、髪 も 紙 も候補として存在しない -- 表記の一覧
# (mozc_dict.json) には出るので候補欄には並ぶが、DP が選べないので
# 文の途中では絶対に出てこない。盲検コーパスの誤りを語義まで分解したとき、
# 「正解の表記に語義が無い」がおよそ半分を占めていた:
#   かみ 誤 神 / 正 髪、かがく 誤 科学 / 正 化学、きこう 誤 機構 / 正 気候、
#   あう 誤 合う / 正 会う ...
# いずれも同じ品詞の同音異字で、負けたのではなく最初から土俵にいなかった。
#
# コストは mozc 自身のものをそのまま使うので、順位付けは mozc の判断のまま。
# 増えるのは語義の件数 (= データ量と DP の分岐) だけ。
# See the アラビア数字 comment in build_dict_and_costs for why kana-typed
# readings penalize Arabic-digit senses.
ARABIC_DIGIT_PENALTY = 3000
# Flat penalty on proper-noun senses (名詞,固有名詞,人名/地域/組織). mozc
# prices many proper nouns cheaply enough to steal spans from ordinary
# segmentations (あすか人名+くぎ over あす+かくぎ閣議, にしの姓 over 西+の,
# あすも over あす+も, おおや→大谷さん...) -- a phone IME converting
# ordinary sentences should require stronger evidence before dropping a
# person/place name into the middle of one. Candidate lists still carry
# the proper noun for cycling; this only weights the DP's default path.
MAX_SURFACES_PER_CLASS = 1

PROPER_NOUN_PENALTY = 2500


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


def load_id_def(path: str, encoding: str) -> dict:
    """Parses an id.def-style file ("<id> <pos1>,<pos2>,...,<posN>" per
    line). Returns raw_id -> full pos fields list -- no class reduction (see
    the module docstring's "Class reduction: tried and rejected" section)."""
    raw_pos = {}
    with open(path, encoding=encoding) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            rid_str, pos = line.split(" ", 1)
            raw_pos[int(rid_str)] = pos.split(",")
    return raw_pos


def compute_content_class_mask(raw_pos: dict, num_raw: int) -> list:
    mask = [0] * num_raw
    for rid, fields in raw_pos.items():
        if fields[0] in CONTENT_POS_MAJOR:
            # 名詞,数 (numerals) excluded: a number sequence is legitimately
            # spelled one short span per digit/unit (ご|ひゃく|えん...,
            # さん|じゅっ|ぷん), so the short-span content penalty was
            # actively breaking numbers apart -- e.g. pushing the DP off
            # さん+じゅっ+ぷん onto a junk single-span place-name entry
            # (さんじゅっ→三拾, 名詞,固有名詞,地域). Numerals behave like
            # function words for segmentation purposes: short by nature,
            # licensed by context (the connection matrix already prices
            # 数→数/数→助数詞 transitions properly).
            if fields[0] == "名詞" and len(fields) > 1 and fields[1] == "数":
                continue
            mask[rid] = 1
    return mask


def load_raw_connection_matrix() -> np.ndarray:
    path = os.path.join(CACHE, "connection_single_column.txt")
    with open(path, encoding="utf-8") as f:
        n = int(f.readline())
        raw = np.loadtxt(f, dtype=np.int64)
    assert raw.size == n * n, f"expected {n*n} costs, got {raw.size}"
    return raw.reshape(n, n)


def to_hiragana(s: str) -> str:
    """Katakana -> hiragana (U+30A1-U+30F6 -> U+3041-U+3096); other chars
    (kanji, ー, ASCII) pass through unchanged."""
    return "".join(
        chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c
        for c in s
    )


def build_dict_and_costs(raw_to_reduced: dict, raw_pos_fields: dict):
    global RAW_POS_FIELDS
    RAW_POS_FIELDS = raw_pos_fields
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
        if MAX_COST is not None and entries[0][0] > MAX_COST:
            continue  # prune the long rare/obscure tail (see MAX_COST comment above)

        # One sense per distinct (leftId, rightId) raw id pair (mozc's own,
        # used directly -- see the module docstring's "No class reduction"
        # section), up to MAX_SENSES_PER_READING -- see the "Node cost /
        # class per reading" section for why this replaced the old
        # single-representative-triple design.
        #
        # Within a class, normally take the cheapest entry -- but if that
        # cheapest surface is merely a KATAKANA-STYLED VARIANT of the
        # reading itself (to_hiragana(surface) == reading: デス, マジ,
        # ヤバい, ホンマ -- no lexical content beyond the reading, just
        # script styling) and another entry IN THE SAME CLASS (same
        # grammatical role) spells the reading in plain hiragana at a
        # comparably low cost (within HIRA_MARGIN), prefer the hiragana
        # one. E.g. です's copula sense (助動詞,特殊・デス,基本形) has both
        # a です (cost 40) and デス (cost 0) row -- purely taking cheapest
        # picked デス, so the extremely common polite copula defaulted to
        # katakana; same pattern across casual/slang vocabulary (まじ/マジ,
        # やばい/ヤバい, えぐい/エグい, ほんま/ホンマ, ...).
        #
        # The "cheapest is a katakana variant" gate is load-bearing: an
        # earlier version omitted it and flipped ANY class where a kana row
        # sat within 500 cost of the winner -- e.g. とっ's 五段促音便 class
        # has 取っ (2345, mozc's own cheapest = its own preferred surface)
        # and とっ (2464), so the ungated margin overrode mozc's real
        # ranking with bare kana across thousands of ordinary verbs/nouns
        # (とった/たりない/つかれた...). With the gate, a kanji winner is
        # never touched; only katakana-vs-hiragana styling of the same word
        # is tie-broken toward hiragana. Genuine loanwords (ばす→バス,
        # めーる→メール) are unaffected in practice because mozc carries no
        # cheap plain-hiragana row for them in the same class.
        HIRA_MARGIN = 500
        groups: dict = {}
        group_order = []
        for cost, left_id, right_id, surface in entries:
            if MAX_COST is not None and cost > MAX_COST:
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
            if to_hiragana(best_surface) == reading and best_surface != reading:
                for cost, surface in items[1:]:
                    if surface == reading and cost <= best_cost + HIRA_MARGIN:
                        best_cost, best_surface = cost, surface
                        break
            # Arabic-digit senses (名詞,数,アラビア数字 -- surfaces like "5"
            # for reading ご) get a flat register penalty: these senses are
            # only ever reachable here through a KANA-TYPED reading (this
            # whole dictionary is kana-keyed), and a user who typed いち/ご
            # in kana wants 一/五, not 1/5 -- digits are typed on the number
            # pad. Without this, unpenalized digit entries (mozc prices some
            # very low, e.g. 2/に at 998) win numeral spans and produce
            # mixed-register output like 1日/1週間分 for いちにち typed in
            # kana. Kanji-numeral (漢数字) senses are untouched.
            # この組から残す表記。先頭は上のかな優先を通した best_surface で、
            # 続けて同じ組の他の表記を安い順に MAX_SURFACES_PER_CLASS 件まで。
            # 同音異字を DP から届くようにするための拡張 (定数の説明を参照)。
            emitted = [(best_cost, best_surface)]
            for cost, surface in items:
                if len(emitted) >= MAX_SURFACES_PER_CLASS:
                    break
                if any(surface == s for _, s in emitted):
                    continue
                emitted.append((cost, surface))

            fields = RAW_POS_FIELDS[key[0]]
            is_digit = fields[:3] == ["名詞", "数", "アラビア数字"]
            is_proper = fields[0] == "名詞" and len(fields) > 1 and fields[1] == "固有名詞"
            for cost, surface in emitted:
                if is_digit:
                    cost += ARABIC_DIGIT_PENALTY
                if is_proper:
                    cost += PROPER_NOUN_PENALTY
                reps.append([cost, key[0], key[1], surface])
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


def write_outputs(mozc_dict: dict, mozc_costs: dict, size: int, bos_class: int,
                   unknown_class: int, content_class_mask: list, matrix: np.ndarray,
                   class_labels: list, noun_general_class: int,
                   kanji_number_class: int) -> None:
    os.makedirs(RAWFILE_DIR, exist_ok=True)
    with open(os.path.join(RAWFILE_DIR, "mozc_dict.json"), "w", encoding="utf-8") as f:
        json.dump(mozc_dict, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(RAWFILE_DIR, "mozc_costs.json"), "w", encoding="utf-8") as f:
        json.dump(mozc_costs, f, ensure_ascii=False, separators=(",", ":"))
    # The N*N connection matrix is by far the heaviest structure (2,673^2 =
    # ~7.14M cells). Shipping it as a JSON array of ints and reshaping it into
    # a JS number[][] on device was the dominant driver of the IME extension's
    # out-of-memory crash: a boxed number[][] of 7.14M elements is well over
    # 50MB resident, on top of a ~35MB JSON string that has to be parsed cell by
    # cell. Instead we ship the matrix as a flat little-endian uint16 binary
    # (mozc_matrix.bin) the device reads straight into a Uint16Array -- ~14MB,
    # no JSON parse. mozc_matrix.json keeps only the small header (class ids +
    # contentClassMask). Connection costs are non-negative and observed <=~15k,
    # so uint16 (0..65535) is safe; assert it so a future data change can't
    # silently wrap.
    flat = matrix.reshape(-1)
    assert flat.min() >= 0 and flat.max() <= 65535, (
        f"connection cost out of uint16 range: min={flat.min()} max={flat.max()}")
    with open(os.path.join(RAWFILE_DIR, "mozc_matrix.bin"), "wb") as f:
        f.write(flat.astype("<u2").tobytes())
    with open(os.path.join(RAWFILE_DIR, "mozc_matrix.json"), "w", encoding="utf-8") as f:
        json.dump({
            "size": size,
            "bosClass": bos_class,
            "unknownClass": unknown_class,
            "nounGeneralClass": noun_general_class,
            "kanjiNumberClass": kanji_number_class,
            "contentClassMask": content_class_mask,
            # matrix cells live in mozc_matrix.bin (row-major uint16 LE, N*N).
        }, f, separators=(",", ":"))

    # Reference-only (not shipped in the app): class id -> label, for
    # maintainers who want to inspect what a given class id means.
    with open(os.path.join(HERE, "mozc_classes_reference.json"), "w", encoding="utf-8") as f:
        json.dump(class_labels, f, ensure_ascii=False, indent=1)

    for name in ("mozc_dict.json", "mozc_costs.json", "mozc_matrix.json", "mozc_matrix.bin"):
        path = os.path.join(RAWFILE_DIR, name)
        print(f"  {name}: {os.path.getsize(path):,} bytes")


def main():
    print("loading id.def (mozc's raw 2,672 POS ids, no class reduction -- see module docstring)...")
    raw_pos = load_id_def(os.path.join(CACHE, "id.def"), "utf-8")
    num_raw = len(raw_pos)
    raw_to_raw = {rid: rid for rid in raw_pos}  # identity: build_dict_and_costs groups by (left_id, right_id) directly
    print(f"  {num_raw} raw ids")

    content_class_mask = compute_content_class_mask(raw_pos, num_raw)
    print(f"  {sum(content_class_mask)} of {num_raw} classes are open-class content POS")

    print("loading raw connection matrix...")
    matrix = load_raw_connection_matrix()
    assert matrix.shape == (num_raw, num_raw), (matrix.shape, num_raw)
    print(f"  matrix shape: {matrix.shape}")

    # segment()'s Viterbi DP (KanaKanjiConverter.ets) needs two extra things
    # this matrix alone doesn't carry:
    #  - a BOS/EOS class to seed the sentence-boundary edge cost (mirrors
    #    track A's VC_BOS) -- this is just raw id 0.
    #  - an UNKNOWN class for single characters with no dictionary entry
    #    (mirrors track A's VC_UNKNOWN) -- id.def has no such catch-all
    #    entry (mozc handles OOV via a separate mechanism this pipeline
    #    doesn't pull in), so we append one synthetic extra
    #    class/row/column whose connection cost to everything is a fixed,
    #    strongly-discouraging value (the observed max cost in the matrix),
    #    so it only ever wins the DP when nothing real fits -- the same
    #    role VN_UNKNOWN_SINGLE/VC_UNKNOWN play in track A.
    bos_class = 0
    unknown_class = num_raw
    discourage_cost = int(matrix.max())
    padded = np.full((num_raw + 1, num_raw + 1), discourage_cost, dtype=np.int64)
    padded[:num_raw, :num_raw] = matrix
    matrix = padded
    size = num_raw + 1
    content_class_mask.append(0)  # synthetic UNKNOWN class is not a content class
    print(f"  + BOS/EOS class {bos_class}, + synthetic UNKNOWN class {unknown_class} "
          f"(discourage cost {discourage_cost}) -> final size {size}")

    # Raw id of plain 名詞,一般 -- shipped so the runtime can score
    # user-dictionary spans (readings mozc doesn't know) as ordinary nouns
    # instead of the punitive synthetic-UNKNOWN class.
    noun_general_class = -1
    for rid, fields in raw_pos.items():
        if fields[:2] == ["名詞", "一般"] and all(f == "*" for f in fields[2:]):
            noun_general_class = rid
            break
    print(f"  名詞,一般 raw id: {noun_general_class}")

    # Generic 名詞,数,漢数字 id -- the class the runtime's numeral pre-pass
    # (see KanaKanjiConverter.ets, mozcNumeralRuns) scores its composed
    # kanji-numeral spans as.
    kanji_number_class = -1
    for rid, fields in raw_pos.items():
        if fields[:3] == ["名詞", "数", "漢数字"] and all(f == "*" for f in fields[3:]):
            kanji_number_class = rid
            break
    print(f"  名詞,数,漢数字 raw id: {kanji_number_class}")

    print("parsing dictionary shards and building dict/costs tables...")
    mozc_dict, mozc_costs = build_dict_and_costs(raw_to_raw, raw_pos)
    print(f"  {len(mozc_dict)} distinct readings")

    class_labels = [None] * size
    for rid, fields in raw_pos.items():
        class_labels[rid] = ",".join(fields)

    write_outputs(mozc_dict, mozc_costs, size, bos_class, unknown_class, content_class_mask, matrix, class_labels, noun_general_class, kanji_number_class)
    print("done.")


if __name__ == "__main__":
    main()
