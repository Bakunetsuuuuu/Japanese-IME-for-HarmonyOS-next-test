# Blind (unpredictable) conversion-quality test

A held-out kana→kanji benchmark that **neither this project's authors nor
its tuning could have been fitted to**, unlike the in-house
`tools/ime-eval` corpora (which were hand-authored during development and
which the engines are, to some degree, tuned toward).

## Why it exists

The in-house corpora flatter track A: on `tools/ime-eval` track A scores
~76% strict vs track B's ~68%. But those sentences were written by the same
people who tuned track A. This benchmark removes that bias entirely, and the
result reverses (see below) — track A generalizes *worse* than the
statistical track B on genuinely unseen everyday Japanese.

## How the corpus was built (`build_blind_corpus.py`)

1. **Source text**: a random sample of the [Tatoeba](https://tatoeba.org/)
   Japanese sentence corpus (`jpn_sentences.tsv`, CC-BY 2.0 FR — see
   Attribution). Everyday register (not the encyclopedic, proper-noun-dense
   text a Wikipedia sample gives), from a source unrelated to this project.
2. **Readings from an independent analyzer**: each sentence is tokenised
   with [Janome](https://mocobeta.github.io/janome/) (a pure-Python
   MeCab/IPADIC analyzer — *not* this project's engine and *not* mozc), and
   the per-token readings are concatenated into the hiragana a user would
   actually type (は/へ/を particles kept as spelled, katakana words spelled
   in hiragana). The original sentence surface is the gold answer.
3. **Filtering**: only clean all-kana/kanji sentences, 8–26 reading kana,
   proper-noun ratio capped, no digits/latin/symbols.

Because both the input readings and the gold surfaces come from a neutral
third party, no fix in this repo could have targeted these specific pairs.
The corpus is regenerated fresh each run (fixed RNG seed for reproducibility;
`blind_corpus.json` is a committed snapshot of one such run, 350 pairs).

## Scoring caveat

The "gold" is one arbitrary valid rendering of each sentence. Many
"mismatches" are simply a *different valid* choice (探して vs 捜して, 硬く vs
固く, 誰か vs だれか, 一日 vs １日). So **strict exact-match understates every
engine**, including Google's; the **character-level accuracy** (1 −
normalised edit distance) is the more honest quality signal. The meaningful
comparison is *between* engines scored against the same gold.

## Running it

```sh
node tools/blind-eval/run_ours.js tools/blind-eval/blind_corpus.json ours_out.json
python3 tools/blind-eval/run_google.py     # queries the Google Input Tools API, caches
python3 tools/blind-eval/score.py
```

## Result snapshot (350 sentences)

| engine | strict exact | char-level acc |
|---|---|---|
| track A (custom, hand-tuned) | 126/350 (36.0%) | 85.6% |
| track B (mozc, full-spec) | 192/350 (54.9%) | 92.6% |
| Google Input Tools API | 220/350 (62.9%) | 94.1% |

Uniquely-correct counts: Google 24, track A 12, track B 4; all three exact
on 104; none exact on 113 (of which ~26 are all-engines-close, i.e. just
alternate-valid gold).

## Comparing against Gboard / HUAWEI / Apple / Microsoft IMEs

Only the **Google Input Tools API** can be driven programmatically from a
build environment. It is Google's own kana-kanji engine (same lineage as
Gboard's Japanese input) but is a lighter web endpoint, not necessarily
identical to the on-device Gboard model.

**Gboard's on-device engine, HUAWEI's stock IME, Apple's Japanese IME, and
Microsoft IME have no public conversion API** — they run on-device with no
programmatic entry point. They cannot be scored automatically here, and this
project does not fabricate numbers for them. To benchmark them, run the
`blind_corpus.json` readings through each IME **by hand on a real device**
and diff against the gold column. The corpus file is plain JSON
(`[[reading, gold], ...]`) precisely so it can be used as a manual test
script.

## Attribution

Sentence source: **Tatoeba** (https://tatoeba.org/), released under
**CC-BY 2.0 FR** (https://creativecommons.org/licenses/by/2.0/fr/). The
`blind_corpus.json` snapshot contains derived (reading, surface) pairs from
Tatoeba sentences. Reading annotation by Janome (Apache-2.0). Neither is
shipped in the app; this directory is developer tooling only.
