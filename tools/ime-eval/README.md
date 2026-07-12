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
node tools/ime-eval/run_test.js           # held-out TEST summary accuracy
node tools/ime-eval/run_test.js --misses  # also print every miss
```

Requires a local `typescript` (`npx tsc`).

## Train/test split

`run.js` (corpus.js/corpus2.js/corpus3.js) is the **train** set: the one
actually used to decide what to fix. `run_test.js` (corpus_test.js/
accept_test.js) is a separately-authored **held-out test** set — never used to
pick or shape a fix, only to check the result afterward. This matters because
tuning repeatedly against one small corpus makes it stop measuring
generalization: an earlier round of this converter scored 89% against a
130-sentence corpus it had been tuned against, but only 70% against a larger
held-out corpus of the same difficulty. Keep that separation when adding
cases — a bug found via corpus_test.js should be fixed by reasoning about the
general rule (or by adding the fix to the train corpus for regression
coverage), not by hand-tuning to the exact test sentence.

## Corpus

- `corpus.js` — everyday sentences, colloquial/casual forms, and readings known
  to surface garbage candidates.
- `corpus2.js` — additional held-out sentences used to validate that a change
  generalizes rather than overfitting.
- `corpus3.js` — a larger, independently-authored held-out corpus (news/forum
  register plus more grammar patterns: passive/causative/potential forms,
  questions, counters) for the same generalization check at greater scale.
- `accept.js` — per-reading map of *additional* valid natural-Japanese outputs
  (okurigana / kana-kanji / standard homophones the IME can't disambiguate
  without context). Garbage is never listed here.
- `corpus_test.js` / `accept_test.js` — the held-out TEST set (see above).
  Same format as corpus.js/accept.js, kept in separate files so it's obvious
  which corpus a given tuning session is/isn't allowed to look at.

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
