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

### 実文コーパス (Tatoeba, 約42k文)

手書きの corpus*.js は小さく(~1.2k)、修正と同時に書かれたものが多いので、
既知の良い挙動を確認する用途に寄っている。こちらはこのIMEを知らない人が
書いた外部の文なので、点数は大きく下がる代わりに正直で、バグ発見に向く。

```sh
node tools/ime-eval/fetch_real_corpus.js    # Tatoeba を cache_real/ に取得(gitignore)
node tools/ime-eval/build_real_corpus.js    # 読みを復元して [読み,表記] に変換
node tools/ime-eval/run_real.js --rank      # 誤りを頻度順に集計 ← これを見て直す
```

### 同音異義語だけを採点する (run_homophone.js)

実文の残る差の大半が表記の好み(事/こと、時/とき)になった段階では、文全体の
一致率は鈍い。同音語の選択を1つ直しても％がほとんど動かず、逆に表記の好みに
合わせにいくと変換の質が下がる。

```sh
node tools/ime-eval/run_homophone.js --rank        # 読みごとの誤り内訳
node tools/ime-eval/run_homophone.js --reading きく # 特定の読みの実例
```

判定の単位を「文」から「1回の同音語選択」に落とす。実文で漢字表記が2種類以上
使われている読みだけを対象にするので、表記ゆれは自動的に外れ、点数がそのまま
「文脈から正しい同音語を選べた割合」になる。

**注意**: Tatoeba は翻訳・文語寄りで、口語や現代的な用法とはズレる。実際
「起こる107対怒る20」「後悔49対公開5」と出るが、どちらも既定を寄せると
反対側(別に怒ってない/更新が公開された)が壊れることを測定で確認している。
頻度は候補であって結論ではない。

`--rank` は各誤りの差分だけを取り出して頻度順に並べる。表記ゆれ(事/こと、
時/とき)は**両方向に**現れるので書き手の流儀と判別でき、片側だけが別語に
なっている行が実バグ。データは取得のみでコミットしない(Tatoeba は CC BY 2.0 FR、
アプリにも同梱しない)。


```sh
node tools/ime-eval/run.js            # TRAIN summary accuracy
node tools/ime-eval/run.js --misses   # also print every miss (gold vs got)
node tools/ime-eval/run_test.js           # held-out TEST summary accuracy (rounds 1-11, see below)
node tools/ime-eval/run_test.js --misses  # also print every miss
node tools/ime-eval/run_vocab.js           # bare single-word dictionary coverage check
node tools/ime-eval/run_vocab.js --misses  # also print every miss
node tools/ime-eval/run_all.js        # one build, every corpus (TRAIN/TEST1-11/VOCAB1-3) -- fastest way to get a full picture
node tools/ime-eval/sweep.js          # 4000-key dict-sampling old(HEAD)-vs-new(working tree) kanji-loss check
node tools/ime-eval/sweep_join.js     # same, but sampling concatenated dict-key PAIRS -- see "Regression tooling" below
node tools/ime-eval/regress.js        # classifies every corpus row that changed into FIXED/REGRESSED/CHANGED_STILL_WRONG
node tools/ime-eval/run_learning.js   # 文節-level learning: teaching a word via one sentence generalizes to others
node tools/ime-eval/run_candidates.js # positions 1+ offer useful homophone/parse alternatives, not katakana/kana junk
```

Note: the corpus scripts above never call `recordChoice`/`recordSegmentedChoice`,
so they measure the converter with an **empty** learning store — a deliberate
choice so accuracy numbers reflect the base dictionary/segmentation, not
whatever a test happened to teach first. `run_learning.js` is the separate
check for the learning layer itself.

Requires a local `typescript` (`npx tsc`). `run_test2.js` … `run_test11.js` and
`run_vocab2.js`/`run_vocab3.js` follow the same naming pattern as `run_test.js`/
`run_vocab.js` for the later rounds.

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
- `corpus_test.js` … `corpus_test11.js` (with matching `accept_test*.js`) —
  successive held-out TEST rounds, each authored/sourced fresh and measured
  once before any fix targeted it. Treat all of them as "spent" (no longer
  blind) once a fix round has run against them; write a new one for the next
  round rather than reusing. `corpus_test9.js` was promoted from a
  49-sentence, 16-register benchmark (news/business/casual/recipe/weather/
  travel/shopping/health/tech/sports/finance/school/family/entertainment/
  nature) authored specifically to cover registers the contemporaneous
  "LONGTEXT" tuning loop hadn't touched; see its header comment for its
  own spent/first-measurement history before reusing it as if still blind.
- `vocab_test.js` / `run_vocab.js` — a separate check: ~250 common everyday
  N5–N3 words as bare single-reading `lookup()` calls (not sentences), to
  measure raw dictionary/ranking coverage independent of segmentation.
- `corpus_test10.js` — authored fresh, not reused from TEST1-9. Doubles as
  the held-out corpus for `tools/mozc_data/compare_engines.js`, which scores
  the optional mozc-derived "track B" engine (see `tools/mozc_data/README.md`
  for what that is and its known quality limitations) side by side with the
  default hand-built dictionary on the same sentences. Not a regression gate
  the way TEST1-9 are against track A — track B isn't expected to match it.
- `corpus_test11.js` — authored fresh after a fix round covering かぜ/風邪
  collocation, the ん-starting function-word segment-merge bug, and the new
  `findBoundaryDetourAlternate` N-best segmentation path. Deliberately
  ordinary natural-Japanese sentences across mixed registers, not built
  around any of that round's specific fixes, so the first-measurement number
  (59.5%) was honest; investigating its misses directly (not deferred to a
  later round, since none of them had been looked at before writing fixes)
  surfaced several further real bugs -- most from `DICTIONARY` entries in
  `KanaKanjiConverter.ets` that silently shadow a much better `dict.json`
  entry for the same reading (checked first in `lookupCore`'s priority
  chain), which a whole-corpus scan can't easily surface since it only
  needs one bad key to slip through: `'あけ': ['朱']` alone was hiding
  `dict.json`'s `開け/明け/空け` (あけたら → 朱たら), and
  `'しおからい': ['しょっぱい', ...]` was substituting a *different* word
  entirely instead of 塩辛い. Also fixed: あわず missing 会わず as a
  candidate, いえ/びるをたてる not preferring 建てる over 立てる, さくげん
  ranking kana ahead of 削減, and かわいて (乾いて) losing a lattice contest
  to a cheaper かわ+いていない split despite already being a correct direct
  dictionary hit on its own. Final score after those fixes: 75.7%.

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

## Regression tooling

Corpus scoring (`run.js`/`run_test*.js`/`run_all.js`) tells you the aggregate
number moved the right way. It doesn't tell you *why*, or catch a regression
outside the ~600 labeled sentences currently in this directory. Three tools
fill that gap, all comparing committed `HEAD` against the current working
tree so they also catch uncommitted changes:

- **`sweep.js`** — samples 4000 keys from `Object.keys(dict.json) ∪
  Object.keys(global_dict.json)` (seeded PRNG, reproducible), builds the
  converter twice (HEAD vs. working tree), and diffs `lookup(key)[0]`,
  flagging any sample that lost kanji (`kanjiLoss`) it had before. Cheap,
  broad, dictionary-ordering/candidate-ranking regressions.
  **Blind spot:** every sampled key already has a direct dictionary entry,
  so this never exercises `lookupCore()`'s "not in any dict" branch and
  therefore never calls `segmentJoinFallback()`/`joinSegs()`. A change to
  that code path can look completely clean under `sweep.js` alone and still
  be a regression.
- **`sweep_join.js`** — same methodology, but samples *concatenated pairs*
  of existing dict keys (which usually aren't themselves dict keys), forcing
  `lookupCore()` down the `segmentJoinFallback()`/`joinSegs()` path that
  `sweep.js` can't reach. Use this whenever a change touches segmentation
  joining, not just dictionary data.
- **`regress.js`** — runs every corpus in this directory (TRAIN/TEST1-11/
  VOCAB1-3) through both the HEAD and working-tree converter and classifies
  every row whose answer changed as `FIXED` (was wrong, now matches gold/
  accept), `REGRESSED` (matched before, wrong now), or
  `CHANGED_STILL_WRONG` (wrong both times, different guess). `REGRESSED`
  rows where the *old* answer had kanji and the *new* one is a plain-kana
  fallback are worth eyeballing individually: an honest "I don't know" kana
  fallback is very often a net improvement over a confidently wrong kanji
  guess, even though it counts as a strict-match loss in the corpus score.

## Workflow

1. `node tools/ime-eval/run_all.js` to get the current baseline across every
   corpus in one build (equivalent to running `run.js` + every `run_test*.js`
   + every `run_vocab*.js` separately, but only transpiles once).
2. Change the converter (ranking, segmentation cost, dictionary pruning, …).
3. Re-run `run_all.js`. A change ships only if accuracy rises **and** no
   previously-correct labeled sentence regresses (`regress.js`'s
   `REGRESSED` list should be empty or each entry manually judged
   net-acceptable, per "Regression tooling" above).
4. Also run `sweep.js` for a broader dictionary-level sanity check. If the
   change touches `joinSegs()`, `segmentJoinFallback()`, or `lookupCore()`'s
   no-dict-entry branch specifically, `sweep.js` alone is **not** sufficient
   — also run `sweep_join.js`.

Some "misses" are valid homophones of the gold (e.g. `撮った` vs `取った`,
`聞く` vs `聴く`), so real-world quality is a little higher than the raw score.
Extend the corpus whenever a new class of mistake is reported.
