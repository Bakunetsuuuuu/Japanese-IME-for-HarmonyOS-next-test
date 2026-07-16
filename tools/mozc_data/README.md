# Track B: mozc + real ipadic + JMdict-derived conversion engine

An optional, in-app switchable second conversion engine (settings toggle:
独自辞書/統計データ) built from mozc's (BSD-3-Clause,
https://github.com/google/mozc) open-source dictionary/connection-cost
data, merged with real mecab-ipadic's own connection-cost matrix
(https://github.com/taku910/mecab, NAIST/ICOT license), and augmented with
extra kanji-spelling candidates from JMdict (https://www.edrdg.org/,
CC BY-SA 4.0) -- kept entirely separate from this project's own hand-built
dictionary ("track A": `dict.json` / the inline `DICTIONARY` in
`KanaKanjiConverter.ets` / `getWordInfo`'s hand-tuned cost heuristics). See
the top-level `THIRD_PARTY_NOTICES.md` for the exact license terms this
data carries.

## Regenerating

```sh
python3 tools/mozc_data/fetch_mozc.py           # downloads + caches raw mozc data (not committed)
python3 tools/mozc_data/fetch_ipadic.py         # downloads + caches raw ipadic data (not committed)
python3 tools/mozc_data/build_mozc_engine.py    # writes entry/src/main/resources/rawfile/mozc_*.json
python3 tools/mozc_data/fetch_jmdict.py         # downloads + caches raw JMdict.xml (not committed)
python3 tools/mozc_data/build_jmdict_augment.py # augments mozc_dict.json in place (run LAST, after build_mozc_engine.py)
node tools/mozc_data/compare_engines.js --misses          # custom vs mozc on corpus_test10.js
node tools/mozc_data/compare_engines.js corpus_test9.js   # or any other tools/ime-eval/ corpus
```

Order matters: `build_mozc_engine.py` always regenerates `mozc_dict.json`
from scratch (mozc's dictionary shards + the ipadic merge, if present), so
`build_jmdict_augment.py` -- which only ever edits `mozc_dict.json` in
place -- must run after it, every time. Re-running `build_mozc_engine.py`
alone discards any previous JMdict augmentation; re-run
`build_jmdict_augment.py` again afterward to restore it.

`build_mozc_engine.py` works with just mozc's cache present (skips the
ipadic merge with a note) if `fetch_ipadic.py` hasn't been run -- useful
for quickly regenerating without the ipadic download, though the shipped
data always includes both. Likewise, `build_jmdict_augment.py` skips with a
note if `fetch_jmdict.py`'s cache is absent.

All three caches (`tools/mozc_data/cache/`, `cache_ipadic/`, `cache_jmdict/`
-- ~90MB + ~30MB + ~120MB) are gitignored; only the small derived output
(`entry/src/main/resources/rawfile/mozc_dict.json` /
`mozc_costs.json` / `mozc_matrix.json`, ~17.8MB combined) is committed and
shipped in the app.

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

`mozc_costs.json` now stores every distinct `(reducedLeftClass,
reducedRightClass)` sense a reading has (capped at `MAX_SENSES_PER_READING`,
see `build_mozc_engine.py`), each carrying its own literal surface.
`segment()`'s DP (`KanaKanjiConverter.ets`, the `isMozc` branch) tries every
sense of a span and lets normal cost minimization pick whichever fits
context — the winning sense's surface is threaded through backtrace into an
instance-level hint map (`mozcLastHints`) so `lookupMozc()` shows that exact
sense, not just "whatever's cheapest for the reading with no context."

### Connection matrix: merged with real ipadic

mozc's dictionary_oss is itself IPAdic-derived, but its connection-cost
matrix turns out NOT to be stock ipadic's own matrix — direct comparison
against the real mecab-ipadic source (`fetch_ipadic.py`) found mozc's
authors re-trained/re-costed it, and that re-training made at least one
extremely common, basic grammar pattern noticeably worse: する's 連用形
(e.g. the し in した) connecting to た (past-tense auxiliary) costs 859 in
mozc's matrix but -7956 (strongly preferred) in real ipadic's matrix.def.

`build_mozc_engine.py` now builds BOTH matrices into a shared reduced-class
space (mozc's `id.def` and ipadic's `left-id.def` use the same POS-label
convention despite different raw numeric id spaces, so classes align by
label) and merges them with MIN — but only after a **calibration step**:
mozc shifted its entire cost scale to be non-negative (raw median ~8157)
while real ipadic uses mecab's native convention (raw median ~-115,
negative = strongly preferred). Merging the raw scales directly was tried
first and made results dramatically worse (corpus_test10 strict dropped
from 20% to 5% — ipadic's very negative values made large swaths of the DP
artificially cheap regardless of context). Shifting ipadic's raw values by
a constant so its median matches mozc's before the MIN merge fixed this;
see `build_ipadic_reduced_matrix`'s comment for the exact mechanism.

mozc's own word list / node costs are **not** touched by this merge — only
the connection (edge-cost) matrix mixes in ipadic's data. Merging the
*dictionaries* was deliberately not attempted (mozc's and ipadic's raw
*node*-cost scales for the same word differ by 1-2 orders of magnitude in
spot checks, and naively pooling both sources' dictionary entries into one
cost-sorted list would let that scale mismatch silently bias which sense
wins — a worse failure mode than not merging at all).

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
  `HIRA_MARGIN`): when a class has both a katakana-lexeme entry and a
  same-cost-ballpark entry whose surface is literally the reading itself,
  prefer the hiragana one. Fixed です defaulting to デス (both exist in
  mozc's raw data at nearly the same cost, same 助動詞,特殊・デス,基本形
  sense) — verified this pattern recurs across ~29 reduced-class groups
  (ござる/ゴザル, べし/ベシ, …), not a です-only patch.

### Measured effect

`compare_engines.js` strict-match rate:

| Corpus | track A (unchanged throughout) | track B, sense-aware Viterbi only | track B, + ipadic matrix merge |
|---|---|---|---|
| `corpus_test10.js` (20 sentences) | 16/20 (80.0%) | 4/20 (20.0%) | 6/20 (30.0%) |
| `corpus_test9.js` (49 sentences, 16 registers) | 35/49 (71.4%) | 9/49 (18.4%) | 13/49 (26.5%) |

(Original baseline before any of this round's changes: 2/20 and not
measured, respectively.) Real, verified, cumulative improvement, and
per-token quality improved further than the strict-sentence-match number
alone shows — several sentences that still don't strict-match now differ
from gold by one homophone/vocabulary choice (とった vs 撮った) rather than a
garbled mis-segmentation. `じゅんびした` → `準備した` (the original diagnosed
failure that motivated the ipadic merge) is now fixed.

**This is still not "Gboard-adjacent" quality.** mozc's own OSS README
(`dictionary_oss/README.txt`, fetched by `fetch_mozc.py`) states its
bundled dictionary explicitly excludes "the large vocabulary set generated
from the Web corpus" that the real Google Japanese Input / Gboard engines
use — real ipadic doesn't have that either. There is a hard vocabulary
ceiling here that connection-matrix or Viterbi engineering alone can't
remove (see "JMdict vocabulary augmentation" below for one further step
taken, and "Considered, not yet done" for what wasn't). Track B should
currently be understood as "a genuine second opinion with real, measurably
improving quality," not a recommended daily-driver replacement for track A.

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
for sentences containing that reading, and a mixing of two independently-
scaled cost sources (mozc/ipadic's calibrated matrix vs. an ad-hoc fallback)
exactly like the dictionary-merge risk already avoided in the connection-
matrix section above. Restricting augmentation to already-known readings
avoids all of that: `inDict`/`getWordInfoCandidatesMozc`/segment()'s DP see
exactly the same set of DP-eligible spans before and after augmentation.
Only `lookup()`/`lookupMozc()`'s candidate *list* for an already-recognised
reading grows — e.g. more kanji options when cycling candidates for a
reading typed and converted on its own.

Effect (this round): scanned 258,109 JMdict reading/kanji pairs, augmented
11,859 of the 137,869 readings already in `mozc_dict.json` (8.6%), adding
20,913 candidate surfaces total (mozc_dict.json: 7,360,801 → 7,586,929
bytes, +3.1%). Per-reading additions are capped (`MAX_NEW_PER_READING=12`
new surfaces, `MAX_TOTAL_CANDIDATES=40` overall per reading) and ordered
with JMdict's own priority-tagged (news1/ichi1/spec1/spec2/gai1) spellings
first, since JMdict carries no cost/frequency number the way mozc's
dictionary does. `compare_engines.js` strict-match rate is unchanged by
this step (confirmed: 6/20 and 13/49, identical to the ipadic-matrix-merge
numbers above) — expected, since it doesn't touch what the DP scores, only
what a resolved reading can additionally display.

## Do not hand-patch individual words/sentences here

Every fix above is a *generic, POS-driven or source-level* mechanism, not a
per-word override — that's deliberate. Responding to a specific remaining
miss by adding a per-word exception in `build_mozc_engine.py` or a runtime
override table recreates exactly the per-word tuning loop track A already
has, defeating the reason track B exists (an independent, largely
unmodified-data second opinion, distinct from track A's approach). If a
new failure class is found, look for the generic/structural cause first
(as both fixes in this round did) before reaching for a word-specific
patch.

## Considered, not yet done

- **SudachiDict** (Apache-2.0, https://github.com/WorksApplications/SudachiDict)
  — a much larger, actively-maintained modern vocabulary. Investigated this
  round and deferred: SudachiDict's lexicon has no connection-cost matrix of
  its own — its connection ids explicitly reference "unidic-mecab 2.1.2's
  left-id.def" (per Sudachi's own docs), a *different* project (UniDic,
  NINJAL, GPL/LGPL/BSD triple-licensed — the BSD option is usable) with its
  own raw id space requiring the same class-alignment-by-label-string
  treatment as the ipadic merge above, plus locating and downloading the
  exact matching UniDic version's matrix. Real, but larger and riskier than
  what this round's budget covered — the two sources actually integrated
  this round (mozc, real ipadic) were lower-risk and higher-confidence.
- **Unreduced (2,672-class) mozc connection matrix** instead of the current
  ~723-class MIN-aggregated reduction (mozc's ~585 + ipadic's ~138 new
  classes) — would cost roughly 2.5MB → ~34MB for `mozc_matrix.json`.
  Deferred because diagnosed failures this round were sense-selection,
  short-span-noise, and matrix-source-calibration issues (now addressed)
  rather than reduction-granularity artifacts — but if a future round's
  diagnosis points at the reduction itself, this is the lever to pull.

## Files

- `fetch_mozc.py` — downloads mozc's dictionary/connection-matrix/POS-id
  files into `cache/` (gitignored).
- `fetch_ipadic.py` — downloads real mecab-ipadic's POS-category CSV
  source files, connection matrix, and id definitions into `cache_ipadic/`
  (gitignored).
- `build_mozc_engine.py` — the actual pipeline: shared POS-class-registry
  reduction across both sources, connection-matrix reduction/calibration/
  merge, multi-sense dictionary/cost table construction (mozc only),
  pruning, content-class mask. Read its module docstring and inline
  comments for the full rationale behind every design choice (class
  reduction granularity, MAX_COST/MAX_CANDIDATES_PER_READING/
  MAX_SENSES_PER_READING pruning, the known かん→澗-style data quirks left
  intentionally unmodified since they're mozc's real data, not a bug).
- `mozc_classes_reference.json` — reduced-class-id → POS-label lookup, for
  maintainers only; not shipped in the app.
- `fetch_jmdict.py` — downloads and decompresses JMdict's XML dump into
  `cache_jmdict/` (gitignored).
- `build_jmdict_augment.py` — safe-mode candidate-surface augmentation of
  the already-built `mozc_dict.json` (does not touch `mozc_costs.json` /
  `mozc_matrix.json`). Must run after `build_mozc_engine.py`. See "JMdict
  vocabulary augmentation" above.
- `compare_engines.js` — side-by-side custom-vs-mozc scoring against any
  `tools/ime-eval/` corpus file (`corpus_test10.js` by default). Not a
  regression gate like `tools/ime-eval/regress.js` — track B isn't expected
  to match track A.
