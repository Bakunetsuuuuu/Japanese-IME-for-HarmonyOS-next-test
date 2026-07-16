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
python3 tools/mozc_data/build_mozc_engine.py     # writes entry/src/main/resources/rawfile/mozc_*.json
python3 tools/mozc_data/fetch_jmdict.py          # downloads + caches raw JMdict.xml (not committed)
python3 tools/mozc_data/build_jmdict_augment.py  # augments mozc_dict.json in place (run AFTER build_mozc_engine.py)
python3 tools/mozc_data/fetch_sudachi.py         # downloads + caches SudachiDict lexicon CSVs (not committed)
python3 tools/mozc_data/build_sudachi_augment.py # augments mozc_dict.json in place (run AFTER build_mozc_engine.py)
node tools/mozc_data/compare_engines.js --misses          # custom vs mozc on corpus_test10.js
node tools/mozc_data/compare_engines.js corpus_test9.js   # or any other tools/ime-eval/ corpus
```

Order matters: `build_mozc_engine.py` always regenerates `mozc_dict.json`
from scratch (mozc's dictionary shards only), so both augmentation
scripts -- which only ever edit `mozc_dict.json` in place, appending
surfaces -- must run after it, every time. The two augmentation scripts
can run in either order relative to each other. Re-running
`build_mozc_engine.py` alone discards any previous JMdict/SudachiDict
augmentation; re-run both augmentation scripts again afterward to restore
it.

Each augmentation script skips with a note if its own fetch script's cache
is absent.

All three caches (`tools/mozc_data/cache/`, `cache_jmdict/`, `cache_sudachi/`
-- ~90MB + ~120MB + ~270MB) are gitignored; only the derived output
(`entry/src/main/resources/rawfile/mozc_dict.json` / `mozc_costs.json` /
`mozc_matrix.json`, ~52MB combined -- see "No class reduction" below for
why `mozc_matrix.json` alone is ~36.5MB of that) is committed and shipped
in the app.

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

| Corpus | track A (unchanged throughout) | sense-aware Viterbi only | + real-ipadic matrix merge (removed) | + no class reduction (current) |
|---|---|---|---|---|
| `corpus_test10.js` (20 sentences) | 16/20 (80.0%) | 4/20 (20.0%) | 6/20 (30.0%) | **12/20 (60.0%)** |
| `corpus_test9.js` (49 sentences, 16 registers) | 35/49 (71.4%) | 9/49 (18.4%) | 13/49 (26.5%) | **20/49 (40.8%)** |

(Original baseline before any track B accuracy work: 2/20 and not
measured, respectively.) The jump from removing class reduction is the
single largest improvement of any change made to track B so far — roughly
doubling strict-match rate over the reduced+ipadic-merged version, and
fixing the case that motivated the (now-removed) ipadic merge in the first
place (じゅんびした → 準備した). Remaining misses are now overwhelmingly
homophone/vocabulary choices (とった vs 撮った, ふる vs 降る) rather than
garbled mis-segmentations — real, qualitative improvement beyond what the
strict-match number alone shows.

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

Effect: scanned 258,109 JMdict reading/kanji pairs, augmented 11,859 of the
137,869 readings already in `mozc_dict.json` (8.6%), adding 20,913
candidate surfaces total (mozc_dict.json: 7,360,801 → 7,586,929 bytes,
+3.1%). Per-reading additions are capped (`MAX_NEW_PER_READING=12` new
surfaces, `MAX_TOTAL_CANDIDATES=40` overall per reading) and ordered with
JMdict's own priority-tagged (news1/ichi1/spec1/spec2/gai1) spellings
first, since JMdict carries no cost/frequency number the way mozc's
dictionary does.

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

Effect: scanned 1,580,626 content-word lexicon rows (small + core tiers),
augmented 38,286 of the 137,869 readings already in `mozc_dict.json`
(27.8%), adding 106,032 candidate surfaces total (mozc_dict.json:
7,586,929 → 8,836,108 bytes, +16.5%). Same caps as the JMdict augmentation
(`MAX_NEW_PER_READING=12`, `MAX_TOTAL_CANDIDATES=40`).

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
- `compare_engines.js` — side-by-side custom-vs-mozc scoring against any
  `tools/ime-eval/` corpus file (`corpus_test10.js` by default). Not a
  regression gate like `tools/ime-eval/regress.js` — track B isn't expected
  to match track A.
