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
node tools/ime-eval/run.js            # summary accuracy
node tools/ime-eval/run.js --misses   # also print every miss (gold vs got)
```

Requires a local `typescript` (`npx tsc`).

## Corpus

- `corpus.js` — everyday sentences, colloquial/casual forms, and readings known
  to surface garbage candidates.
- `corpus2.js` — additional held-out sentences used to validate that a change
  generalizes rather than overfitting.

Natural usage is the target, **not** textbook-correct Japanese: colloquial
readings (`まじでそれなー`, `なんか疲れたわ`) have their casual surface as the gold.
Readings are authored by hand so alignment is exact.

## Workflow

1. `node tools/ime-eval/run.js` to get the current baseline.
2. Change the converter (ranking, segmentation cost, dictionary pruning, …).
3. Re-run. A change ships only if accuracy rises **and** no previously-correct
   labeled sentence regresses (diff the `--misses` output before/after).

Some "misses" are valid homophones of the gold (e.g. `撮った` vs `取った`,
`聞く` vs `聴く`), so real-world quality is a little higher than the raw score.
Extend the corpus whenever a new class of mistake is reported.
