# Track B: mozc-derived conversion engine

An optional, in-app switchable second conversion engine (settings toggle:
独自辞書/統計データ) built from mozc's (BSD-3-Clause,
https://github.com/google/mozc) open-source dictionary and connection-cost
data, kept entirely separate from this project's own hand-built dictionary
("track A": `dict.json` / the inline `DICTIONARY` in `KanaKanjiConverter.ets`
/ `getWordInfo`'s hand-tuned cost heuristics). See the top-level
`THIRD_PARTY_NOTICES.md` for the exact license terms this data carries.

## Regenerating

```sh
python3 tools/mozc_data/fetch_mozc.py         # downloads + caches raw mozc data (not committed)
python3 tools/mozc_data/build_mozc_engine.py  # writes entry/src/main/resources/rawfile/mozc_*.json
node tools/mozc_data/compare_engines.js --misses          # custom vs mozc on corpus_test10.js
node tools/mozc_data/compare_engines.js corpus_test9.js   # or any other tools/ime-eval/ corpus
```

`fetch_mozc.py`'s cache (`tools/mozc_data/cache/`, ~90MB) is gitignored;
only `build_mozc_engine.py`'s small derived output
(`entry/src/main/resources/rawfile/mozc_dict.json` /
`mozc_costs.json` / `mozc_matrix.json`, ~16.7MB combined) is committed and
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

### Sense-aware Viterbi (the main structural fix this round)

The first version of this track collapsed every dictionary entry sharing a
reading down to a single representative `(cost, leftClass, rightClass)`
triple (whichever was globally cheapest). That was diagnosed as the primary
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

Two further generic (POS-driven, not per-word) mitigations, both verified
empirically against `compare_engines.js`:
- **Short-span content-word penalty** (`MOZC_SINGLE_CONTENT_PENALTY`,
  `KanaKanjiConverter.ets`): a 1-2 character span almost always has *some*
  dictionary sense (mozc has the same raw kanji-homophone-dump problem per
  short reading that the hand-built dictionary had before
  `reorder_kana_dumps.py` cleaned it up), so an unpenalized open-class
  content sense here frequently steals a short span from what should have
  been part of a longer word. Mirrors track A's own `singleContentPenalty`.
  Only applies to open-class POS (`contentClassMask` in `mozc_matrix.json`:
  名詞/動詞/形容詞/副詞/連体詞/接頭詞) — a genuine short particle/auxiliary
  (は/を/に/した=する's past/ます/…) must stay cheap.
- **Hiragana-preference tie-break within a class** (`build_dict_and_costs`,
  `HIRA_MARGIN`): when a class has both a katakana-lexeme entry and a
  same-cost-ballpark entry whose surface is literally the reading itself,
  prefer the hiragana one. Fixed です defaulting to デス (both exist in
  mozc's raw data at nearly the same cost, same 助動詞,特殊・デス,基本形
  sense) — verified this pattern recurs across ~29 reduced-class groups
  (ござる/ゴザル, べし/ベシ, …), not a です-only patch.

### Measured effect

`compare_engines.js` strict-match rate, same corpora before/after this
round's changes:

| Corpus | track A (unchanged) | track B before | track B after |
|---|---|---|---|
| `corpus_test10.js` (20 sentences) | 16/20 (80.0%) | 2/20 (10.0%) | 4/20 (20.0%) |
| `corpus_test9.js` (49 sentences, 16 registers) | 35/49 (71.4%) | not measured | 9/49 (18.4%) |

Real, verified improvement (2x), and per-token quality improved further
than the strict-sentence-match number alone shows — several sentences that
still don't strict-match now differ from gold by one homophone/vocabulary
choice (とった vs 撮った, わたし vs 私) rather than a garbled mis-segmentation.
**This is not "Gboard-adjacent" quality** and further tuning-as-usual won't
close that gap (see below) — track B should currently be understood as "a
genuine second opinion with real but limited quality," not a recommended
daily-driver replacement for track A.

## Known remaining limitation (read before extending further)

The dominant remaining failure pattern (`じゅんびした` → `準備下` instead of
`準備した`) is **not fixable by more Viterbi engineering** — verified by
reading mozc's raw, *unreduced* `connection_single_column.txt` directly:
raw id 638 (する's 連用形, exactly the sense needed) really does connect to
raw id 142 (た, the auxiliary) at cost 859, while 準備(noun) → した(a
noun-suffix reading of 下) connects at cost 173. This is mozc's own
authentic trained statistic, not a reduction artifact or a pipeline bug —
confirmed by checking the *raw* (pre-class-reduction) matrix cell directly,
not the reduced one. Two deeper reasons this class of issue persists:

1. `dictionary00.txt`..`dictionary09.txt` (mozc's plain-text dictionary
   export) has no precomposed "した" entry tagged as a conjugated form of
   する at all — only unrelated noun senses (下/志多/…). A real mecab/ipadic
   *compiled* dictionary generates every conjugated surface from paradigm
   templates at compile time; that expansion machinery lives outside the
   flat text files this pipeline reads. Even with the sense-aware DP now
   correctly finding raw id 638 for "し", the connection cost into it is
   real mozc data, not something this pipeline is getting wrong.
2. mozc's own OSS README (`dictionary_oss/README.txt`, fetched by
   `fetch_mozc.py`) states its bundled dictionary explicitly **excludes**
   "the large vocabulary set generated from the Web corpus" that the real
   Google Japanese Input / Gboard engines use. There is a hard vocabulary
   and training-data ceiling here that no amount of engineering against
   this exact data source will remove.

**Do not respond to either of these by hand-patching individual
sentences/readings in `build_mozc_engine.py` or via a runtime override
table** — that recreates exactly the per-word tuning loop track A already
has, defeating the reason track B exists (an independent, unmodified-data
second opinion). If pushing quality further is worth it in a future round,
the right next steps are structural, not per-word:
- Fetching real mecab-ipadic conjugation-template source data (not mozc's
  already-compiled OSS export) to properly generate missing conjugated
  forms like した.
- A larger/richer open dictionary source than mozc OSS's IPAdic-based
  vocabulary (e.g. SudachiDict, Apache-2.0) layered in as additional raw
  input to `build_mozc_engine.py`, still processed through the same
  generic, unmodified pipeline.
- Not attempted this round: using the *unreduced* 2,672-class connection
  matrix instead of the ~586-class MIN-aggregated reduction, which would
  cost roughly 1.6MB → ~34MB for `mozc_matrix.json`. Deferred because the
  concretely diagnosed failures this round turned out to be sense-selection
  and short-span-noise issues (now fixed) rather than matrix-reduction
  artifacts — but if a future round's diagnosis points at the reduction
  itself, this is the lever to pull.

## Files

- `fetch_mozc.py` — downloads mozc's dictionary/connection-matrix/POS-id
  files into `cache/` (gitignored).
- `build_mozc_engine.py` — the actual pipeline: POS-class reduction,
  connection-matrix reduction, multi-sense dictionary/cost table
  construction, pruning, content-class mask. Read its module docstring and
  inline comments for the full rationale behind every design choice
  (class reduction granularity, MAX_COST/MAX_CANDIDATES_PER_READING/
  MAX_SENSES_PER_READING pruning, the known かん→澗-style data quirks left
  intentionally unmodified since they're mozc's real data, not a bug).
- `mozc_classes_reference.json` — reduced-class-id → POS-label lookup, for
  maintainers only; not shipped in the app.
- `compare_engines.js` — side-by-side custom-vs-mozc scoring against any
  `tools/ime-eval/` corpus file (`corpus_test10.js` by default). Not a
  regression gate like `tools/ime-eval/regress.js` — track B isn't expected
  to match track A.
