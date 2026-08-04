# Track B: mozc + JMdict + SudachiDict-derived conversion engine

An optional, in-app switchable second conversion engine (settings toggle:
独自辞書/統計データ) built from mozc's (BSD-3-Clause,
https://github.com/google/mozc) open-source dictionary/connection-cost
data, used with its raw 2,672-class POS space directly (no reduction --
see "No class reduction" below), and augmented with extra kanji-spelling
candidates from JMdict (https://www.edrdg.org/, CC BY-SA 4.0) and
SudachiDict (https://github.com/WorksApplications/SudachiDict, Apache
License 2.0) -- kept entirely separate from this project's own hand-built
dictionary ("track A": `dict.json` / the inline `DICTIONARY` in
`KanaKanjiConverter.ets` / `getWordInfo`'s hand-tuned cost heuristics). See
the top-level `THIRD_PARTY_NOTICES.md` for the exact license terms this
data carries.

## Regenerating

```sh
python3 tools/mozc_data/fetch_mozc.py            # downloads + caches raw mozc data (not committed)
python3 tools/mozc_data/build_mozc_engine.py     # writes entry/src/main/resources/rawfile/mozc_*.json (intermediate, see below)
python3 tools/mozc_data/fetch_jmdict.py          # downloads + caches raw JMdict.xml (not committed)
python3 tools/mozc_data/build_jmdict_augment.py  # augments mozc_dict.json in place (run AFTER build_mozc_engine.py)
python3 tools/mozc_data/fetch_sudachi.py         # downloads + caches SudachiDict lexicon CSVs (not committed)
python3 tools/mozc_data/build_sudachi_augment.py # augments mozc_dict.json in place (run AFTER build_mozc_engine.py)
python3 tools/mozc_data/convert_to_binary.py     # flattens mozc_dict.json/mozc_costs.json into the shipped mozc_*.bin/*.json (see "On-device format" below)
node tools/ime-eval/regress.js                             # confirm zero change to track A (custom)
node tools/mozc_data/compare_engines.js --misses            # custom vs mozc on corpus_test10.js
node tools/mozc_data/compare_engines.js corpus_test9.js     # or any other tools/ime-eval/ corpus
```

Order matters: `build_mozc_engine.py` always regenerates `mozc_dict.json`
from scratch (mozc's dictionary shards only), so both augmentation
scripts -- which only ever edit `mozc_dict.json` in place, appending
surfaces -- must run after it, every time. The two augmentation scripts
can run in either order relative to each other. Re-running
`build_mozc_engine.py` alone discards any previous JMdict/SudachiDict
augmentation; re-run both augmentation scripts again afterward to restore
it. `convert_to_binary.py` must run last, after both augmentation scripts,
since it's what actually produces the files read on-device (see "On-device
format" below) -- forgetting this step leaves the shipped rawfiles stale
even though `mozc_dict.json`/`mozc_costs.json` were regenerated correctly.

Each augmentation script skips with a note if its own fetch script's cache
is absent.

All three caches (`tools/mozc_data/cache/`, `cache_jmdict/`, `cache_sudachi/`
-- ~90MB + ~120MB + ~270MB) are gitignored; only the derived output is
committed and shipped in the app.

### On-device format

`build_mozc_engine.py`/the augmentation scripts write their output as
`entry/src/main/resources/rawfile/mozc_dict.json` / `mozc_costs.json` /
`mozc_matrix.json` (JSON, easy to inspect/diff) -- but these are build
**intermediates** only, gitignored (see
`entry/src/main/resources/rawfile/.gitignore`) and
never shipped in the app as of the OOM fix below. `convert_to_binary.py`
reads them and writes the actual shipped files: `mozc_readings.json` /
`mozc_dict_surfaces.json` / `mozc_dict_index.bin` / `mozc_costs_surfaces.json`
/ `mozc_costs_index.bin` / `mozc_costs.bin` (plus `mozc_matrix.bin`, written
directly by `build_mozc_engine.py` itself). These flattened files (~76MB
combined) are what's committed and what `KeyboardController.ets`'s
`loadMozcRawfiles` fetches on-device -- see `convert_to_binary.py`'s module
docstring for why (JSON.parsing the un-flattened `Record<reading, ...>`
JSON directly on-device peaked past the IME extension's memory budget and
crashed it). `tools/mozc_data/load_mozc.js` is the Node-side equivalent
loader, used by `compare_engines.js`/the eval harness.

`convert_to_binary.py`'s three *string* outputs (`mozc_readings.json` /
`mozc_dict_surfaces.json` / `mozc_costs_surfaces.json`) are no longer shipped
as JSON either: `pack_strings.py` repacks them into `.blob`/`.len`/`.base`
(+`.srt` for readings) and those are what ship. The JSON originals moved to
`tools/mozc_data/packed_src/` -- anything left under `rawfile/` is packed
into the HAP whether the app reads it or not, and nothing reads them at
runtime any more. Re-run `pack_strings.py` after any rebuild that changes
those three files, then `verify_packed.js`.

Why: the JSON was cheap to *read* and expensive to *parse*. Measured
on-device, per stage, loading the mozc engine took 1990ms:

| stage | time |
| --- | --- |
| file reads (76MB, every file) | 139ms |
| `JSON.parse` of the three string tables | 1456ms |
| building `Map<reading, index>` (746k) | 395ms |

93% of it was making the JS engine materialise 746k+ string objects and a
hash map, none of which is needed until a reading is actually looked up. The
packed form is read as bytes, strings are decoded lazily on first access, and
readings are found by binary-searching `.srt` against the raw UTF-8 in the
blob instead of through a `Map`. Same measurement after: **117ms** (106ms
reads + 11ms assembly), and the packed files are 2.45MB *smaller* than the
JSON they replace. See `MozcStrTable` in `KanaKanjiConverter.ets` for the
layout and `pack_strings.py`'s docstring for why lengths are uint8 with a
per-32-entry base rather than a uint32 offset per string.

This is a format change only, and is held to that: `verify_packed.js` checks
every one of the 2,960,934 entries against the JSON, plus `indexOf()`
round-tripping on all 745,964 readings and negative lookups. Run it after
`pack_strings.py`.

**"Full spec" mode**: `MAX_COST`/`MAX_CANDIDATES_PER_READING`/
`MAX_SENSES_PER_READING` in `build_mozc_engine.py` were relaxed to mozc's
own true observed maximums (no reading dropped by cost, every candidate
surface and every distinct grammatical sense kept), at explicit user
request accepting the app-size cost. `mozc_dict.json`/`mozc_costs.json`
grew from ~8.8MB/~8.0MB (138k readings, the old MAX_COST=6000 cutoff) to
~38MB/~47MB (all 745,964 readings). `mozc_matrix.json` is unaffected (it
was already shipped unreduced, see "No class reduction" below). See the
constants' own comment block in `build_mozc_engine.py` for the exact
percentiles this was measured against.

## How it plugs in

`KanaKanjiConverter` has a static `engine: 'custom' | 'mozc'` flag. When it's
`'custom'` (the default), every existing method runs completely unchanged —
this is verified every time via `tools/ime-eval/run_all.js` /
`sweep.js` / `sweep_join.js` / `regress.js` showing zero change from before
this track existed. When `'mozc'`, five entry points
(`inDict`/`getWordInfo`/`getEdgeCost`/`lookup`/`isDictionaryWord`) dispatch
to mozc-specific counterparts at their very top. `segment()`'s Viterbi DP
itself has one real branch (see below) but is otherwise the same shared
method for both engines — its backtrace/merge/return-value contract is
unchanged, so every caller (`joinSegs`, `findAlternateSegmentation`,
`KeyboardController.ets`, the eval harness) works unmodified for both
engines. See the `engine` field's comment block in `KanaKanjiConverter.ets`
for the full design.

### Sense-aware Viterbi

Earlier versions of this pipeline collapsed every dictionary entry sharing a
reading down to a single representative `(cost, leftClass, rightClass)`
triple (whichever was globally cheapest). That was diagnosed as a primary
cause of poor connected-sentence accuracy: many readings have several
distinct grammatical senses (e.g. し is both する's conjugated stem and an
unrelated classical auxiliary form), and collapsing to one picks whichever
was cheapest in isolation, with no way for the DP to ever consider the
other.

`mozc_costs.json` now stores every distinct `(leftClass, rightClass)` sense
a reading has (mozc's own raw ids, used directly -- see below; capped at
`MAX_SENSES_PER_READING`, see `build_mozc_engine.py`), each carrying its own
literal surface. `segment()`'s DP (`KanaKanjiConverter.ets`, the `isMozc`
branch) tries every sense of a span and lets normal cost minimization pick
whichever fits context — the winning sense's surface is threaded through
backtrace into an instance-level hint map (`mozcLastHints`) so
`lookupMozc()` shows that exact sense, not just "whatever's cheapest for
the reading with no context."

### No class reduction: mozc's raw 2,672 POS ids, used directly

An earlier version of this pipeline folded mozc's raw POS space (2,672
ids, `id.def`) into ~585-723 "reduced classes" (MIN-aggregating the
connection matrix per reduced-class pair) to keep `mozc_matrix.json` small
and to let real mecab-ipadic's own connection matrix be merged in
(different raw id space than mozc's, but the same POS-label-string
convention, so classes could align by label after reduction).

Direct analysis of mozc's raw `connection_single_column.txt` (2,672x2,672)
found this reduction was a real, measurable accuracy cost, not just a
theoretical one: of the 342,225 reduced (left, right) class-pair buckets,
257,544 (75%) collapsed MORE THAN ONE raw (left, right) cost into a single
number, and among those, the internal spread (max-min) had a median of
3,176 and a mean of 3,643 cost units (worst case: 200 raw pairs collapsed
into one bucket spanning min=0 to max=14,793). Because MIN aggregation
always keeps the cheapest raw pair in a bucket, the bias is directional:
a reduced-class-pair's stored cost often reflected an atypical best case,
not the typical cost for most of the specific raw id pairs mapped into it
-- pulling segment()'s Viterbi DP toward transitions that only looked
cheap because of the aggregation artifact.

Rebuilding with mozc's raw 2,672-class id space used directly (no
reduction: `mozc_costs.json`'s `leftClass`/`rightClass` are mozc's own
native ids, `mozc_matrix.json` ships the full unreduced 2,672x2,672
matrix) and measuring confirmed the fix — see "Measured effect" below.
The reduced-class-registry / real-ipadic-connection-matrix-merge machinery
this replaced is gone (see git history for that implementation).

**Tradeoff**: `mozc_matrix.json` grew from ~2.5MB (reduced) to ~36.5MB
(2,672² cells, no longer reducible) — a real, user-facing app-size cost.
Judged worth it given the accuracy gain measured below, but flagged here
for anyone reconsidering the tradeoff later (e.g. if app size becomes a
real complaint, a middle-ground reduction granularity is one lever;
another is only reducing for the *unknown-fallback* case rather than the
whole matrix).

### Per-(position, class) Viterbi states, not one state per position

`segment()`'s DP (`KanaKanjiConverter.ets`) used to track a single cheapest
state per character position (`best[i]` + one `rightClass[i]`) — standard
for track A's own much smaller, hand-designed class space, but a real bug
for track B's much larger one: whenever two senses of a span tied exactly
on total cost, only the first one tried survived, and every later edge
cost was computed against *its* class alone, even when a different tied
sense would have connected far better to whatever actually followed.

Confirmed via direct debug trace (not assumed) as the cause of a real
miss: ダウンロードした mis-converting to ダウンロード下. "ダウンロード"
isn't in mozc's (hiragana-keyed) dictionary as a katakana span, so it's
processed one character at a time via the generic UNKNOWN-class fallback
-- and connecting FROM the UNKNOWN class costs the same maximal
discourage_cost to every class, so five of し's six senses (助動詞文語キ/
助詞/動詞接尾/動詞未然形/動詞連用形) tied exactly at cost 0. The old
single-state version kept whichever came first in mozc_costs.json (文語
キ, a rare classical form) and permanently lost する's 連用形 sense (the
one actually needed) right there, so た then computed its own edge cost
against the wrong surviving class and lost to a cheaper "した(下)" 2-span
reading instead.

Fixed by tracking every reachable (position, class) state (a `Map<class,
{cost, prevPos, prevClass, surface}>` per position, not a single scalar) --
exactly what real Viterbi POS taggers (mecab/kuromoji/Sudachi) do. Ties
now survive until an actual difference in the following context resolves
them, instead of being collapsed arbitrarily by array order. Scoped to
the `isMozc` branch only; track A keeps its original scalar arrays
completely untouched (verified via `run_all.js`/`regress.js`/`sweep.js`/
`sweep_join.js` showing zero change). Reachable classes per position stay
naturally bounded (roughly `MAX_LEN` × `MAX_SENSES_PER_READING`), so this
adds no meaningful overhead -- `compare_engines.js` runs at the same speed
as before.

### Two further generic (POS-driven, not per-word) mitigations

Both verified empirically against `compare_engines.js`:
- **Short-span content-word penalty** (`MOZC_SINGLE_CONTENT_PENALTY`,
  `KanaKanjiConverter.ets`): a 1-2 character span almost always has *some*
  dictionary sense (mozc has the same raw kanji-homophone-dump problem per
  short reading that the hand-built dictionary had before
  `reorder_kana_dumps.py` cleaned it up), so an unpenalized open-class
  content sense here frequently steals a short span from what should have
  been part of a longer word. Mirrors track A's own `singleContentPenalty`.
  Only applies to `contentClassMask` POS (名詞/形容詞/副詞/連体詞/接頭詞) —
  **動詞 (verbs) deliberately excluded**, unlike track A: a short verb span
  is very often a genuine conjugated stem used as light-verb glue
  (じゅんびした = 準備 + し(する's 連用形) + た), not homophone noise the way
  a short bare noun usually is. Including 動詞 in the penalty was tried and
  empirically made things worse (re-broke じゅんびした specifically);
  excluding it is a measured result, not an assumption.
- **Hiragana-preference tie-break within a class** (`build_dict_and_costs`,
  `HIRA_MARGIN`): when a class (mozc's own raw leftId/rightId pair) has
  both a katakana-lexeme entry and a same-cost-ballpark entry whose
  surface is literally the reading itself, prefer the hiragana one. Fixed
  です defaulting to デス (both exist in mozc's raw data at nearly the same
  cost, same 助動詞,特殊・デス,基本形 sense, i.e. the same raw id pair) —
  verified this pattern recurs across ~29 such groups (ござる/ゴザル,
  べし/ベシ, …), not a です-only patch.

### Measured effect

`compare_engines.js` strict-match rate:

| Corpus | track A (unchanged throughout) | sense-aware Viterbi only | + real-ipadic matrix merge (removed) | + no class reduction | + per-class Viterbi states | + full-spec pruning removal (current) |
|---|---|---|---|---|---|---|
| `corpus_test10.js` (20 sentences) | 16/20 (80.0%) | 4/20 (20.0%) | 6/20 (30.0%) | 12/20 (60.0%) | 14/20 (70.0%) | 14/20 (70.0%) |
| `corpus_test9.js` (49 sentences, 16 registers) | 35/49 (71.4%) | 9/49 (18.4%) | 13/49 (26.5%) | 20/49 (40.8%) | 26/49 (53.1%) | **29/49 (59.2%)** |

Across the full `tools/ime-eval` suite (TRAIN+TEST1-10, 529 sentences), the
full-spec pruning removal moved track B from 309/529 (58.4%) to 327/529
(61.8%) strict-match — a real, modest gain (every sub-corpus non-negative,
none regressed), not the large jump the earlier no-class-reduction/
per-class-state fixes were. Track A remains clearly ahead (76.2%): the
pruning caps this removed were mostly trimming genuinely rare vocabulary,
not silently hobbling common-case accuracy, so most of this mode's cost is
paid in app size (mozc_dict.json/mozc_costs.json roughly quadrupled) for a
comparatively small accuracy return. See "This is still not
'Gboard-adjacent' quality" below for the harder ceiling full-spec mode
doesn't touch.

### The 2026-07 deep-fix round (327 → 360/529, 61.8% → 68.1%)

A systematic miss-categorization pass (dump every TRAIN+TEST1-10 miss with
its segmentation, trace representative cases against the raw data, fix the
structural cause, re-measure) landed these, in order of measured impact:

- **HIRA_MARGIN mis-implementation** (build): the "prefer hiragana in the
  same class" tie-break (for です/デス) never checked that the entry it was
  replacing was a katakana styling of the reading — so it also replaced
  KANJI winners (取っ 2345, mozc's own preferred surface) with kana rows
  within 500 cost (とっ 2464), silently kana-locking thousands of ordinary
  verbs (とった/たりない/つかれた...). Now gated on
  `to_hiragana(best_surface) == reading`.
- **Track A hand-tuning leaking into track B's composition**: autoConvert's
  FUNCTION_WORDS short-circuit and homograph overrides (ね/でる/たり →
  forced kana) applied regardless of engine, overwriting the mozc DP's
  correct 寝/出る/足り choices. Track B now goes straight to its own
  hint-first lookup.
- **Missing EOS edge cost** (runtime): the DP picked its final state without
  the word→EOS transition (matrix[cls][0]) real mozc adds -- no signal to
  prefer sentence-terminal forms. Structural omission of the port, fixed.
- **Proper-noun steamrolling** (build): mozc prices many proper nouns
  cheaply enough to hijack ordinary sentences (あすか人名+くぎ over
  あす+かくぎ閣議, にしの姓 over 西+の). PROPER_NOUN_PENALTY=2500 (swept
  1500/2500/3500 on TRAIN) on 固有名詞 senses.
- **Numeral handling** (build + runtime): three interlocking fixes -- 名詞,数
  excluded from the short-span content penalty (numbers are legitimately
  typed one unit at a time), ARABIC_DIGIT_PENALTY=3000 on kana-typed
  digit senses (typing ご in kana means 五, not 5), and a runtime numeral
  pre-pass (findMozcNumeralRuns) that offers composed kanji-number spans
  (さんじゅっ→三十, ごひゃく→五百) as proper 漢数字-class DP senses --
  mozc's own lexicalized entries for these are junk (さんじゅっ→三拾 as a
  PLACE NAME) and its per-token numeral costs lose to homophone noise
  (産=10 vs 三=3248). This is the moral equivalent of real mozc's
  NumberRewriter, which its OSS lattice data alone doesn't reproduce.
- **2-char content penalty removed** (runtime): the half-strength penalty on
  2-mora content spans hit nouns but not verbs (動詞 excluded from the
  mask), tilting every 2-mora noun-vs-verb ambiguity ~1250 toward the verb
  (しゅうまつはうみにいく → 生み). Traced via a full Python re-simulation
  of the DP; len==1 keeps the full penalty.
- **MAX_LEN 10 → 16** (runtime, mozc only): 5.7% of mozc's readings (42k,
  including common polite phrases like ありがとうございました) were longer
  than the DP's span cap and structurally unconvertible.
- **Kana-first unknown fallback**: unknown readings only lead with katakana
  when they contain ー (loanword signal); それって no longer becomes
  ソレッテ.

Plus three user-facing layers the corpus numbers don't capture:

- **Composed whole-input candidates** (composeMozcCandidates): the
  candidate list for a multi-segment input used to be whatever junk entry
  the concatenated reading happened to have (とった → [トッタ], nothing
  else -- 撮った was unreachable by cycling). Now built from the winning
  path with one-segment-at-a-time same-reading swaps (取った/撮った/
  獲った...), the dominant real-world correction pattern.
- **Learned-choice and user-dictionary layering in lookupMozc**: track B
  now applies the same user-intent priority order as track A (user dict >
  learned > engine), where it previously consulted neither -- a homophone
  the user had corrected a hundred times kept defaulting to mozc's
  statistical pick. Learned surfaces absent from the candidate list are
  prepended (not just reordered), since track B's per-reading lists
  genuinely lack many valid conversions the user built through 文節変換.
- **User-dictionary spans in the DP**: readings mozc doesn't know but the
  user registered are now DP-eligible (scored as 名詞,一般 at mid cost via
  nounGeneralClass) instead of being unconvertible line noise.

(Original baseline before any track B accuracy work: 2/20 and not
measured, respectively.) Removing class reduction and then fixing the
single-state-per-position Viterbi bug are the two largest improvements
made to track B so far, each roughly doubling strict-match rate in turn,
and together fixing both cases that motivated the (now-removed) ipadic
merge (じゅんびした → 準備した) and the per-class-state fix
(ダウンロードした, どこかいこうよ). Remaining misses are now
overwhelmingly homophone/vocabulary choices (とった vs 撮った, ふる vs
降る) rather than garbled mis-segmentations — real, qualitative
improvement beyond what the strict-match number alone shows.

JMdict/SudachiDict vocabulary augmentation (below) doesn't move this
number at all, by design — they only add candidate-cycling surfaces, never
touch what the DP scores.

**This is still not "Gboard-adjacent" quality.** mozc's own OSS README
(`dictionary_oss/README.txt`, fetched by `fetch_mozc.py`) states its
bundled dictionary explicitly excludes "the large vocabulary set generated
from the Web corpus" that the real Google Japanese Input / Gboard engines
use. There is a hard vocabulary ceiling here that connection-matrix or
Viterbi engineering alone can't remove (see "JMdict/SudachiDict vocabulary
augmentation" below for the steps taken against this, and "Considered, not
yet done" for what wasn't). Track B should currently be understood as "a
genuine second opinion with real, measurably improving quality," not a
recommended daily-driver replacement for track A.

### JMdict vocabulary augmentation

`build_jmdict_augment.py` broadens track B's candidate-cycling vocabulary
with JMdict's kanji spellings (CC BY-SA 4.0, see `THIRD_PARTY_NOTICES.md`
for the full license terms and how this project satisfies them), in a
deliberately narrow **safe mode**: it only appends extra surface candidates
to `mozc_dict.json` readings that **already exist** there — it never adds
a new reading key.

This scope was chosen specifically to preserve the "never changes DP/
segmentation behavior" guarantee: `segment()`'s DP (`KanaKanjiConverter.ets`)
gates multi-character spans on `inDict(sub)`, which for track B checks
`mozcDict` directly. Adding a brand-new reading key would make spans
matching it newly DP-eligible (falling back to the generic UNKNOWN-class
discourage cost in `getWordInfoCandidatesMozc`, since `mozc_costs.json`
would have no real entry for it) — a real change to segmentation behavior
for sentences containing that reading. Restricting augmentation to
already-known readings avoids all of that: `inDict`/
`getWordInfoCandidatesMozc`/segment()'s DP see exactly the same set of
DP-eligible spans before and after augmentation. Only `lookup()`/
`lookupMozc()`'s candidate *list* for an already-recognised reading grows
— e.g. more kanji options when cycling candidates for a reading typed and
converted on its own.

Effect (full-spec base, 2026-07-21 data, see below): scanned 258,285 JMdict
reading/kanji pairs, augmented 28,690 of the 745,964 readings already in
`mozc_dict.json` (3.8%), adding 45,014 candidate surfaces total
(mozc_dict.json: 35,436,895 → 35,973,210 bytes, +1.5%). Per-reading
additions are capped (`MAX_NEW_PER_READING=12` new surfaces,
`MAX_TOTAL_CANDIDATES=40` overall per reading) and ordered with JMdict's own
priority-tagged (news1/ichi1/spec1/spec2/gai1) spellings first, since
JMdict carries no cost/frequency number the way mozc's dictionary does.

**Katakana-reading normalization (2026-07 freshness pass)**: `mozc_dict.json`'s
reading keys are, with a handful of iteration-mark exceptions, entirely
hiragana (mozc's own dictionary is keyed by hiragana IME input, never
katakana) — but about a third of JMdict's own `<reb>` reading elements are
written in katakana (slang/emphasis forms like アカン, gairaigo-style
readings like アソコ, etc.). `build_jmdict_augment.py` didn't normalize
`<reb>` before checking it against `mozc_dict.json`, so it silently dropped
every katakana-written reading before the "does this reading already exist"
check even ran — measured at 33,971 of 258,285 (reading, kanji) pairs
(13.2%) never getting a chance to match, e.g. アセビ→馬酔木, アソコ→彼処/
彼所, アマゴ→甘子, アカン→明かん, アホンダラ→阿呆陀羅. Fixed by adding the
same katakana→hiragana `kata_to_hira` helper `build_sudachi_augment.py`
already uses for its own (katakana-only) reading field. Effect of the fix
alone (isolated from the same-week JMdict data refresh above): +2,057
readings augmented, +2,850 candidate surfaces, all still within the same
safe-mode scope (no new reading keys, no DP/segmentation change — verified
via `regress.js` and a full TRAIN+TEST1-10 `compare_engines.js` run showing
0 strict-match change for both `mozc` and `hybrid`).

### SudachiDict vocabulary augmentation

`build_sudachi_augment.py` does the same thing as the JMdict augmentation
above, sourced from SudachiDict (Apache License 2.0,
https://github.com/WorksApplications/SudachiDict) instead — same safe
mode (only appends candidates to already-existing `mozc_dict.json`
readings, never adds a reading key), same reasoning for why that scope
specifically preserves the "never changes DP/segmentation behavior"
guarantee.

SudachiDict was also considered for a full connection-matrix merge (the
way real ipadic's used to be, before that was superseded -- see "No class
reduction" above), since it's a much larger, actively-maintained modern
lexicon. Investigated properly rather than assumed impossible: fetched
SudachiDict's own `matrix.def` (5,981×5,981 raw context classes -- larger
than mozc's own 2,672) directly from the project's distribution host. But
unlike mozc's `id.def` (a POS-label-string-keyed file), SudachiDict's own
distribution has **no published id→POS-label mapping for those 5,981
context classes** -- Sudachi's own docs say the ids are UniDic-mecab
2.1.2's native numbering, but the actual UniDic 2.1.2 `id.def` (a separate
NINJAL distribution, not part of what SudachiDict ships) wasn't obtained,
and UniDic's short-unit-word POS convention isn't confirmed to align with
mozc's IPADIC-derived one. Attempting the merge without directly verifying
that label alignment would risk a silent mis-alignment -- exactly the kind
of unverified-alignment risk the class-reduction analysis above just
showed can silently wreck accuracy. So this round only integrates
SudachiDict's *vocabulary*, not its connection costs.

Source scope: only SudachiDict's "small" and "core" lexicon tiers (fetched
from the project's own distribution host, see `fetch_sudachi.py`) -- not
"notcore" (the "full" tier), which the project's own docs describe as
"miscellaneous proper nouns", a much larger and noisier long tail. Entries
are filtered to open-class content-word POS categories (名詞/動詞/形容詞/
副詞/連体詞/接頭辞/接尾辞/感動詞/形状詞) with a non-ASCII surface, so
symbols/whitespace/particles/auxiliary-verb entries in the lexicon don't
pollute candidate lists.

Effect (full-spec base, 2026-07-21 data, run after the JMdict fix above):
scanned 1,580,626 content-word lexicon rows (small + core tiers), augmented
78,019 of the 745,964 readings already in `mozc_dict.json` (10.5%), adding
177,201 candidate surfaces total (mozc_dict.json: 35,973,210 →
38,135,419 bytes, +6.0%). Same caps as the JMdict augmentation
(`MAX_NEW_PER_READING=12`, `MAX_TOTAL_CANDIDATES=40`) -- SudachiDict's own
raw scan count and reading-key set are unaffected by the JMdict fix
(SudachiDict's reading field was already hiragana-normalized), but its
*augmented* count is very slightly lower than before (78,145 → 78,019)
because more readings now already have their `MAX_TOTAL_CANDIDATES` room
filled by JMdict's own newly-recovered candidates by the time this script
runs -- combined coverage (JMdict ∪ SudachiDict) is strictly larger than
before the fix.

## Do not hand-patch individual words/sentences here

Every fix above is a *generic, POS-driven or source-level* mechanism, not a
per-word override — that's deliberate. Responding to a specific remaining
miss by adding a per-word exception in `build_mozc_engine.py` or a runtime
override table recreates exactly the per-word tuning loop track A already
has, defeating the reason track B exists (an independent, largely
unmodified-data second opinion, distinct from track A's approach). If a
new failure class is found, look for the generic/structural cause first
(as every fix documented here did) before reaching for a word-specific
patch.

### 2026-07 weakness survey (observed, not acted on)

A pass over plain mozc's misses on TRAIN (`corpus.js`/`corpus2.js`/
`corpus3.js`) surfaced a few recurring homophone-choice patterns, noted here
for whoever picks this up next rather than hand-patched now (see the
warning above -- none of these has an identified generic/POS-level cause
yet, only the surface symptom):

- **雨 context + ふる homophones**: mozc's Viterbi consistently prefers
  振る/振った/振られて over 降る/降った/降られて whenever ふる follows 雨
  (weather-verb sense), e.g. あめがふっている → 雨が振っている (gold: 雨が
  降っている). Recurs across multiple independent sentences, so it's mozc's
  raw cost ordering for this reading, not sentence-specific noise -- but no
  POS-driven fix was identified (both senses are ordinary 動詞 with
  otherwise-unremarkable classes; this isn't the proper-noun/numeral/
  short-span pattern the existing penalties target).
- **たほうがいい idiom**: 方 stays hiragana (ほう) in mozc's output inside
  this construction (寝たほうがいい, 買ったほうがいい) where the corpus
  gold consistently wants 方. Possibly a real ipadic-derived cost gap
  specific to this reading+context rather than something the existing
  short-span/proper-noun/numeral penalties touch.
- **Small-count + counter-word combinations**: ふたつ (二つ) and ごにん
  (五人) lose outright to unrelated kanji homophones (布達, 誤認) rather
  than composing as numeral+counter the way `findMozcNumeralRuns`'s
  existing pre-pass handles larger composed numbers (さんじゅっ→三十). The
  existing numeral pre-pass appears scoped to multi-digit compositions, not
  small numeral+counter pairs -- a possible extension, not attempted here
  since it touches DP-time behavior (the exact area with three prior failed
  rounds, see `applyHybridHintOverride`'s comment block in
  `KanaKanjiConverter.ets`).

None of these were pursued into an actual fix in this round: each would
mean touching `segment()`'s DP-time behavior (cost tables or the runtime
penalty mechanisms), the same territory the three prior hybrid-override
attempts tried and never beat plain mozc with. Flagging the *pattern* here
(not a per-sentence fix) so a future attempt has a documented starting
point instead of re-discovering these from scratch.

## Considered, not yet done

- **SudachiDict's own connection-cost matrix** — see the "SudachiDict
  vocabulary augmentation" section above for why this specifically (not
  SudachiDict as a whole, which *is* now integrated for vocabulary) remains
  undone: it would need UniDic 2.1.2's own `id.def` (NINJAL, a separate
  distribution SudachiDict's own host doesn't carry) to align its
  5,981-class raw matrix with mozc's, plus verification that UniDic's
  short-unit POS convention actually aligns with the IPADIC-derived one
  mozc/JMdict/SudachiDict's own vocabulary side already share. UniDic
  itself is GPL/LGPL/BSD triple-licensed (the BSD option would be usable).
  Real, but a larger, separately-scoped project than a vocabulary
  augmentation.
- **Real mecab-ipadic**, as either a vocabulary augmentation (like JMdict/
  SudachiDict) or a connection-matrix source, was tried as a connection-
  matrix merge in an earlier round and later removed (superseded by the
  unreduced mozc matrix, which measured better -- see "No class reduction"
  above and git history). Using it purely as a vocabulary source (like
  JMdict/SudachiDict) was never attempted; real ipadic's own dictionary is
  smaller and less actively maintained than either JMdict or SudachiDict,
  so this is low priority.

## Files

- `fetch_mozc.py` — downloads mozc's dictionary/connection-matrix/POS-id
  files into `cache/` (gitignored).
- `build_mozc_engine.py` — the actual pipeline: multi-sense dictionary/cost
  table construction (mozc's raw ids used directly, no class reduction),
  pruning, content-class mask. Read its module docstring and inline
  comments for the full rationale behind every design choice
  (MAX_COST/MAX_CANDIDATES_PER_READING/MAX_SENSES_PER_READING pruning, the
  known かん→澗-style data quirks left intentionally unmodified since
  they're mozc's real data, not a bug, and why class reduction was tried
  and rejected).
- `mozc_classes_reference.json` — raw mozc POS id → label lookup, for
  maintainers only; not shipped in the app.
- `fetch_jmdict.py` — downloads and decompresses JMdict's XML dump into
  `cache_jmdict/` (gitignored).
- `build_jmdict_augment.py` — safe-mode candidate-surface augmentation of
  the already-built `mozc_dict.json` (does not touch `mozc_costs.json` /
  `mozc_matrix.json`). Must run after `build_mozc_engine.py`. See "JMdict
  vocabulary augmentation" above.
- `fetch_sudachi.py` — downloads and extracts SudachiDict's "small" and
  "core" lexicon CSVs into `cache_sudachi/` (gitignored).
- `build_sudachi_augment.py` — the same safe-mode candidate-surface
  augmentation as `build_jmdict_augment.py`, sourced from SudachiDict
  instead. Must run after `build_mozc_engine.py`. See "SudachiDict
  vocabulary augmentation" above.
- `pack_strings.py` — repacks the three string tables from JSON into the
  shipped `.blob`/`.len`/`.base`/`.srt` binaries. Reads
  `packed_src/*.json`, writes into `rawfile/`. Run after any rebuild that
  changes those tables. See "On-device format" above.
- `verify_packed.js` — proves `pack_strings.py`'s output is entry-for-entry
  identical to the JSON it replaced (`bun tools/mozc_data/verify_packed.js`).
- `packed_src/` — the JSON originals of the three string tables, kept out of
  `rawfile/` so they aren't packed into the HAP.
- `compare_engines.js` — side-by-side custom-vs-mozc scoring against any
  `tools/ime-eval/` corpus file (`corpus_test10.js` by default). Not a
  regression gate like `tools/ime-eval/regress.js` — track B isn't expected
  to match track A.
