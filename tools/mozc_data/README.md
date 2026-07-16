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
node tools/mozc_data/compare_engines.js --misses   # custom vs mozc on corpus_test10
```

`fetch_mozc.py`'s cache (`tools/mozc_data/cache/`, ~90MB) is gitignored;
only `build_mozc_engine.py`'s small derived output
(`entry/src/main/resources/rawfile/mozc_dict.json` /
`mozc_costs.json` / `mozc_matrix.json`, ~13.8MB combined) is committed and
shipped in the app.

## How it plugs in

`KanaKanjiConverter` has a static `engine: 'custom' | 'mozc'` flag. When it's
`'custom'` (the default), every existing method runs completely unchanged —
this is verified every time via `tools/ime-eval/run_all.js` /
`sweep.js` / `regress.js` showing byte-identical results to before this
track existed. When `'mozc'`, four entry points
(`inDict`/`getWordInfo`/`getEdgeCost`/`lookup`) dispatch to mozc-specific
counterparts at their very top, and `segment()`'s Viterbi DP (unmodified
itself) automatically becomes engine-aware through them. See the `engine`
field's comment block in `KanaKanjiConverter.ets` for the full design.

## Known quality limitation (read before extending)

**Track B's out-of-the-box segmentation quality on connected sentences is
currently well below track A's** (first measurement on
`tools/ime-eval/corpus_test10.js`: 2/20 strict vs. track A's 16/20 — see
`compare_engines.js`). This is not a bug in the pipeline; it's a genuine
structural gap discovered during validation:

`dictionary00.txt`..`dictionary09.txt` (mozc's plain-text dictionary export)
list each verb largely by its base/dictionary form (基本形) plus whichever
conjugated surfaces happened to be scraped from the web corpus, **not** a
full paradigm expansion. A real mecab/ipadic-based tokenizer generates every
conjugated surface (未然形/連用形/仮定形/…) from a small set of conjugation
templates at dictionary *compile* time — that expansion machinery lives
outside the flat text files this pipeline reads, and wasn't pulled in here.
Concretely verified case: じゅんびした ("prepared") should segment as
準備(noun) + し(する's 連用形, raw id 638) + た(auxiliary), but raw id 638's
reading "し" ties at cost 0 with an unrelated 助詞 sense of the same
reading, and even after preferring it, 準備 → し's edge cost apparently
doesn't connect as naturally as 準備 → した (a noun-suffix homograph reading
下), so the DP still prefers the wrong path. Fixing this properly needs
either genuine conjugation-expansion data (fetching mecab-ipadic's raw
templates rather than mozc's already-compiled export) or a
sense-aware Viterbi node (segment() only tracks reading spans, not which
literal sense within a reading was intended) — both are real engineering
projects, not a quick patch.

Two narrow, *generic* (not per-word) mitigations already applied in
`build_mozc_engine.py`, both kept because they're principled POS-driven
filters rather than word-specific hand-tuning:
- MIN (not mean) cost aggregation when reducing mozc's 2,672 raw POS ids
  down to ~585 classes (mean systematically overcosted common connections
  like 名詞+です by averaging in unrelated costlier siblings).
- Preferring a non-文語 (classical/literary Japanese) sense as a reading's
  representative cost/class when a modern sense also exists.

**Do not respond to this by hand-patching individual sentences/readings in
`build_mozc_engine.py` or via a runtime override table** — that recreates
exactly the per-word tuning loop track A already has, defeating the reason
track B exists (an independent, unmodified-data second opinion). If this is
worth improving further, the right next steps are either sourcing real
conjugation-expansion data, or making `segment()`'s DP sense-aware (a
structural change affecting both engines, needing its own isolated design
and validation pass) — not spot-fixes here.

## Files

- `fetch_mozc.py` — downloads mozc's dictionary/connection-matrix/POS-id
  files into `cache/` (gitignored).
- `build_mozc_engine.py` — the actual pipeline: POS-class reduction,
  connection-matrix reduction, dictionary/cost table construction, pruning.
  Read its module docstring and inline comments for the full rationale
  behind every design choice (class reduction granularity, MAX_COST/
  MAX_CANDIDATES_PER_READING pruning, the known かん→澗/です→デス-style data
  quirks left intentionally unmodified).
- `mozc_classes_reference.json` — reduced-class-id → POS-label lookup, for
  maintainers only; not shipped in the app.
- `compare_engines.js` — side-by-side custom-vs-mozc scoring against
  `tools/ime-eval/corpus_test10.js`. Not a regression gate like
  `tools/ime-eval/regress.js` — track B isn't expected to match track A.
