# IME conversion-accuracy harness

Offline evaluation of the kana→kanji converter, for iterating on conversion
quality with a measurable target instead of guesswork.

`KanaKanjiConverter.ets` has no ArkTS-only runtime dependencies, so it runs as
plain TypeScript under Node. `run.js` transpiles it on the fly, loads the real
bundled dictionaries (`entry/src/main/resources/rawfile/{dict,global_dict}.json`),
reproduces the app's default sentence conversion
(`KeyboardController.updateCandidates` → `candidate[0]`), and scores it against a
labeled corpus of natural Japanese `[reading, goldSurface]` pairs.

## Run

```sh
node tools/ime-eval/run.js            # TRAIN summary accuracy
node tools/ime-eval/run.js --misses   # also print every miss (gold vs got)
node tools/ime-eval/run_test.js           # held-out TEST summary accuracy (rounds 1-6, see below)
node tools/ime-eval/run_test.js --misses  # also print every miss
node tools/ime-eval/run_vocab.js           # bare single-word dictionary coverage check
node tools/ime-eval/run_vocab.js --misses  # also print every miss
```

Requires a local `typescript` (`npx tsc`).

## Train/test split — and its limits

`run.js` (corpus.js/corpus2.js/corpus3.js) is the **train** set: the one
actually used to decide what to fix. `run_test*.js` (corpus_test*.js/
accept_test*.js) are **held-out test** sets — never used to pick or shape a
fix, only to check the result afterward. This matters because tuning
repeatedly against one small corpus makes it stop measuring generalization:
an earlier round of this converter scored 89% against a 130-sentence corpus
it had been tuned against, but only 70% against a larger held-out corpus of
the same difficulty.

**A single held-out corpus is not enough if the same person writes both the
fixes and the test sentences.** Round 1 (`corpus_test.js`) turned out to
overlap in spirit with words patched the same session that authored it — no
literal sentence duplication, but 30% of its sentences directly exercised a
word just patched, which quietly inflates the score without proving anything
generalizes. Two mitigations are in place:

1. **Rotate the corpus every round.** `corpus_test2.js` through
   `corpus_test6.js` were each measured exactly once, *before* any fix aimed at
   that round's failures, to get an honest baseline; after fixing, that
   corpus is "spent" (informative, but no longer blind) and the next round
   uses a fresh one. Don't keep re-measuring against the same held-out file
   round after round while tuning — write a new one.
2. **Prefer corpora whose *wording* isn't yours.** `corpus_test6.js` is
   sampled from the [Tatoeba Project](https://tatoeba.org) (CC BY 2.0 FR),
   real sentences from independent contributors — only the hiragana reading
   column was transcribed by hand for this project, not the sentence content
   itself. This is more rigorous than corpus_test.js–corpus_test5.js (all
   hand-authored by whoever was doing the fixing that session), which still
   carries an unconscious vocabulary-selection bias even when no fix is
   deliberately targeted. Prefer sourcing more real-corpus sentences (with a
   compatible license) over hand-authoring when starting a new round.
   Tatoeba itself skews toward polite/textbook-style example sentences,
   though, not genuine casual speech — `corpus_test7.js` instead samples the
   [Open 2channel Dialogue Corpus](https://github.com/1never/open2ch-dialogue-corpus)
   (Apache 2.0), real casual message-board conversation, and scores
   noticeably lower (22.7% first-measurement) than the more formal-register
   sources. That gap is itself informative: this converter's dictionary/
   grammar coverage is much better tuned to neutral/written register than to
   live colloquial speech, and any accuracy number should be read alongside
   *what register the test corpus is drawn from*, not as a single scalar.

Even with both mitigations, expect the *first-measurement* score on a fresh
round to land well below any previously-reported number — that gap is the
honest one. Fixing what a fresh corpus reveals is legitimate; re-running the
*same* corpus after patching it and reporting the new number as if it were
still a blind measurement is not.

## Corpus

- `corpus.js` / `corpus2.js` / `corpus3.js` / `accept.js` — the TRAIN set (see
  above).
- `corpus_test.js` … `corpus_test6.js` (with matching `accept_test*.js`) —
  successive held-out TEST rounds, each authored/sourced fresh and measured
  once before any fix targeted it. Treat all of them as "spent" (no longer
  blind) once a fix round has run against them; write a new one for the next
  round rather than reusing.
- `vocab_test.js` / `run_vocab.js` — a separate check: ~250 common everyday
  N5–N3 words as bare single-reading `lookup()` calls (not sentences), to
  measure raw dictionary/ranking coverage independent of segmentation.

Two metrics are reported:
- **strict** — output equals the one authored gold exactly.
- **lenient** — output is the gold *or* any alternate in `accept.js`; i.e. "did
  it produce valid, natural Japanese". This is the number to optimize, since
  many readings have several equally-correct surfaces.

Natural usage is the target, **not** textbook-correct Japanese: colloquial
readings (`まじでそれなー`, `なんか疲れたわ`) have their casual surface as the gold.
Readings are authored by hand so alignment is exact.

## Where the converter encodes this

`KanaKanjiConverter` carries a few small lexicons/tables that feed conversion
quality — extend these, plus the segmentation cost constants in `getWordInfo` /
`buildConnectionMatrix`, when the harness surfaces a new class of mistake:

- `COMMON_READINGS` — a frequency signal for *segmentation*: common words beat
  a rare-kanji fragment split of the same span.
- `COMMON_WORDS` — a ranking boost for specific *candidate surface forms*,
  regardless of which dictionary source produced them.
- `COLLOQUIAL_KANA` — well-known slang forced to its natural kana form.
- `COLLOCATION_HINTS` — object→verb disambiguation within one phrase
  (`かさをかいた`→買った, not 書いた/飼った), keyed by "noun|verbReading".
- `ADJACENT_PAIR_HINTS` — two segments that read as a different compound
  together than either would alone, used by `findAlternateSegmentation`.
- `ALT_SEG_WORDS` — a curated "both sides are real words" gate for
  `findAlternateSegmentation`'s alternate-segmentation candidate (offers a
  second, differently-split parse — e.g. へんかんせいど as one compound entry
  →変換精度 vs the へんかん+せいど split →返還制度). Deliberately kept separate
  from `COMMON_READINGS`: folding words in there changes the *default*
  segmentation too, not just this opt-in secondary candidate.
- `PredictivePhrases.ets` — prefix-matched completion for common greetings/
  set phrases (あけまし→あけましておめでとうございます), independent of the
  regular whole-reading dictionary lookup.

## Workflow

1. `node tools/ime-eval/run.js` to get the current baseline.
2. Change the converter (ranking, segmentation cost, dictionary pruning, …).
3. Re-run. A change ships only if accuracy rises **and** no previously-correct
   labeled sentence regresses (diff the `--misses` output before/after).

Some "misses" are valid homophones of the gold (e.g. `撮った` vs `取った`,
`聞く` vs `聴く`), so real-world quality is a little higher than the raw score.
Extend the corpus whenever a new class of mistake is reported.
