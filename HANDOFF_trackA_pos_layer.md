# 引き継ぎ: track A 根本改善「品詞・活用レイヤー導入」(Phase 1)

このファイルは、前セッションがインフラ不具合(ExitPlanMode / AskUserQuestion の
tool-permission ストリームが繰り返し `AbortError` で落ちる)で継続不能になったため、
新セッションが**完全に同じ状態から続行できる**よう書かれた引き継ぎメモ。
実装着手の直前まで進んでおり、設計は確定済み。**このファイルは作業完了後に削除してよい**。

---

## 0. 現在の状態(コミット済み)

- ブランチ: `claude/landscape-layout-cutoff-i84e7p`
- 最新コミット: `f126b79`(track B の Viterbi per-class 修正)。作業ツリーはクリーン。
- 開発規約(全セッション共通、継続):
  - 作業は必ず `claude/landscape-layout-cutoff-i84e7p` ブランチ。
  - GitHub は `shuntilettuce/japanese-ime-for-harmonyos-next` のみ。
  - コミットに生のモデルID文字列を書かない(Co-Authored-By は `Claude Sonnet 5` を使う)。
    Claude-Session 行と Co-Authored-By 行を各コミット末尾に付ける(既存コミット参照)。
  - push は `git push -u origin claude/landscape-layout-cutoff-i84e7p`。
  - PR #3 が既にこのブランチで open(base: `claude/harmonyos-japanese-ime-app-3OaxO`)。
    新規PRは作らず、このブランチに push すれば PR #3 が更新される。

## 1. これまでの経緯(track B は完成)

track B(統計データエンジン, `engine='mozc'`)は本ブランチで完成済み:
mozc生2,672クラス接続行列を直接使用 + JMdict/SudachiDict語彙拡充 + per-class Viterbi。
最終 compare_engines.js: corpus_test10 14/20(70%)、corpus_test9 26/49(53.1%)。
**track B には今後触れない。** また GitHub Sponsors / OFUSE 導線、設定画面のフルパネル化も
完了済み。

## 2. 今回のタスク: track A(独自辞書エンジン, `engine='custom'`, デフォルト)の根本改善

ユーザー指示(原文):
- 「track Aの改善に戻ろう 根本的に何か変わる策を考えてくれ」
- 制約確認 → **「完全オリジナル厳守」**: track A には mozc/JMdict/Sudachi/ipadic 等の
  **外部統計データを一切流用しない**。手書き文法ルール・track A 自身のコード由来の
  データのみ。二本立て(独立した第二意見)の意義を保つため。
- 方向性確認 → **「品詞・活用レイヤー導入」** を選択。
- 承認済み: 「承認ということで よろしく」→ Phase 1 実装OK。

## 3. 根本原因(前セッションで実データ計測済み)

### 誤り分析の結果(5コーパス TRAIN/TEST2/6/7/8、句読点不可能7件を除く62件)
- **ランキング誤り(分割は正しいが漢字選択ミス): 38件(61%)**
- **本当の分割/語彙誤り: 24件(39%)**

### 構造的欠陥(Exploreエージェント2本で確定)
`entry/src/main/ets/ime/KanaKanjiConverter.ets`:
1. **`getWordInfo()`(custom版, 現在 `:27307–27386`付近)は辞書の内容語を全て
   `VC_NOUN`(=0)固定で返す**。left==right クラス。非名詞クラスは
   `FW_CLASS_MAP`(読みキー262件)と `FUNCTION_WORDS`(フラット class 73)からしか出ない。
2. その結果 `buildConnectionMatrix()`(100×100, `:27442–27677`付近)の
   **動詞活用形・形容詞・副詞のクラス行がまるごと到達不能(デッドコード)**。
   実装済みだが一度も発火していない。
3. track A は語ごとの品詞/頻度メタデータを一切持たない
   (dict.json/global_dict.json/inline DICTIONARY は全て `読み→[表記]` フラット)。
   文法知識は COMMON_READINGS(~1,500) 等の手書き表に個別に埋め込まれてきた。

### 診断済みの具体的失敗例(活用レイヤーで直る類)
- 分割誤り: `ごにんできた`→五人**できた**(正:で+来た)、`ふってい/て`→払底、
  `ふるまえ`→古前、`きいてい/て`、`はやくなった`境界
- 動詞/形容詞が稀な名詞・固有名詞に負ける: `おわり`→**尾張**、`ふる`→**古**、`ふり`→**振り**
- ※ 意味依存の同音異義(熱い/暑い、速い/早い、計る/測る)は Phase 1 では直らない
  → Phase 2(同音異義ランキング)送り。

## 4. 実装可能性の裏付け(重要)

`tools/build_inline_dict.py`(1097行)は inline `const DICTIONARY:` リテラルを .ets に
直接生成している(`:1034` の `load_existing`/`:1040` の `patch`/`:1057` の `main`)。
活用エンジン群:
- `conj_ichidan`(`:19`)、`conj_godan_u/ku/gu/su/tsu/nu/bu/mu/ru`(`:65`以降)
- ※ **する/くる/形容詞のエンジンは無い**(する/なる/くる/ある/いる は FW_CLASS_MAP で
  既に 28/14/32/14/22 に割当済み)。→ Phase 1 は五段(base=14)・一段(base=22)のみ対象。
- 各エンジンは `add('った','った')` のように、生成する形の**活用形を構造的に把握**して
  生成している。つまり track A 自身が外部データゼロで「読み→活用クラス」を生成できる。
  欠けていたのはこの入力だけで、消費側(接続行列)は搭載済み。
- `main()`(`:1057`)は `VERBS` テーブル(`:326`〜)を回して `fn(r_stem,k_stem)` を呼び、
  `patch()` で **未登録の読みだけ** DICTIONARY に追加する(既存はスキップ)。
  → VERB_CLASS は「新規追加分」ではなく **全生成形** をカバーする必要がある。

## 5. 接続行列の動詞クラス構成(`:27456–27476` で確認済み)
```
NOUNS 0-13 / VERBS 14-33 / ADJ 34-41 / ADV 42-47 / 助詞 48-72 / AUX 73-86 / CONJ 87-89
V_BASE=[14,22,28,32]  V_RENYOU=[15,16,23,29,33]  V_TE=[17,24,30,33]
V_TA=[18,25]  V_NAI=[19,26,31]  V_COND=[20,27]  V_IMP=21
ADJ_ALL=[34..41]  (34=base 35=く 36=て 37=た 38=ないく 39=形状stem 40=な 41=に)
```
グループ別: 五段(base14,連用15/16,て17,た18,未然19,仮定20,命令21)、
一段(base22,連用23,て24,た25,未然26,仮定27)、する(28-31)、くる(32-33)。
`fv(from,to,v)` は `m[from][to]=v`。行列は `m[prevRightClass][curLeftClass]`。

## 6. 確定した設計(Phase 1)

### 方針: whole-word 動詞エントリに (leftClass, rightClass) を付与
- **leftClass = グループの base 動詞クラス**(五段=14, 一段=22)。
  → 前の助詞/副詞/名詞が「動詞に接続」する扱いになる
  (`fv(CASE_P, VERBS_ALL, -800)` 等が発火。VERBS_ALL=14..33 に含まれるので OK)。
- **rightClass = 生成形の語尾から判定した終止形クラス**(次への接続を正しくする)。
- track A のスカラー Viterbi(`:27813–27838`付近の custom 分岐)は**変更不要**。
  1読み1クラスを保てば left≠right でもスカラーDPは正しく動く
  (track B で必要だった per-class 化は track A では不要)。

### rightClass 判定(生成形の suffix = reading[len(r_stem):] で分類)
build_inline_dict.py の main ループ内で、各生成読みの suffix を取り、以下で分類
(左は group base=14 or 22。以下は右クラス。上から順に最初にマッチしたもの):
```
endswith 'なかった'          -> 37 (adj past 的)
endswith 'たかった'          -> 37
endswith 'なくて'            -> 36
endswith 'たくて'            -> 36
endswith 'たくない'          -> 38
endswith 'ない'             -> 34 (ない は i-adj 的終止)
endswith 'たい'             -> 34
endswith 'た' or 'だ'        -> 18 (過去: った/いた/いだ/んだ/た/ました)
endswith 'て' or 'で'        -> 17 (て形: って/いて/て)
endswith 'ば'               -> 20 (仮定)
endswith 'ます' or 'ません'   -> 14 (丁寧終止)
else (base: う/く/ぐ/す/つ/ぬ/ぶ/む/る 終止, ている/られる/させる 等の る終止含む)
                            -> group base (14 or 22)
```
※ この分類は「まず動かして計測、回帰が出たら反復調整」。値は暫定。

### VERB_CLASS の持たせ方: **inline const を .ets に生成**(rawfile JSON にしない)
理由: 実行時ローダ(KeyboardPage 等)と評価ハーネス(run_all/regress/sweep/sweep_join/
compare_engines の各 build())の**全ロード箇所を触らずに済む**(コンパイル時取り込み)。
DICTIONARY と同じ生成器が吐くので同期ズレも起きない。
- build_inline_dict.py に「全 VERBS を回して verb_class = {reading:[left,right]} を作り、
  inline `const VERB_CLASS: Record<string, number[]> = {...};` を .ets 内に生成/置換する」
  処理を追加。DICTIONARY 生成の直後、`const VERB_CLASS` ブロックがあれば丸ごと置換、
  無ければ DICTIONARY 定義の直後に挿入(冪等に)。
- 衝突: 同じ読みが複数 stem から異なるクラスで生成される場合は最初のを優先(measure)。

### getWordInfo の改修(custom版のみ)
`getWordInfo()` の **既存の全分岐(FW_CLASS_MAP / 46件ハードコード / FUNCTION_WORDS)の後、
名詞デフォルト(現 `:27366–27385`)の直前**に挿入:
```ts
const vc = KanaKanjiConverter.VERB_CLASS[sub];
if (vc !== undefined) {
  const lenBonus = Math.min((sub.length - 1) * 500, KanaKanjiConverter.VN_DEFAULT - 500);
  const commonBonus = KanaKanjiConverter.COMMON_READINGS.has(sub) ? 3000 : 0;
  return [KanaKanjiConverter.VN_DEFAULT - lenBonus - commonBonus, vc[0], vc[1]];
}
```
- **完全に追加的・ゲート式**: `sub` が VERB_CLASS に無ければ既存コードと byte-identical。
  既存の手書き表が優先されるので、**今まさに名詞デフォルトに落ちている読みだけ**が変化。
  → 影響範囲が動詞活用形に限定され、回帰リスクが bounded。
- getWordInfo は mozc なら冒頭(`:27308`)で早期return するので、この追加は custom 専用。
- `VERB_CLASS` の static フィールド宣言(`private static VERB_CLASS: Record<string,number[]> = {}`)
  は不要 — inline const として .ets トップレベルに置くなら `KanaKanjiConverter.VERB_CLASS`
  ではなく直接 `VERB_CLASS[sub]` で参照(DICTIONARY と同じ扱い。DICTIONARY はトップレベル
  const で `DICTIONARY[sub]` 参照している、`:27137` 等)。→ 上記コードは `VERB_CLASS[sub]`
  に直すこと。

## 7. 検証(重要な注意)

これは **track A の挙動を意図的に変える初めての変更**。従来の「track A は byte-identical」
基準は**適用外**。成功基準は「純増」:
1. `node tools/ime-eval/run_all.js`: TRAIN/TEST/VOCAB の strict 一致率が純増(最低でも不変)。
   現行ベースライン(f126b79 時点):
   ```
   TRAIN 198/228(86.8%) TEST1 48/57 TEST2 37/54 TEST3 38/48 TEST4 42/46 TEST5 34/41
   TEST6 28/50 TEST7 23/44 TEST8 25/40 TEST9 35/49 TEST10 16/20
   VOCAB1 226/247 VOCAB2 130/139 VOCAB3 104/104
   ```
2. `node tools/ime-eval/regress.js`: **FIXED >> REGRESSED** であること(今回は 0/0 でなくてよい)。
   個々の REGRESSED を精査し、必要なら接続行列値/クラス割当を反復調整。
3. `node tools/ime-eval/sweep.js` / `sweep_join.js`: VERB_CLASS に**無い**読み(非活用の名詞等)で
   kanji-loss=0(影響範囲が本当に活用形のみに限定されている確認)。
4. 下記 miss 分析スクリプトを再走し、診断済み境界誤り(ごにんできた/ふってい/ふるまえ 等)が
   実際に flip したか個別確認。
5. track B は無関係だが engine dispatch を壊していないことを
   `node tools/mozc_data/compare_engines.js corpus_test10.js` で一応確認
   (期待値 mozc 14/20)。

### ハーネスの使い方メモ
- どのハーネスも .ets を毎回 tsc で `// @ts-nocheck` 付き transpile して実行する
  (ArkTS はフルコンパイル不可、目視レビュー中心)。
- inline const VERB_CLASS を .ets に足すだけなので、ハーネス側の変更は不要。

## 8. miss 分析スクリプト(再現用、前セッションで使用)

新セッションで scratchpad に置いて実行するとカテゴリ別に誤りを吐く。ロジック:
各誤りについて `conv.segment(reading)` の各セグメントの候補(`conv.lookup(seg)` +
生かな + カタカナ)で gold を tiling できれば RANKING誤り、できなければ SEG/VOCAB誤り。
gold に句読点 [、。「」（）] を含むものは unwinnable として除外。
```js
// build() は run_all.js の build() をそのまま流用(SRC/DICT/GDICT を読み tsc transpile)。
// convert() も run_all.js のものをコピー。
// tile(segs, gold): BFS で (segIndex, goldPos) 到達可能性。各 seg の候補集合は
//   new Set([...conv.lookup(seg), seg, KanaKanjiConverter.toKatakana(seg)])。
// 集計: PUNC=/[、。「」『』（）,.]/ を含む gold は unwinnable。
//   それ以外で tile 可能なら RANKING、不可なら SEG/VOCAB。
// 対象コーパス: corpus.js+corpus2.js+corpus3.js(TRAIN), corpus_test2/6/7/8.js。
```
(前セッションの完全版は scratchpad/miss_analysis3.js にあったが session-ephemeral。
上記ロジックで再作成可能。)

## 9. Phase 2(今回はやらない、記録のみ)
- 選ばれた活用クラスを lookup() まで伝搬(track B の mozcLastHints と同じ機構)し、
  動詞文脈(後続が動詞接続の助動詞)では動詞表記を名詞/固有名詞表記より優先
  (尾張→終わり、古→降る)。裸連用形(ふり/おわり/ふる 等、名詞と衝突する読み)の
  曖昧性もここで扱う。Phase 1 では裸連用形にクラス付与しない(明確な活用形に限定)。
- 形容詞エンジン(く/かった/くて → ADJ 34-41)の追加も Phase 2 以降で検討。

## 10. まとめ: 新セッションの着手手順
1. このファイルを読む。`git log --oneline -3` で f126b79 が最新か確認。
2. `tools/build_inline_dict.py` に VERB_CLASS 生成を追加(§6)。実行して .ets に
   inline const が入ること、サイズ・数件のエントリを確認。
3. `getWordInfo()` に VERB_CLASS 参照を追加(§6、`VERB_CLASS[sub]` で参照)。
4. `run_all.js` / `regress.js` / `sweep.js` / `sweep_join.js` / miss分析 で計測(§7)。
5. 純増になるまで接続行列値/クラス割当を反復調整。純増を確認したらコミット&push
   (§0 の規約)。コミットメッセージに根本原因・設計・before/after 数値を詳述。
6. 完了したらこの HANDOFF ファイルを削除するコミットを入れる。
```
