import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import type { Want } from '@kit.AbilityKit';
import display from '@ohos.display';
import util from '@ohos.util';
import dataPreferences from '@ohos.data.preferences';
import pasteboard from '@ohos.pasteboard';
import vibrator from '@ohos.vibrator';
import bundleManager from '@ohos.bundle.bundleManager';

import { JapaneseConverter, toKatakana } from './JapaneseConverter';
import { KanaKanjiConverter, MozcMatrixData, MozcPackedTables, VocabPackInfo } from './KanaKanjiConverter';
import { UserDictStore } from './UserDictStore';
import { UserPosStore } from './UserPosStore';
import type { UserPosEntry, PosKind, VerbGroup } from './ConjugationEngine';
import { buildUserExpansion } from './ConjugationEngine';
import { SettingsStore, KeyboardSettings, isDarkFromConfiguration, isDarkFromResourceManager, resolveIsDark } from './SettingsStore';
import { findPredictiveCompletion } from './PredictivePhrases';
import { NextWordPredictor } from './NextWordPredictor';
import { PredictiveConversion } from './PredictiveConversion';
import { UnknownWordLearner } from './UnknownWordLearner';
import { SuppressedCandidates, SUPPRESSED_STORE, SUPPRESSED_KEY } from './SuppressedCandidates';
import { DateTimePredictor } from './DateTimePredictor';
import { NumberFormatter } from './NumberFormatter';
import { EmojiSuggest } from './EmojiSuggest';
import { AppMaintenance } from './AppMaintenance';
import { InputLog } from './InputLog'; // [DEBUG-LOG]

interface InputMethodSubtype {
  id: string;
  label?: string;
  locale?: string;
  mode?: string;
}

// Segmentation of the current composing text plus each non-final segment's
// auto-converted surface, captured while updateCandidates runs (where the
// segmentation and prefix conversions are already computed). A later
// whole-sentence commit uses this to learn each 文節 individually: it peels
// the known prefix off the committed text to recover the final segment's
// accepted surface, so homophone corrections generalize word-by-word --
// see learnCommit / KanaKanjiConverter.recordSegmentedChoice.
interface ComposeAlignment {
  segs: string[];            // per-segment readings
  prefixSurfaces: string[];  // auto-converted surface of segs[0..n-2]
  prefixText: string;        // prefixSurfaces joined
}

// ホスト側(確定済み)テキストへの1回の操作。hostUndoStack の要素。
// 詳しい設計意図は hostUndoStack のフィールドコメント参照。
interface InsertTextOptions {
  raw: boolean;
}

interface HostEditOp {
  kind: 'insert' | 'delete';
  text: string;
  at: number;   // IME自己完結の相対座標(ホストの絶対indexではない)
}

// 開き括弧 -> 閉じ括弧。pendingBracketClose の元ネタ。
//
// 以前は「（）」のように開き・閉じを1つの候補として丸ごと確定し、確定後に
// カーソルだけ内側へ戻す実装だったが、moveCursor/selectByRange のどちらも
// 実機で信用できないことが分かり撤去した (コミット 7328e504 参照)。
//
// 今回は発想を変え、カーソルを一切動かさない: 開きだけを確定し、閉じは
// 「次に確定される内容の直後」まで保留する。ユーザーは括弧の中を普通に
// 打ち進めるだけで、次の確定のたびに保留中の閉じがその直後へ続けて出る
// ので、結果的に (内容) の形になる。カーソル移動プリミティブを一切
// 使わないので、上記の実機不具合と無縁になる。
const BRACKET_PAIRS: Record<string, string> = {
  '（': '）', '「': '」', '『': '』', '【': '】',
  '〖': '〗', '〔': '〕', '〈': '〉', '《': '》',
  '(': ')', '[': ']', '{': '}',
  '［': '］', '｛': '｝', '〝': '〟',
};

// Cap for tablet/foldable content width (see computeKeyWidths / applyKeyboardWidthsForVp).
const MAX_KB_VP = 620;

// Pure width math shared by the display-metrics-based initial guess (computeKeyWidths)
// and the live layout correction (KeyboardPage.onAreaChange). display.getDefaultDisplaySync()
// can under- or over-report the actually drawable panel width on some devices (e.g. a
// landscape cutout/nav-bar inset it doesn't account for), which made keys sized from the
// raw display metrics alone overflow past the real edge on one side while leaving a dead
// band on the other. Recomputing from the *measured* on-screen width — whatever the true
// source of the discrepancy — self-corrects regardless of cause.
export function applyKeyboardWidthsForVp(rawScreenVp: number, isTabletClass: boolean): void {
  const screenVp = isTabletClass ? Math.min(rawScreenVp, MAX_KB_VP) : rawScreenVp;
  AppStorage.setOrCreate('keyboardContentVp', screenVp);
  // 10-key rows (KeyboardView's number row / qwerty row / romaji asdfghjklー
  // row): 4vp total H-padding + 9 gaps × 5vp (KeyboardView's Row({space:5}),
  // not the 2vp this used to assume before the design-token pass bumped row
  // spacing -- that mismatch was the actual bug: keys came out ~2.7vp too
  // wide each, ~27vp of overflow past the right edge on any 10-key row) =
  // 49vp overhead. The middle letter row (asdfghjkl + ー) and bottom row
  // (shift + zxcvbnm + backspace) also reuse this width; they aren't a
  // fixed-width fit like this row, just centered, so a different key count
  // is harmless.
  const kwVp = Math.max(Math.floor((screenVp - 49) / 10), 24);
  const skwVp = Math.round(kwVp * 1.2);
  // Space bar = remaining after mode + 、 + 文節 + 。 + enter + 5 gaps × 5vp
  // (文節 sits right after space, at the same special-key width as
  // mode/enter — the row would overflow if it were sized on top of them
  // instead of space giving up the room). Same space:5 vs assumed-2vp
  // mismatch as kwVp above.
  const spaceVp = Math.max(Math.floor(screenVp - 4 - 3 * skwVp - 2 * kwVp - 25), 60);
  // Flick keys: 5 columns (左特殊・中央3列・右特殊) + 4 gaps × 4vp
  // (FlickKeyboardView's Row({space:4})) + 0vp H-padding (its Column has no
  // left/right padding) = 16vp overhead -- same total as the old "4 gaps ×
  // 3vp + 4vp H-padding" comment assumed, by coincidence, so this one was
  // never actually broken.
  //
  // flickSideColumnRatio (設定 → レイアウト調整) は「左右の特殊キー1列の
  // 幅 / 中央の かなキー1列の幅」。既定 1.0 で今までどおり5列均等になる。
  // available = 2*side + 3*mid, side = ratio*mid という連立から解く。
  const available = screenVp - 16;
  const sideRatio = Math.min(2.0, Math.max(0.4, AppStorage.get<number>('flickSideColumnRatio') ?? 1.0));
  const flickKwVp = Math.max(Math.floor(available / (3 + 2 * sideRatio)), 40);
  const flickSideKwVp = Math.max(Math.floor(flickKwVp * sideRatio), 32);
  AppStorage.setOrCreate('keyWidthVp', kwVp);
  AppStorage.setOrCreate('specialKeyWidthVp', skwVp);
  AppStorage.setOrCreate('spaceKeyWidthVp', spaceVp);
  AppStorage.setOrCreate('flickKeyWidthVp', flickKwVp);
  AppStorage.setOrCreate('flickSideKeyWidthVp', flickSideKwVp);
  // Symbol panel: 8 columns + 7 gaps × 4vp (SymbolView's Row({space:4})) +
  // 8vp H-padding (left:4 + right:4) = 36vp overhead -- was assuming 2vp
  // gaps + 6vp padding (20vp) here too, same class of bug as kwVp above.
  const symKwVp = Math.max(Math.floor((screenVp - 36) / 8), 36);
  AppStorage.setOrCreate('symKeyWidthVp', symKwVp);
}

export const enum InputState {
  IDLE = 'IDLE',
  COMPOSING = 'COMPOSING',
  SELECTING = 'SELECTING',
  BUNSETSU = 'BUNSETSU',
}

export const enum InputMode {
  HIRAGANA = 'HIRAGANA',
  KATAKANA = 'KATAKANA',
  ALPHANUMERIC = 'ALPHANUMERIC',
}

const IMEAbility = inputMethodEngine.getInputMethodAbility();

// Cycles through all applicable variants of a kana character on repeated taps.
// Order: small (if applicable) → dakuten → handakuten (if applicable) → original
const VARIANT_CYCLE: Record<string, string> = {
  // ka行: dakuten toggle
  'か':'が','が':'か','き':'ぎ','ぎ':'き','く':'ぐ','ぐ':'く','け':'げ','げ':'け','こ':'ご','ご':'こ',
  // sa行: dakuten toggle
  'さ':'ざ','ざ':'さ','し':'じ','じ':'し','す':'ず','ず':'す','せ':'ぜ','ぜ':'せ','そ':'ぞ','ぞ':'そ',
  // ta行: ち/て/と dakuten only; つ→っ→づ→つ (small first)
  'た':'だ','だ':'た','ち':'ぢ','ぢ':'ち','て':'で','で':'て','と':'ど','ど':'と',
  'つ':'っ','っ':'づ','づ':'つ',
  // ha行: dakuten → handakuten → original
  'は':'ば','ば':'ぱ','ぱ':'は','ひ':'び','び':'ぴ','ぴ':'ひ',
  'ふ':'ぶ','ぶ':'ぷ','ぷ':'ふ','へ':'べ','べ':'ぺ','ぺ':'へ','ほ':'ぼ','ぼ':'ぽ','ぽ':'ほ',
  // う: small → dakuten → original
  'う':'ぅ','ぅ':'ゔ','ゔ':'う',
  // small vowels (no dakuten)
  'あ':'ぁ','ぁ':'あ','い':'ぃ','ぃ':'い','え':'ぇ','ぇ':'え','お':'ぉ','ぉ':'お',
  'や':'ゃ','ゃ':'や','ゆ':'ゅ','ゅ':'ゆ','よ':'ょ','ょ':'よ','わ':'ゎ','ゎ':'わ',
  // katakana — same pattern
  'カ':'ガ','ガ':'カ','キ':'ギ','ギ':'キ','ク':'グ','グ':'ク','ケ':'ゲ','ゲ':'ケ','コ':'ゴ','ゴ':'コ',
  'サ':'ザ','ザ':'サ','シ':'ジ','ジ':'シ','ス':'ズ','ズ':'ス','セ':'ゼ','ゼ':'セ','ソ':'ゾ','ゾ':'ソ',
  'タ':'ダ','ダ':'タ','チ':'ヂ','ヂ':'チ','テ':'デ','デ':'テ','ト':'ド','ド':'ト',
  'ツ':'ッ','ッ':'ヅ','ヅ':'ツ',
  'ハ':'バ','バ':'パ','パ':'ハ','ヒ':'ビ','ビ':'ピ','ピ':'ヒ',
  'フ':'ブ','ブ':'プ','プ':'フ','ヘ':'ベ','ベ':'ペ','ペ':'ヘ','ホ':'ボ','ボ':'ポ','ポ':'ホ',
  'ウ':'ゥ','ゥ':'ヴ','ヴ':'ウ',
  'ア':'ァ','ァ':'ア','イ':'ィ','ィ':'イ','エ':'ェ','ェ':'エ','オ':'ォ','ォ':'オ',
  'ヤ':'ャ','ャ':'ヤ','ユ':'ュ','ュ':'ユ','ヨ':'ョ','ョ':'ヨ','ワ':'ヮ','ヮ':'ワ',
};

const DAKUTEN: Record<string, string> = {
  'か':'が','き':'ぎ','く':'ぐ','け':'げ','こ':'ご',
  'さ':'ざ','し':'じ','す':'ず','せ':'ぜ','そ':'ぞ',
  'た':'だ','ち':'ぢ','つ':'づ','て':'で','と':'ど',
  'は':'ば','ひ':'び','ふ':'ぶ','へ':'べ','ほ':'ぼ','う':'ゔ',
  'が':'か','ぎ':'き','ぐ':'く','げ':'け','ご':'こ',
  'ざ':'さ','じ':'し','ず':'す','ぜ':'せ','ぞ':'そ',
  'だ':'た','ぢ':'ち','づ':'つ','で':'て','ど':'と',
  'ば':'は','び':'ひ','ぶ':'ふ','べ':'へ','ぼ':'ほ','ゔ':'う',
  'カ':'ガ','キ':'ギ','ク':'グ','ケ':'ゲ','コ':'ゴ',
  'サ':'ザ','シ':'ジ','ス':'ズ','セ':'ゼ','ソ':'ゾ',
  'タ':'ダ','チ':'ヂ','ツ':'ヅ','テ':'デ','ト':'ド',
  'ハ':'バ','ヒ':'ビ','フ':'ブ','ヘ':'ベ','ホ':'ボ','ウ':'ヴ',
  'ガ':'カ','ギ':'キ','グ':'ク','ゲ':'ケ','ゴ':'コ',
  'ザ':'サ','ジ':'シ','ズ':'ス','ゼ':'セ','ゾ':'ソ',
  'ダ':'タ','ヂ':'チ','ヅ':'ツ','デ':'テ','ド':'ト',
  'バ':'ハ','ビ':'ヒ','ブ':'フ','ベ':'ヘ','ボ':'ホ','ヴ':'ウ',
};
const HANDAKUTEN: Record<string, string> = {
  'は':'ぱ','ひ':'ぴ','ふ':'ぷ','へ':'ぺ','ほ':'ぽ',
  'ば':'ぱ','び':'ぴ','ぶ':'ぷ','べ':'ぺ','ぼ':'ぽ',
  'ぱ':'は','ぴ':'ひ','ぷ':'ふ','ぺ':'へ','ぽ':'ほ',
  'ハ':'パ','ヒ':'ピ','フ':'プ','ヘ':'ペ','ホ':'ポ',
  'バ':'パ','ビ':'ピ','ブ':'プ','ベ':'ペ','ボ':'ポ',
  'パ':'ハ','ピ':'ヒ','プ':'フ','ペ':'ヘ','ポ':'ホ',
};
const SMALL_KANA: Record<string, string> = {
  'あ':'ぁ','い':'ぃ','う':'ぅ','え':'ぇ','お':'ぉ',
  'つ':'っ','や':'ゃ','ゆ':'ゅ','よ':'ょ','わ':'ゎ',
  'ぁ':'あ','ぃ':'い','ぅ':'う','ぇ':'え','ぉ':'お',
  'っ':'つ','ゃ':'や','ゅ':'ゆ','ょ':'よ','ゎ':'わ',
  'ア':'ァ','イ':'ィ','ウ':'ゥ','エ':'ェ','オ':'ォ',
  'ツ':'ッ','ヤ':'ャ','ユ':'ュ','ヨ':'ョ','ワ':'ヮ',
  'ァ':'ア','ィ':'イ','ゥ':'ウ','ェ':'エ','ォ':'オ',
  'ッ':'ツ','ャ':'ヤ','ュ':'ユ','ョ':'ヨ','ヮ':'ワ',
};

// ---------- InputHandler ----------

export class InputHandler {
  private static _instance: InputHandler | undefined = undefined;
  private kbController: inputMethodEngine.KeyboardController | undefined;
  private inputClient: inputMethodEngine.InputClient | undefined;
  private converter: JapaneseConverter = new JapaneseConverter();
  private kanjiConverter: KanaKanjiConverter = new KanaKanjiConverter();
  // bunsetsu state
  private bSegs: string[] = [];
  private bChosen: string[] = [];
  private bCur: number = 0;
  // Segmentation + prefix surfaces of the most recent updateCandidates()
  // composing text, or undefined when it was a single segment / had a symbol
  // prefix. Lets a whole-sentence commit learn each 文節 individually (see
  // learnCommit / KanaKanjiConverter.recordSegmentedChoice).
  private lastAlignment: ComposeAlignment | undefined = undefined;
  private insertedBuffer: string[] = [];
  // 変換前のかな組み立て中(COMPOSING)にbackspaceで消した文字のLIFO。この
  // バッファは常に末尾でしか編集できない(カーソルが途中へ移動する経路が
  // 無い)ので、位置のズレが起きようがない。確定するとその回の組み立ては
  // 終わりなので resetComposition で空にする(handleDirectKana 参照)。
  private composingUndoStack: string[] = [];
  private conversionEnd: number = 0;
  // composingText の「今回の入力で一番長く伸びた時点」の値。updateCandidates
  // のたびに更新し (打っている間は常に候補が見えているので、これが伸びる=
  // 「変換候補を見た」の代わり)、消して空に戻ったときに
  // UnknownWordLearner.noteAbandonedReading へ渡す。確定すれば
  // resetComposition で捨てる (諦めたのではなく使われたため)。
  private composingWatermark: string = '';
  // この入力欄が setPreviewTextSync に対応しているか (onInputStart で判定)。
  private previewSupported: boolean = false;
  // 実際に入力欄へプレビューを出している最中か。出していないのに
  // finishTextPreviewSync を呼ぶと無駄な IPC になるので状態を持つ。
  private previewActive: boolean = false;
  // いまプレビューとして出している文字数 (取り消し時の削除長に使う)。
  private previewLen: number = 0;
  // 入力中のかなをどこに出すかの設定 (SettingsStore、独立した2つのトグル)。
  private composingInPanel: boolean = true;
  private composingInField: boolean = true;
  // ホスト側(確定済み、IDLE状態)テキストに対する操作の履歴。挿入・削除
  // どちらも1本のスタックに積み、取消キーは最新のものから本当のctrl+zと
  // 同じ順序で戻す。insertText() を経由するものは全部ここに乗るので、
  // 変換確定・生かな確定・記号/絵文字タップ・予測変換タップ・
  // クリップボード貼り付け...どの経路で入っても等しく取り消せる。
  //
  // at は「このIME自身が動かした分」だけを積算した自己完結の座標で、
  // ホストの絶対カーソル位置とは対応しない。inputClient.getTextIndexAtCursor
  // は実機で誤った値(カーソル後方にテキストがあると文末寄りの値)を返すこと
  // が分かっている(括弧カーソル自動移動機能で実証・撤去済み、コミット
  // 7328e504 参照)ため、ホストの絶対座標には一切頼らない。矢印キー(◄►)
  // による移動は hostCursor に反映して追従できるが、ユーザーが入力欄を
  // 直接タップしてカーソルを動かした場合は検知できずズレる。それでも
  // 「常に今のカーソル位置で実行する」だった以前より、追跡できる範囲では
  // 確実に正しくなる。
  private hostUndoStack: HostEditOp[] = [];
  private hostCursor: number = 0;
  private static readonly MAX_HOST_UNDO = 100;
  // 括弧の自動閉じで「次の確定の直後に出す」ぶんの閉じ括弧。空なら保留無し。
  // 詳しい設計意図は BRACKET_PAIRS のコメント参照。
  private pendingBracketClose: string = '';
  private imeContext: InputMethodExtensionContext | undefined = undefined;
  private learningPrefs: dataPreferences.Preferences | undefined = undefined;
  private learningSaveTimer: number = -1;
  private nextWordPrefs: dataPreferences.Preferences | undefined = undefined;
  private nextWordSaveTimer: number = -1;
  private unknownWordPrefs: dataPreferences.Preferences | undefined = undefined;
  private unknownWordSaveTimer: number = -1;
  private suppressedPrefs: dataPreferences.Preferences | undefined = undefined;
  // 前回の書き込み以降に中身が変わったか。変化が無いのに閉じるたび4本
  // 書きに行かないため (flushPendingSaves のコメント参照)。
  private learningDirty: boolean = false;
  private nextWordDirty: boolean = false;
  private unknownWordDirty: boolean = false;
  // 登録したそのままのユーザー辞書 (活用展開する前)。設定パネルの一覧用。
  private userDictRaw: Record<string, string[]> = {};
  // 辞書の自由入力中に、確定文字の送り先を切り替えるための印。
  // '' = ホストアプリ / 'yomi' | 'word' = パネル内のその欄。
  private captureTarget: string = '';
  private suppressedDirty: boolean = false;
  private suppressedSaveTimer: number = -1;
  // The last (up to) two committed words, at word granularity, used as the
  // 1- and 2-word context for next-word prediction/learning (see
  // NextWordPredictor / pushPredictions). Newest last.
  private recentWords: string[] = [];
  // Parallel to the 'predictions' AppStorage strip: the individual word(s) each
  // displayed chip represents (a phrase chip's own words, or [text] for a
  // plain single-word/emoji chip) -- see pushPredictions/commitPrediction.
  private predictionWordGroups: string[][] = [];
  private symbolPrefs: dataPreferences.Preferences | undefined = undefined;
  private symbolSaveTimer: number = -1;
  // Per-symbol tap counts, used to rank the symbol panel's "recent" tab by
  // actual usage instead of a fixed guess. Static so SymbolView's AppStorage
  // read and InputHandler's own updates always see the same data.
  private static symbolFreq: Record<string, number> = {};

  static getInstance(): InputHandler {
    if (!InputHandler._instance) {
      InputHandler._instance = new InputHandler();
    }
    return InputHandler._instance;
  }

  // 拡張プロセスの永続化の初期化。ここが1つの同期ブロックなので、途中で例外が
  // 出ると以降の getPreferences が全部走らず、learningPrefs 等が undefined の
  // まま残る。そうなると saveLearning/saveSuppressed 等は `if (!prefs) return`
  // で黙って何もしなくなり、キーボード自体は動くのに保存だけが全部死ぬ ──
  // 画面からは「全部空」としか見えない。
  // だから、ここに本質的でない処理を足さないこと。収集用の初期化は最後に
  // setupInputLog() として切り出してある(それ自体も try で囲ってある)。
  setContext(ctx: InputMethodExtensionContext): void {
    if (this.imeContext !== undefined) { return; }
    this.imeContext = ctx;
    dataPreferences.getPreferences(this.imeContext, 'shunti_learning')
      .then((prefs: dataPreferences.Preferences) => {
        this.learningPrefs = prefs;
        return prefs.get('v1', '{}');
      })
      .then((val: dataPreferences.ValueType) => {
        try {
          const data = JSON.parse(String(val)) as Record<string, Record<string, number>>;
          KanaKanjiConverter.setLearned(data);
        } catch (_e) {}
      })
      .catch((e: Error) => { InputLog.recordInit('shunti_learning', e); }); // [DEBUG-LOG]
    dataPreferences.getPreferences(this.imeContext, 'shunti_nextword')
      .then((prefs: dataPreferences.Preferences) => {
        this.nextWordPrefs = prefs;
        return prefs.get('v1', '{}');
      })
      .then((val: dataPreferences.ValueType) => {
        try {
          // Either the v2 {v,uni,bi} store or a legacy flat unigram map; the
          // cast satisfies setLearned's union parameter and setLearned itself
          // decides which shape it is (by checking `.v`) and migrates the old one.
          const data = JSON.parse(String(val)) as Record<string, Record<string, number>>;
          NextWordPredictor.setLearned(data);
        } catch (_e) {}
      })
      .catch((e: Error) => { InputLog.recordInit('shunti_nextword', e); }); // [DEBUG-LOG]
    dataPreferences.getPreferences(this.imeContext, 'shunti_unknownword')
      .then((prefs: dataPreferences.Preferences) => {
        this.unknownWordPrefs = prefs;
        return prefs.get('v1', '{}');
      })
      .then((val: dataPreferences.ValueType) => {
        try {
          const data = JSON.parse(String(val)) as Record<string, Record<string, number>>;
          UnknownWordLearner.setLearned(data);
        } catch (_e) {}
      })
      .catch((e: Error) => { InputLog.recordInit('shunti_unknown', e); }); // [DEBUG-LOG]
    dataPreferences.getPreferences(this.imeContext, SUPPRESSED_STORE)
      .then((prefs: dataPreferences.Preferences) => {
        this.suppressedPrefs = prefs;
        return prefs.get(SUPPRESSED_KEY, '{}');
      })
      .then((val: dataPreferences.ValueType) => {
        try {
          const data = JSON.parse(String(val)) as Record<string, string[]>;
          SuppressedCandidates.setSuppressed(data);
        } catch (_e) {}
      })
      .catch((e: Error) => { InputLog.recordInit('shunti_suppressed', e); }); // [DEBUG-LOG]
    dataPreferences.getPreferences(this.imeContext, 'shunti_symbol_freq')
      .then((prefs: dataPreferences.Preferences) => {
        this.symbolPrefs = prefs;
        return prefs.get('v1', '{}');
      })
      .then((val: dataPreferences.ValueType) => {
        try {
          InputHandler.symbolFreq = JSON.parse(String(val)) as Record<string, number>;
          InputHandler.publishFrequentSymbols();
        } catch (_e) {}
      })
      .catch((e: Error) => { InputLog.recordInit('shunti_symbol_freq', e); }); // [DEBUG-LOG]
    this.reloadUserDict();
    this.reloadSettings();
    // 単漢字ずつ組み立て直した語が、実は辞書のどこかに(埋もれて)もう存在した
    // ときの合図。「志岐」のように読み全体では一発で出てこないくらい埋もれて
    // いる語は、UnknownWordLearner からは isKnown()=true で毎回捨てられる一方、
    // 読み全体をひとつの文字列として打つことが無いので recordChoice も一切
    // 呼ばれず、いつまでも埋もれたままになる穴があった。通常の学習ブーストに
    // 回すことでこの穴を塞ぐ。
    // ★ デバッグ専用ではない (リリースでも効くべき機能) なので、下の
    // setupInputLog とは違い収集用の印を付けないこと。
    // (印の文字列をここに書くと、check_debug_log の
    //  削除対象一覧にこの説明文自体が混ざる)
    UnknownWordLearner.onKnownAssembly = (r: string, s: string) => {
      KanaKanjiConverter.recordChoice(r, s);
      this.saveLearning();
      InputLog.recordKnownAssembly(r, s); // [DEBUG-LOG]
    };
    this.setupInputLog(ctx); // [DEBUG-LOG] 必ず最後。上の初期化を壊さないため
  }

  // [DEBUG-LOG] 収集の初期化。
  //
  // これを setContext の先頭に置き、しかも ctx.getApplicationContext() という
  // 新しい API 依存をそこに足していた。あの位置で例外が出ると以降の
  // getPreferences が1つも走らず、学習も削除候補も黙って保存されなくなる。
  // デバッグ用の機能を、本体の永続化より前に立ててはいけない。
  // 末尾に移し、全体を try で囲い、パス取得にも代替を用意した。
  private setupInputLog(ctx: InputMethodExtensionContext): void { // [DEBUG-LOG]
    try { // [DEBUG-LOG]
      // 書き込み先は「実際に開けたところ」を使う。パス文字列が取れることと
      // 拡張プロセスがそこに書けることは別なので、仮定せず試す。
      //
      // ★ 重要: このログは本体アプリからは読めない (別サンドボックス)。
      //
      // キーボードは :inputMethod という別プロセスで動いており、実機で確認した
      // ところ、拡張のサンドボックスは本体アプリのそれと別実体だった。
      // 根拠: 拡張は shunti_settings の保存に成功している (flush 完了後に出る
      // "saveConversionEngine ok" が出る) のに、本体アプリ側から見える
      // preferences には shunti_settings が存在しない。一方で本体アプリが書く
      // shunti_userdict はそこに存在し、更新時刻も書いた瞬間に動く。
      // モジュール単位・アプリ単位のどちらを使っても結果は同じだった。
      //
      // よってディレクトリの選び方では解決しない。プロセスを跨ぐには
      // dataGroupIds + context.getGroupDir() のような別の仕組みが要る。
      // ここでアプリ単位を先に試しているのは読み手と順序を揃えてあるだけで、
      // 「共有されるから」ではない。 // [DEBUG-LOG]
      let appDir = ''; // [DEBUG-LOG]
      try { appDir = ctx.getApplicationContext().filesDir; } catch (_e) { appDir = ''; } // [DEBUG-LOG]
      const used = InputLog.setWritableDir([appDir, ctx.filesDir]); // [DEBUG-LOG]
      console.info('shuntiIME InputLog dir=' + used + ' (module=' + ctx.filesDir + ' app=' + appDir + ')'); // [DEBUG-LOG]
      InputLog.recordPaths('setContext', // [DEBUG-LOG]
        used.length > 0 ? used : '書き込めるディレクトリ無し', // [DEBUG-LOG]
        ctx.filesDir, ctx.preferencesDir); // [DEBUG-LOG]
      // ApplicationInfo に versionName は無い (ApplicationInfo.d.ts に存在しない
      // フィールドだった -- BundleInfo 側にしかない)。getBundleInfoForSelfSync
      // は追加権限なしで呼べる。 // [DEBUG-LOG]
      let appVersion = ''; // [DEBUG-LOG]
      try { appVersion = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName; } catch (_e) { appVersion = ''; } // [DEBUG-LOG]
      InputLog.recordVersion(appVersion); // [DEBUG-LOG]
      UnknownWordLearner.onLearn = (r: string, s: string, confirmed: boolean) => { InputLog.recordUnknownWord(r, s, confirmed); }; // [DEBUG-LOG]
    } catch (e) { // [DEBUG-LOG]
      console.error('shuntiIME InputLog setup failed', JSON.stringify(e)); // [DEBUG-LOG]
    } // [DEBUG-LOG]
  } // [DEBUG-LOG]

  // Called whenever the user taps a symbol in SymbolView, so its "recent" tab
  // can be ranked by what this user actually reaches for instead of a fixed
  // guess at common punctuation.
  recordSymbolUse(sym: string): void {
    InputHandler.symbolFreq[sym] = (InputHandler.symbolFreq[sym] ?? 0) + 1;
    // Deliberately does NOT republish the "recent" ordering here: doing so on
    // every tap re-sorted the 🕐 tab in real time, so a key slid out from
    // under the user's finger as they used it. The visible order is snapshotted
    // when the symbol panel opens instead (SymbolView.aboutToAppear →
    // refreshFrequentSymbols), so positions stay put during a tapping session
    // and only settle into their new frequency order the next time it opens.
    clearTimeout(this.symbolSaveTimer);
    this.symbolSaveTimer = setTimeout(() => {
      const prefs = this.symbolPrefs;
      if (!prefs) { return; }
      prefs.put('v1', JSON.stringify(InputHandler.symbolFreq))
        .then(() => prefs.flush())
        .catch((_e: Error) => {});
    }, 2000);
  }

  // Re-sort the "recent" symbol tab by current tap frequency. Called on
  // symbol-panel open (not per tap) so the ordering the user sees is stable
  // while they tap within it -- see recordSymbolUse.
  refreshFrequentSymbols(): void {
    InputHandler.publishFrequentSymbols();
  }

  private static publishFrequentSymbols(): void {
    const syms = Object.keys(InputHandler.symbolFreq);
    syms.sort((a: string, b: string) =>
      (InputHandler.symbolFreq[b] ?? 0) - (InputHandler.symbolFreq[a] ?? 0));
    AppStorage.setOrCreate('frequentSymbols', syms.slice(0, 24));
  }

  // Reload the user dictionary from disk (picks up words added in the main
  // app), plus its 品詞 metadata (DictEditBar's POS chips) --
  // expanded into conjugated forms + connection-matrix class overrides via
  // ConjugationEngine before handing off to KanaKanjiConverter, so a verb/
  // adjective/person/place entry gets real segmentation behaviour instead of
  // the flat noun default (see UserPosStore/ConjugationEngine.ets).
  private reloadUserDict(): void {
    if (!this.imeContext) { return; }
    const ctx = this.imeContext;
    Promise.all([
      UserDictStore.load(ctx, true),
      UserPosStore.load(ctx, true),
    ]).then((results: [Record<string, string[]>, Record<string, UserPosEntry>]) => {
      // Guarded: corrupt/unexpected persisted user data must NEVER take the
      // whole keyboard extension down. buildUserExpansion runs the
      // conjugation engine over on-disk data every launch, so a single bad
      // entry throwing here used to become an unhandled rejection that
      // recurred on every restart until the store was wiped (a
      // "reinstall-only" crash). On any failure, fall back to no user
      // dictionary rather than crashing — the keyboard still works.
      // [DEBUG-LOG] 拡張が本体アプリの書いた辞書を読めているかの切り分け用。
      // ここが 0件 なら本体アプリ→拡張の受け渡し自体が届いていない。
      // 件数が出るのに変換に出ないなら、原因は展開/候補側にある。
      // 件数だけ。読みや単語そのものは hilog に出さない (端末の共有ログに
      // ユーザーの登録内容が残るため)。
      console.info('shuntiIME reloadUserDict loaded',
        JSON.stringify({ dict: Object.keys(results[0]).length, pos: Object.keys(results[1]).length })); // [DEBUG-LOG]
      // 設定パネルの「登録済み」一覧が出す元データ (展開前の生の登録内容)。
      this.userDictRaw = results[0];
      try {
        const expansion = buildUserExpansion(results[0], results[1]);
        KanaKanjiConverter.setUserDict(expansion.dict);
        KanaKanjiConverter.setUserClassMap(expansion.classMap);
      } catch (e) {
        console.error('shuntiIME reloadUserDict expansion failed', JSON.stringify(e));
        KanaKanjiConverter.setUserDict({});
        KanaKanjiConverter.setUserClassMap({});
      }
    }).catch((err: Error) => {
      console.error('shuntiIME reloadUserDict load failed', JSON.stringify(err));
      KanaKanjiConverter.setUserDict({});
      KanaKanjiConverter.setUserClassMap({});
    });
  }

  // Reload keyboard-wide settings from disk (picks up the layout choice made
  // in the main app's settings screen, since that's a separate process).
  private reloadSettings(): void {
    if (!this.imeContext) {
      console.error('shuntiIME reloadSettings: no imeContext');
      return;
    }
    SettingsStore.load(this.imeContext, true)
      .then((s: KeyboardSettings) => {
        console.info('shuntiIME reloadSettings applied', JSON.stringify(s));
        AppStorage.setOrCreate('kanaKeyboardLayout', s.kanaKeyboardLayout);
        AppStorage.setOrCreate('alphabetKeyboardLayout', s.alphabetKeyboardLayout);
        AppStorage.setOrCreate('oneHandedMode', s.oneHandedMode);
        AppStorage.setOrCreate('oneHandedSide', s.oneHandedSide);
        AppStorage.setOrCreate('conversionEngine', s.conversionEngine);
        AppStorage.setOrCreate('numericPadEnabled', s.numericPadEnabled);
        AppStorage.setOrCreate('hapticEnabled', s.hapticEnabled);
        AppStorage.setOrCreate('themeMode', s.themeMode);
        AppStorage.setOrCreate('keyChromeEnabled', s.keyChromeEnabled);
        this.applyVocabPacks(s.vocabPackOverrides);
        this.applyComposingDisplay(s.composingInPanel, s.composingInField);
        this.hapticEnabled = s.hapticEnabled;
        this.applyConversionEngine(s.conversionEngine);
        this.applyThemeMode(s.themeMode);
        // computeKeyHeight/applyKeyboardWidthsForVp は AppStorage の
        // keyboardHeightScale/flickSideColumnRatio を読むが、起動直後の
        // initPanel はこの読み込みより先に (既定値のまま) 一度走っている
        // ことがある。ここで値を入れたうえで resizePanel を呼び直し、
        // 保存済みの調整を確実に反映させる。
        AppStorage.setOrCreate('keyboardHeightScale', s.keyboardHeightScale);
        AppStorage.setOrCreate('flickSideColumnRatio', s.flickSideColumnRatio);
        this.kbCtrlRef?.resizePanel();
      });
  }

  // Track B (mozc-derived) is loaded lazily -- only the first time the
  // conversionEngine setting is actually 'mozc' -- so users who never touch
  // the toggle pay zero extra startup cost/memory for it. Safe to call
  // repeatedly: loadMozcEngine() is a no-op cost-wise once already loaded
  // (isMozcLoaded() short-circuits), and setEngine('custom') is always cheap.
  private applyConversionEngine(engine: string): void {
    if (engine !== 'mozc' && engine !== 'hybrid') {
      KanaKanjiConverter.setEngine('custom');
      return;
    }
    const target: 'mozc' | 'hybrid' = engine === 'hybrid' ? 'hybrid' : 'mozc';
    if (KanaKanjiConverter.isMozcLoaded()) {
      KanaKanjiConverter.setEngine(target);
      return;
    }
    if (!this.imeContext) { return; }
    this.loadMozcRawfiles(this.imeContext, target);
  }

  // Fetch + parse the mozc rawfiles and hand them to the converter. Every
  // per-reading structure (dict surfaces, cost/class/surface per sense) is
  // pre-flattened at build time by tools/mozc_data/convert_to_binary.py --
  // the device only JSON.parses three plain string[] arrays (no per-key
  // object/hash overhead, unlike the old Record<string, ...> shape) and
  // reads the rest as typed-array binaries with zero parse cost. This is
  // what fixed the OOM crash: the old code's JSON.parse of mozc_dict.json/
  // mozc_costs.json built a transient object tree (~183MB + ~286MB
  // resident) that coexisted with its own flattened output at the peak,
  // well over the extension's ~464MB heap budget. A catchable failure just
  // falls back to custom.
  // 読み終わるまで isMozcLoaded() は false のままなので、起動直後に
  // applyConversionEngine が二度呼ばれると読み込みも二度走る (実機ログで確認)。
  // 読み込み中であることを別に覚えておいて、二本目は目標エンジンだけ更新する。
  private mozcLoading: boolean = false;
  private mozcLoadTarget: 'mozc' | 'hybrid' = 'mozc';

  private loadMozcRawfiles(ctx: InputMethodExtensionContext, target: 'mozc' | 'hybrid' = 'mozc'): void {
    this.mozcLoadTarget = target;
    if (this.mozcLoading) { return; }
    this.mozcLoading = true;
    const rm = ctx.resourceManager;
    // toAligned: getRawFileContent's Uint8Array may sit at a non-even
    // byteOffset, which Uint32Array/Int32Array/Uint16Array can't wrap
    // directly -- copy into a fresh aligned buffer first. Device is
    // little-endian, matching the files written by the build scripts.
    // The big UTF-8 blobs are read as Uint8Array and used as-is (no copy).
    const toBuf = (data: Uint8Array, byteOffset: number, byteLength: number): ArrayBuffer =>
      data.buffer.slice(data.byteOffset + byteOffset, data.byteOffset + byteOffset + byteLength);
    // 全ファイルを並行して読む。以前は1本ずつ .then() で繋いでいたが、
    // ここは純粋な読み込みで互いに依存が無く、直列にする理由が無い。
    const names: string[] = [
      'mozc_readings.blob', 'mozc_readings.len', 'mozc_readings.base', 'mozc_readings.srt',
      'mozc_dict_surfaces.blob', 'mozc_dict_surfaces.len', 'mozc_dict_surfaces.base',
      'mozc_dict_index.bin',
      'mozc_costs_surfaces.blob', 'mozc_costs_surfaces.len', 'mozc_costs_surfaces.base',
      'mozc_costs_index.bin', 'mozc_costs.bin',
      'mozc_matrix.json', 'mozc_matrix.bin',
    ];
    Promise.all(names.map((n: string) => rm.getRawFileContent(n)))
      .then((all: Uint8Array[]) => {
        const u32 = (d: Uint8Array): Uint32Array => new Uint32Array(toBuf(d, 0, d.byteLength));
        const costsIndex = u32(all[11]);
        // mozc_costs.bin layout: int32 cost[n] + uint16 left[n] + uint16 right[n]
        // (see convert_to_binary.py write_outputs). n_senses = last cumulative index.
        const costsBin = all[12];
        const nSenses = costsIndex[costsIndex.length - 1];
        const tables: MozcPackedTables = {
          readBlob: all[0], readLens: all[1], readBase: u32(all[2]), readSorted: u32(all[3]),
          dictSurfBlob: all[4], dictSurfLens: all[5], dictSurfBase: u32(all[6]),
          dictIndex: u32(all[7]),
          costSurfBlob: all[8], costSurfLens: all[9], costSurfBase: u32(all[10]),
          costsIndex: costsIndex,
          costsCost: new Int32Array(toBuf(costsBin, 0, nSenses * 4)),
          costsLeft: new Uint16Array(toBuf(costsBin, nSenses * 4, nSenses * 2)),
          costsRight: new Uint16Array(toBuf(costsBin, nSenses * 4 + nSenses * 2, nSenses * 2)),
        };
        const decoder = new util.TextDecoder('utf-8');
        const matrix = JSON.parse(decoder.decode(all[13])) as MozcMatrixData;
        // The connection matrix cells ship as a separate flat uint16 binary
        // (mozc_matrix.bin) rather than inside the JSON, so it can be read
        // straight into a Uint16Array without a multi-megabyte JSON parse or
        // a boxed number[][] -- the change that keeps mozc inside the heap.
        const cells = new Uint16Array(toBuf(all[14], 0, all[14].byteLength));
        this.mozcLoading = false;
        KanaKanjiConverter.loadMozcEngine(tables, matrix, cells);
        KanaKanjiConverter.setEngine(this.mozcLoadTarget);
      })
      .catch((e: Error) => {
        this.mozcLoading = false;
        console.error('shuntiIME mozc engine load failed, staying on custom', JSON.stringify(e));
        KanaKanjiConverter.setEngine('custom');
      });
  }

  // One-handed mode is toggled from the keyboard's own settings panel, so it
  // can persist AppStorage's current value directly rather than re-reading it.
  setOneHandedMode(enabled: boolean, side: string): void {
    AppStorage.setOrCreate('oneHandedMode', enabled);
    AppStorage.setOrCreate('oneHandedSide', side);
    if (this.imeContext) {
      SettingsStore.saveOneHanded(this.imeContext, enabled, side);
    }
  }

  // Toggle one-handed mode for a given side, driven by the same key-swipe both
  // to enter and to leave: an up-swipe engages that side, and repeating it while
  // already leaning that way returns to full width. Swiping the other side's key
  // switches sides directly.
  toggleOneHanded(side: string): void {
    const on = AppStorage.get<boolean>('oneHandedMode') ?? false;
    const cur = AppStorage.get<string>('oneHandedSide') ?? 'right';
    if (on && cur === side) {
      this.setOneHandedMode(false, side);
    } else {
      this.setOneHandedMode(true, side);
    }
  }

  // Switching the keyboard layout from the keyboard's own settings panel
  // takes effect immediately (same process, no reload round-trip needed) —
  // more reliable than the main-app toggle, which depends on the extension
  // picking the change back up on its own next reload. かな/アルファベット are
  // independent settings (each can be QWERTY or FLICK on its own).
  setKanaKeyboardLayout(layout: string): void {
    AppStorage.setOrCreate('kanaKeyboardLayout', layout);
    if (this.imeContext) {
      SettingsStore.saveKanaKeyboardLayout(this.imeContext, layout);
    }
  }

  setAlphabetKeyboardLayout(layout: string): void {
    AppStorage.setOrCreate('alphabetKeyboardLayout', layout);
    if (this.imeContext) {
      SettingsStore.saveAlphabetKeyboardLayout(this.imeContext, layout);
    }
  }

  // Same immediate-switch pattern as setOneHandedMode/setKanaKeyboardLayout
  // above. Toggling this off while the 数字パッド (numeric subMode) happens
  // to be open would strand the user on a panel cycleInputMode's あA key can
  // no longer reach -- fall back to kana so the setting and the panel
  // actually on screen never disagree.
  // ---- 打鍵時の振動 -------------------------------------------------------
  //
  // 設定はキーボード側で持つ (本体アプリとはデータを共有できないため)。
  // 実際に振動させるかは毎回 AppStorage を読まず、この場に控えた値で判断する。
  // 打鍵ごとに走る経路なので、余計な読み出しを挟まない。
  private hapticEnabled: boolean = false;

  setHapticEnabled(enabled: boolean): void {
    this.hapticEnabled = enabled;
    AppStorage.setOrCreate('hapticEnabled', enabled);
    if (this.imeContext) {
      SettingsStore.saveHapticEnabled(this.imeContext, enabled);
    }
    // 切り替えた手応えとして一度鳴らす。オンにしたことがその場で分かる。
    // ここで方式の判定も走る。
    if (enabled) { this.hapticMode = 0; this.hapticTick(); }
  }

  // 振動の鳴らし方。最初の1回で試して決める。
  //   0 = 未判定 / 1 = プリセット効果 / 2 = 時間指定 / 3 = 旧FA系 / -1 = 鳴らせない
  //
  // 現状のHarmonyOSでは、この経路はまず通らない。入力方式の拡張プロセスは
  // SELinux上 input_isolate_hap (デバッグ版は input_isolate_debug_hap)
  // というドメインで動き、そこから振動サービスへの接続が明示的に禁じられている。
  //
  //   allow { normal_hap_attr -input_isolate_attr }
  //         sa_miscdevice_service:samgr_class { get };
  //
  // 実機のログにも avc: denied { get } ... sa_miscdevice_service が出て、
  // startVibration は 14600101 (Device operation failed) で返る。
  // 権限 (VIBRATE) は付与済みで、同じ端末でも本体アプリからは鳴る。つまり
  // 権限でも端末差でもなく、プロセスの種別による遮断であり、アプリ側では
  // 解決できない (リリース版でも同じドメイン属性なので配信しても変わらない)。
  //
  // OSが方針を変えれば以下がそのまま動くため、実装は残してある。
  private hapticMode: number = 0;

  private probeHaptic(): void {
    AppStorage.setOrCreate('hapticUnavailable', false);
    // 1) プリセット効果。端末が用意している「カチッ」を借りる方式。
    vibrator.startVibration({ type: 'preset', effectId: 'haptic.clock.timer', count: 1 },
      { id: 0, usage: 'physicalFeedback' })
      .then(() => { this.hapticMode = 1; })
      .catch((_e1: ESObject) => {
        // 2) 時間指定 + usage:'touch'。物理フィードバック扱いを避ける。
        vibrator.startVibration({ type: 'time', duration: 30 }, { id: 0, usage: 'touch' })
          .then(() => { this.hapticMode = 2; })
          .catch((_e2: ESObject) => {
            this.markHapticUnavailable();
          });
      });
  }

  // どの方式でも鳴らせなかった。
  //
  // 効かない設定を残しても混乱させるだけなので、自動でオフに戻して
  // 「この端末では使えない」と示せるようにする。
  private markHapticUnavailable(): void {
    this.hapticMode = -1;
    this.hapticEnabled = false;
    AppStorage.setOrCreate('hapticEnabled', false);
    AppStorage.setOrCreate('hapticUnavailable', true);
    if (this.imeContext) { SettingsStore.saveHapticEnabled(this.imeContext, false); }
  }

  // キーを押した瞬間に呼ぶ。判定済みの方式で鳴らす。
  // 鳴らせないと分かっている端末では何もしない (毎回失敗を投げても無駄なので)。
  hapticTick(): void {
    if (!this.hapticEnabled) { return; }
    if (this.hapticMode === -1) { return; }
    if (this.hapticMode === 0) { this.probeHaptic(); return; }
    const effect: ESObject = this.hapticMode === 1
      ? { type: 'preset', effectId: 'haptic.clock.timer', count: 1 }
      : { type: 'time', duration: 30 };
    const usage: string = this.hapticMode === 1 ? 'physicalFeedback' : 'touch';
    try {
      vibrator.startVibration(effect as ESObject, { id: 0, usage: usage } as ESObject)
        .catch((_e: ESObject) => {});
    } catch (_e) {
      // 非対応端末。鳴らないだけで害は無い。
    }
  }

  // キーボードのライト／ダーク。即時反映し、OS のカラーモード変更は
  // 'system' のときだけ追従する (applyColorMode / applyColorModeFrom)。
  setThemeMode(mode: string): void {
    AppStorage.setOrCreate('themeMode', mode);
    this.applyThemeMode(mode);
    if (this.imeContext) {
      SettingsStore.saveThemeMode(this.imeContext, mode);
    }
  }

  private applyThemeMode(mode: string): void {
    if (!this.imeContext) {
      AppStorage.setOrCreate('isDark', resolveIsDark(mode, AppStorage.get<boolean>('isDark') ?? false));
      return;
    }
    AppStorage.setOrCreate('isDark', resolveIsDark(mode, isDarkFromResourceManager(this.imeContext as ESObject)));
  }

  setKeyChromeEnabled(enabled: boolean): void {
    AppStorage.setOrCreate('keyChromeEnabled', enabled);
    if (this.imeContext) {
      SettingsStore.saveKeyChromeEnabled(this.imeContext, enabled);
    }
  }

  setNumericPadEnabled(enabled: boolean): void {
    AppStorage.setOrCreate('numericPadEnabled', enabled);
    if (!enabled && AppStorage.get<string>('keyboardSubMode') === 'numeric') {
      AppStorage.setOrCreate('keyboardSubMode', 'kana');
    }
    if (this.imeContext) {
      SettingsStore.saveNumericPadEnabled(this.imeContext, enabled);
    }
  }

  // Shared "あA"/"Aあ" mode-switch key handler for both FlickKeyboardView and
  // KeyboardView. With 数字パッド enabled this cycles 日本語→アルファベット→数字→
  // (back to 日本語 via NumericPadView's exit key); with it disabled the key
  // only toggles 日本語⇔アルファベット, matching the pre-numeric-pad behavior.
  cycleInputMode(): void {
    const inputMode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    const numericPadEnabled = AppStorage.get<boolean>('numericPadEnabled') ?? false;
    if (inputMode === InputMode.ALPHANUMERIC) {
      if (numericPadEnabled) {
        AppStorage.setOrCreate('keyboardSubMode', 'numeric');
      } else {
        AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
      }
      return;
    }
    AppStorage.setOrCreate('inputMode', InputMode.ALPHANUMERIC);
  }

  // Same immediate-switch pattern as setKanaKeyboardLayout above. applyConversionEngine
  // lazily fetches the mozc rawfiles the first time 'mozc' is actually selected.
  setConversionEngine(engine: string): void {
    AppStorage.setOrCreate('conversionEngine', engine);
    this.applyConversionEngine(engine);
    if (this.imeContext) {
      SettingsStore.saveConversionEngine(this.imeContext, engine);
    }
  }

  // 入力中のかなの表示先の切替 (設定画面 → SettingsBar)。2つは独立で、
  // 両方OFFにもできる (どこにも出なくなるので設定画面側で警告を出す)。
  setComposingDisplay(inPanel: boolean, inField: boolean): void {
    this.applyComposingDisplay(inPanel, inField);
    if (this.imeContext) {
      SettingsStore.saveComposingDisplay(this.imeContext, inPanel, inField);
    }
  }

  // 保存せずに反映だけする。設定の読み直しは拡張側 (reloadSettings) と
  // パネル側 (KeyboardPage.reloadSettingsIntoStorage) の両方から走るので、
  // 読み直しのたびに書き戻さないよう保存と分けてある。
  applyComposingDisplay(inPanel: boolean, inField: boolean): void {
    this.composingInPanel = inPanel;
    this.composingInField = inField;
    AppStorage.setOrCreate('composingInPanel', inPanel);
    AppStorage.setOrCreate('composingInField', inField);
    // 入力欄側をOFFにした瞬間、出したままのプレビューを消す。
    if (!inField) { this.cancelPreviewText(); }
    this.publishPreviewMode();
  }

  // レイアウト調整モード (設定 → レイアウト調整) からの参照。パネルの
  // 実サイズ変更 (panel.resize) はこのクラスからはできず、それを持っている
  // KeyboardController (拡張本体) へ委譲する必要があるので、生成時に
  // 向こうから自分を渡してもらう (KeyboardController.onCreate 参照)。
  private kbCtrlRef: KeyboardController | undefined = undefined;

  setKeyboardControllerRef(ctrl: KeyboardController): void {
    this.kbCtrlRef = ctrl;
  }

  // 縦の長さスライダー。ドラッグ中に毎回呼ばれる想定なので、保存は別
  // (saveKeyboardHeightScale) にして、ここは AppStorage の書き換えと
  // パネルの実リサイズだけをその場でやる。
  applyKeyboardHeightScaleLive(scale: number): void {
    AppStorage.setOrCreate('keyboardHeightScale', scale);
    this.kbCtrlRef?.resizePanel();
  }

  saveKeyboardHeightScale(scale: number): void {
    this.applyKeyboardHeightScaleLive(scale);
    if (this.imeContext) {
      SettingsStore.saveKeyboardHeightScale(this.imeContext, scale);
    }
  }

  // 中央3列 : 左右特殊キー1列 の比率スライダー。パネル自体のサイズは
  // 変わらないので、幅の再計算 (applyKeyboardWidthsForVp) だけで足りる。
  applyFlickSideRatioLive(ratio: number): void {
    AppStorage.setOrCreate('flickSideColumnRatio', ratio);
    const vp = AppStorage.get<number>('keyboardContentVp') ?? 0;
    if (vp <= 0) { return; }
    const isTabletClass = AppStorage.get<boolean>('isTabletClass') ?? false;
    applyKeyboardWidthsForVp(vp, isTabletClass);
  }

  saveFlickSideRatio(ratio: number): void {
    this.applyFlickSideRatioLive(ratio);
    if (this.imeContext) {
      SettingsStore.saveFlickSideRatio(this.imeContext, ratio);
    }
  }

  // 設定画面のリセットボタン。両方とも既定 (1.0 = 今までどおり) へ戻す。
  resetLayoutAdjust(): void {
    this.saveKeyboardHeightScale(1.0);
    this.saveFlickSideRatio(1.0);
  }

  // 語彙パックの明示的な ON/OFF (利用者が自分で触ったものだけ)。
  // ここに無いパックは .pack の default: ヘッダに従う。
  private vocabPackOverrides: Record<string, boolean> = {};

  // manifest が届いたあとに呼ばれる。保存済みの指定でもう一度反映する。
  refreshVocabPacks(): void {
    this.applyVocabPacks(this.vocabPackOverrides);
  }

  // 有効なパックの語彙バイナリだけを読む。
  //
  // 地名パックは1つで最大8千語あるので、無効なものまで読むとパックに分けた
  // 意味が無くなる。読み込みは一度きり (isVocabPackLoaded) で、以後の
  // ON/OFF は enabledPacks の出し入れだけで済む -- 一度読んだものを捨てて
  // また読み直すほうが、切り替えのたびに待たされて体感が悪い。
  private loadEnabledPackData(ids: string[]): void {
    const ctx = this.imeContext;
    if (!ctx) { return; }
    const rm = ctx.resourceManager;
    const toU32 = (d: Uint8Array): Uint32Array =>
      new Uint32Array(d.buffer.slice(d.byteOffset, d.byteOffset + d.byteLength));
    for (const id of ids) {
      if (KanaKanjiConverter.isVocabPackLoaded(id)) { continue; }
      const base = 'pack_' + id;
      const names: string[] = [
        base + '.keys.blob', base + '.keys.len', base + '.keys.base',
        base + '.vals.blob', base + '.vals.len', base + '.vals.base',
        base + '.idx.bin',
      ];
      Promise.all(names.map((n: string) => rm.getRawFileContent(n)))
        .then((all: Uint8Array[]) => {
          KanaKanjiConverter.setVocabPackPacked(id, all[0], all[1], toU32(all[2]),
            all[3], all[4], toU32(all[5]), toU32(all[6]));
        })
        .catch((e: Error) => {
          console.error('shuntiIME vocab pack load failed: ' + id, JSON.stringify(e));
        });
    }
  }

  // 明示指定 (overrides) と .pack の既定から実際に有効なパックを決めて反映する。
  private applyVocabPacks(overrides: Record<string, boolean>): void {
    this.vocabPackOverrides = overrides;
    const enabled = KanaKanjiConverter.resolveEnabledPacks(overrides);
    KanaKanjiConverter.setEnabledPackIds(enabled);
    AppStorage.setOrCreate('enabledVocabPacks', enabled);
    AppStorage.setOrCreate('vocabPackOverrides', overrides);
    this.loadEnabledPackData(enabled);
  }

  // 語彙パックのON/OFF切替 (設定画面 → SettingsBar)。パック自体の中身は
  // loadVocabPacks で既に読み込み済み (どのパックもロードだけでは効かない)
  // なので、ここは有効/無効の集合を切り替えて保存するだけで即座に候補へ
  // 反映される。
  setVocabPackEnabled(id: string, enabled: boolean): void {
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(this.vocabPackOverrides)) { next[k] = this.vocabPackOverrides[k]; }
    next[id] = enabled;
    this.applyVocabPacks(next);
    if (this.imeContext) {
      SettingsStore.saveVocabPackOverrides(this.imeContext, next);
    }
  }

  // 学習系の保存はどれもデバウンスされている。打鍵のたびに数万件の JSON を
  // 書き出すわけにいかないので、それ自体は正しい。問題は「予約したまま消える」
  // 経路が塞がれていなかったこと。
  //
  //   入力 -> 2秒後に書く予約 -> キーボードが閉じる/拡張が落とされる
  //        -> タイマーごと消える -> 一度も書かれない
  //
  // IME拡張は入力欄を離れるたびに落とされうるので、これは例外ケースではなく
  // 通常の経路だった。学習も削除した候補もメモリ上では効くため、使っている間は
  // 正常に見えて、次の起動には何も残っていない ── 「削除した候補」がずっと空
  // だったのも、5つのストアが揃って空だったのもこれ。
  // 対処は flushPendingSaves()。セッション終了時と onDestroy で必ず呼ぶ。
  //
  // ただし flushPendingSaves() は onInputStop/onDestroy が実際に呼ばれる
  // 正常終了の経路にしか効かない。OS がプロセスを強制終了する経路
  // (メモリ逼迫など、onInputStop を経由しない) では、デバウンス待ちの間隔
  // そのものが「学習が失われる窓」として残り続ける。
  // 実データで確認済み: 「し」を選んで「志」を学習した13日後、同じ「志」を
  // 再度選んだ記録が学習前の並び順 (18/40) から始まっていた ── その1回目の
  // 保存がどこかで消えていたことになる。候補削除 (suppressedSaveTimer) は
  // 元々 500ms だったのに、学習系だけ 2000ms のままだったのは単なる
  // 不揃いで、学習が候補削除より軽視していい理由は無い。窓を揃えて縮める。
  //
  // dirty フラグは、変化が無いのに閉じるたび4本書きに行かないためのもの。

  private writeLearning(): void {
    if (!this.learningDirty) { return; }
    const prefs = this.learningPrefs;
    if (!prefs) { return; }
    this.learningDirty = false;
    prefs.put('v1', JSON.stringify(KanaKanjiConverter.getLearned()))
      .then(() => prefs.flush())
      .catch((e: Error) => { InputLog.recordInit('shunti_learning(保存)', e); }); // [DEBUG-LOG]
  }

  private saveLearning(): void {
    this.learningDirty = true;
    clearTimeout(this.learningSaveTimer);
    this.learningSaveTimer = setTimeout(() => { this.writeLearning(); }, 500);
  }

  private writeNextWord(): void {
    if (!this.nextWordDirty) { return; }
    const prefs = this.nextWordPrefs;
    if (!prefs) { return; }
    this.nextWordDirty = false;
    prefs.put('v1', JSON.stringify(NextWordPredictor.getLearned()))
      .then(() => prefs.flush())
      .catch((e: Error) => { InputLog.recordInit('shunti_nextword(保存)', e); }); // [DEBUG-LOG]
  }

  private saveNextWord(): void {
    this.nextWordDirty = true;
    clearTimeout(this.nextWordSaveTimer);
    this.nextWordSaveTimer = setTimeout(() => { this.writeNextWord(); }, 500);
  }

  private writeUnknownWords(): void {
    if (!this.unknownWordDirty) { return; }
    const prefs = this.unknownWordPrefs;
    if (!prefs) { return; }
    this.unknownWordDirty = false;
    prefs.put('v1', JSON.stringify(UnknownWordLearner.getLearned()))
      .then(() => prefs.flush())
      .catch((e: Error) => { InputLog.recordInit('shunti_unknown(保存)', e); }); // [DEBUG-LOG]
  }

  private saveUnknownWords(): void {
    this.unknownWordDirty = true;
    clearTimeout(this.unknownWordSaveTimer);
    this.unknownWordSaveTimer = setTimeout(() => { this.writeUnknownWords(); }, 500);
  }

  // ---- 辞書登録 (キーボード内で完結させるための API) ----------------------
  //
  // 本体アプリの辞書画面から登録した語は、キーボードには一切届かない。
  // 入力方式の拡張は別プロセスかつ別サンドボックスで動いており、本体アプリが
  // 書いた preferences を拡張から読むと空になる (実機で確認済み: 本体側には
  // 160B の shunti_userdict があるのに、拡張の reloadUserDict は 0 件)。
  // プラットフォーム側の共有手段 (dataGroupIds + getGroupDir) は応用市場での
  // 発行が前提で、このアカウントでは開放されていない。
  // よって登録も一覧も、変換を行っているこの拡張プロセス側で完結させる。
  //
  // 登録候補は UnknownWordLearner が既に持っている「ユーザーが組み立てたが
  // 辞書に無い語」をそのまま使う。読みと表記を手で打ち直させる必要が無く、
  // パネル内に自由入力欄を作らずに済む。

  // 登録候補 (組み立てられた未知語) を出現回数の多い順に。
  // 文字列1本 "よみ\t表記\t回数" で返すのは、ArkTS の @StorageLink に
  // 構造体配列を載せると更新検知が効きにくいため。
  // 1回しか組み立てられていないものは出さない。
  //
  // 連続して打った2語は、1語を組み立てた場合と構造上まったく区別できない。
  // 実際「丸一日」と「本山」を続けて打っただけで「丸一日本山」が候補に上がって
  // いた。判定で弾くことはできない (春+知 のような本当に登録したい組み立ても
  // 同じ形になる) ので、回数で見る。偶然の隣接は繰り返されないが、実際に使う
  // 語は何度も組み立て直すことになる。
  private static readonly SUGGEST_MIN_COUNT = 2;

  getUnknownWordSuggestions(): string[] {
    const counts = UnknownWordLearner.getLearned();
    const rows: string[] = [];
    for (const reading of Object.keys(counts)) {
      const entry = counts[reading];
      for (const surface of Object.keys(entry)) {
        if (entry[surface] < InputHandler.SUGGEST_MIN_COUNT) { continue; }
        rows.push(`${reading}\t${surface}\t${entry[surface]}`);
      }
    }
    rows.sort((a: string, b: string) => {
      const ca = Number.parseInt(a.split('\t')[2], 10);
      const cb = Number.parseInt(b.split('\t')[2], 10);
      return cb - ca;
    });
    return rows;
  }

  // 登録済みユーザー辞書を "よみ\t表記" で。変換器に渡すのは活用展開後の辞書
  // なので、一覧には reloadUserDict が控えておいた「登録したそのままの内容」を使う。
  getUserDictRows(): string[] {
    const dict = this.userDictRaw;
    const rows: string[] = [];
    for (const reading of Object.keys(dict)) {
      for (const surface of dict[reading]) { rows.push(`${reading}\t${surface}`); }
    }
    rows.sort();
    return rows;
  }

  // AppStorage 経由で UI に配る。パネルは @StorageLink でこれを見る。
  publishDictRows(): void {
    AppStorage.setOrCreate('dictSuggestions', this.getUnknownWordSuggestions());
    AppStorage.setOrCreate('dictRegistered', this.getUserDictRows());
  }

  // 1件を本登録する。拡張自身の preferences に書くので、次の reloadUserDict で
  // そのまま変換に反映される。登録済みの語は未知語リストから外す。
  // 品詞つきで登録する。品詞は活用展開 (ConjugationEngine.buildUserExpansion) を
  // 駆動するので、動詞や形容詞は指定しないと「〜ます」「〜た」等で引けない。
  // pos が 'noun' のときは UserPosStore 側で保存しない (既定扱い)。
  registerUserWordWithPos(reading: string, surface: string, pos: string, group: string): void {
    if (!this.imeContext) { return; }
    if (pos === 'noun') {
      this.registerUserWord(reading, surface);
      return;
    }
    const ctx = this.imeContext;
    const entry: UserPosEntry = group.length > 0
      ? { pos: pos as PosKind, group: group as VerbGroup }
      : { pos: pos as PosKind };
    UserPosStore.load(ctx, true)
      .then((map: Record<string, UserPosEntry>) => {
        const next = UserPosStore.set(map, reading, surface, entry);
        return UserPosStore.save(ctx, next);
      })
      .then(() => { this.registerUserWord(reading, surface); })
      .catch((e: ESObject) => {
        console.error('shuntiIME registerUserWordWithPos failed', JSON.stringify(e));
        // 品詞が保存できなくても、語そのものは登録しておく。
        this.registerUserWord(reading, surface);
      });
  }

  registerUserWord(reading: string, surface: string): void {
    if (!this.imeContext) {
      console.error('shuntiIME registerUserWord: imeContext なし');
      return;
    }
    if (reading.length === 0 || surface.length === 0) { return; }
    const ctx = this.imeContext;
    UserDictStore.load(ctx, true)
      .then((dict: Record<string, string[]>) => {
        const next: Record<string, string[]> = {};
        for (const k of Object.keys(dict)) { next[k] = dict[k]; }
        const cur = next[reading];
        if (cur === undefined) {
          next[reading] = [surface];
        } else if (cur.indexOf(surface) < 0) {
          const merged: string[] = [surface];
          for (const w of cur) { merged.push(w); }
          next[reading] = merged;
        }
        return UserDictStore.save(ctx, next).then(() => next);
      })
      .then((next: Record<string, string[]>) => {
        // 一覧は保存できた内容から直接作る。reloadUserDict の完了を待って
        // タイマーで配り直す形にしていたが、間に合わないと登録直後の一覧が
        // 古いままになり「登録できていない」ように見える。
        this.userDictRaw = next;
        UnknownWordLearner.forget(reading, surface);
        this.saveUnknownWords();
        this.publishDictRows();
        // 変換への反映 (活用展開) は別途。こちらは表示に影響しない。
        this.reloadUserDict();
        console.info('shuntiIME registerUserWord ok', reading + '→' + surface,
          '登録数=' + String(Object.keys(next).length));
      })
      .catch((e: ESObject) => { console.error('shuntiIME registerUserWord failed', JSON.stringify(e)); });
  }

  // ---- 自由入力 (任意の読み・単語を手で入れる) --------------------------
  //
  // '' = 通常 (確定文字はホストアプリへ) / 'yomi' | 'word' = その欄へ。
  // 実際の振り分けは insertText と handleBackspace で行う。

  // 設定パネルはキーボードの代わりに全面を占有するため、その中に入力欄を置いても
  // 打つキーが無い。登録欄はキーボードを残したまま候補バーの位置に出す
  // (DictEditBar)。ここではそのモードに入り、設定パネルを畳んで、最初の欄を
  // 掴むところまでを行う。
  beginDictEdit(): void {
    this.clearDictEdit();
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    AppStorage.setOrCreate('dictEditMode', true);
    this.startCapture('yomi');
  }

  endDictEdit(): void {
    this.stopCapture();
    AppStorage.setOrCreate('dictEditMode', false);
    this.clearDictEdit();
  }

  startCapture(target: string): void {
    // 入力途中の変換状態を持ち越すと、欄を切り替えた瞬間に前の欄の続きが
    // 入ってしまう。切り替えのたびに畳む。
    this.resetComposition();
    this.captureTarget = target;
    AppStorage.setOrCreate('dictCaptureTarget', target);
  }

  stopCapture(): void {
    this.resetComposition();
    this.captureTarget = '';
    AppStorage.setOrCreate('dictCaptureTarget', '');
  }

  private appendCaptured(text: string): void {
    const key = this.captureTarget === 'yomi' ? 'dictEditYomi' : 'dictEditWord';
    const cur = AppStorage.get<string>(key) ?? '';
    AppStorage.setOrCreate(key, cur + text);
  }

  private backspaceCaptured(): void {
    const key = this.captureTarget === 'yomi' ? 'dictEditYomi' : 'dictEditWord';
    const cur = AppStorage.get<string>(key) ?? '';
    if (cur.length > 0) { AppStorage.setOrCreate(key, cur.slice(0, cur.length - 1)); }
  }

  clearDictEdit(): void {
    AppStorage.setOrCreate('dictEditYomi', '');
    AppStorage.setOrCreate('dictEditWord', '');
    AppStorage.setOrCreate('dictEditPos', 'noun');
    AppStorage.setOrCreate('dictEditVerbGroup', '');
  }

  // 自由入力の内容を登録する。読みがひらがな以外だと変換で引けないので弾く。
  // 戻り値は画面に出すメッセージ (空なら成功)。
  commitDictEdit(): string {
    const yomi = AppStorage.get<string>('dictEditYomi') ?? '';
    const word = AppStorage.get<string>('dictEditWord') ?? '';
    if (yomi.length === 0 || word.length === 0) { return 'よみと単語の両方を入れてください'; }
    for (let i = 0; i < yomi.length; i++) {
      const c = yomi.charCodeAt(i);
      const hira = c >= 0x3041 && c <= 0x309f;
      const choon = c === 0x30fc;
      if (!hira && !choon) { return 'よみはひらがなで入れてください'; }
    }
    const pos = AppStorage.get<string>('dictEditPos') ?? 'noun';
    // 動詞で読みが「る」で終わる場合、五段と一段が字面で区別できない
    // (detectGodanRow のコメント参照)。活用を出し分けるため種別が要る。
    const group = AppStorage.get<string>('dictEditVerbGroup') ?? '';
    if (pos === 'verb' && yomi.endsWith('る') && group.length === 0) {
      return '動詞の種類(五段/一段)を選んでください';
    }
    this.registerUserWordWithPos(yomi, word, pos, pos === 'verb' ? group : '');
    this.clearDictEdit();
    return '';
  }

  // ---- 削除した候補の一覧・復元 -----------------------------------------
  //
  // 候補の長押し削除は拡張プロセス側で完結しているのに、一覧と復元は本体アプリの
  // 画面にしか無かった。両者はサンドボックスが別なので、アプリからは常に空にしか
  // 見えず「消したら二度と戻せない」状態だった。書いている側で見せる。

  publishSuppressedRows(): void {
    const map = SuppressedCandidates.getSuppressed();
    const rows: string[] = [];
    for (const reading of Object.keys(map)) {
      for (const surface of map[reading]) { rows.push(`${reading}\t${surface}`); }
    }
    rows.sort();
    AppStorage.setOrCreate('suppressedRows', rows);
  }

  restoreSuppressedWord(reading: string, surface: string): void {
    const next = SuppressedCandidates.restore(
      SuppressedCandidates.getSuppressed(), reading, surface);
    SuppressedCandidates.setSuppressed(next);
    this.saveSuppressed();
    this.publishSuppressedRows();
    // 内蔵辞書で作れない語は、抑制を解いただけでは戻らない。自分で登録して
    // 消した語がこれにあたる (削除時に登録からも外しているため)。
    // 作れないと分かったときだけ登録し直す。
    if (this.kanjiConverter.lookup(reading).indexOf(surface) < 0) {
      this.registerUserWord(reading, surface);
    }
    // 削除で候補から外れていた語をその場で戻す。
    this.updateCandidates();
  }

  clearAllSuppressed(): void {
    SuppressedCandidates.clear();
    this.saveSuppressed();
    this.publishSuppressedRows();
    this.updateCandidates();
  }

  // ---- 修復・リセット ---------------------------------------------------
  //
  // 本体アプリの「修復」は本体アプリ側のストアを消すだけで、キーボードの学習・
  // 設定・辞書には一切届かない (別サンドボックス)。壊れた状態からの復旧手段が
  // 実質機能していなかったので、こちらにも用意する。

  resetLearningData(): void {
    if (!this.imeContext) { return; }
    AppMaintenance.resetLearning(this.imeContext)
      .then(() => {
        KanaKanjiConverter.setLearned({});
        NextWordPredictor.setLearned({});
        InputHandler.symbolFreq = {};
        InputHandler.publishFrequentSymbols();
        UnknownWordLearner.setLearned({});
        this.publishDictRows();
        console.info('shuntiIME resetLearningData ok');
      })
      .catch((e: ESObject) => { console.error('shuntiIME resetLearningData failed', JSON.stringify(e)); });
  }

  resetAllData(): void {
    if (!this.imeContext) { return; }
    AppMaintenance.resetAll(this.imeContext)
      .then(() => {
        KanaKanjiConverter.setLearned({});
        NextWordPredictor.setLearned({});
        InputHandler.symbolFreq = {};
        InputHandler.publishFrequentSymbols();
        UnknownWordLearner.setLearned({});
        SuppressedCandidates.clear();
        this.userDictRaw = {};
        KanaKanjiConverter.setUserDict({});
        KanaKanjiConverter.setUserClassMap({});
        this.publishDictRows();
        this.publishSuppressedRows();
        console.info('shuntiIME resetAllData ok');
      })
      .catch((e: ESObject) => { console.error('shuntiIME resetAllData failed', JSON.stringify(e)); });
  }

  // ---- 入力ログの閲覧 (デバッグ専用) ------------------------------------ // [DEBUG-LOG]
  //
  // 本体アプリからは読めない。ログを書いているのは拡張プロセスで、
  // 本体アプリとはサンドボックスが別だから (registerUserWord のコメント参照)。
  // 収集した内容を見るには、書いた側であるここで読むしかない。

  publishInputLogRows(): void { // [DEBUG-LOG]
    const dir = InputLog.writerDir();
    if (dir.length === 0) {
      AppStorage.setOrCreate('inputLogSummary', '収集先が未設定です(初期化に失敗)');
      AppStorage.setOrCreate('inputLogRows', [] as string[]);
      return;
    }
    const raw = InputLog.readRaw(dir);
    const total = InputLog.countLines(raw);
    const bytes = InputLog.sizeBytes(dir);
    AppStorage.setOrCreate('inputLogSummary', `${total}件 / ${Math.round(bytes / 1024)}KB`);
    // デバッグ専用。精度改善のために後から眺めるものなので、表示が重くなることより
    // 「必要な行が切り捨てられていない」ことを優先して上限を大きく取る。
    const entries = InputLog.parse(raw, 20000);
    const rows: string[] = [];
    for (const e of entries) {
      // 種別・読み・確定した表記・何番目の候補か。詳細は書き出しで見る。
      const pick = e.i >= 0 ? ` [${e.i + 1}/${e.n}]` : '';
      rows.push(`${e.k}\t${e.r}\t${e.s}${pick}\t${e.x}`);
    }
    AppStorage.setOrCreate('inputLogRows', rows);
  }

  // 全文を hilog へ吐き出す。クリップボードの setData (生テキスト・URI 両方)は
  // この拡張プロセスからだと常に "async call failed" で落ちることを実測で確認
  // 済み (759,070 文字のテキストでも file:// URI でも同じ)。原因の切り分けは
  // 打ち切り、このセッション中ずっと問題なく読めている hilog 経由に変える --
  // サンドボックスの外から hdc で読める、ここまでで唯一確実な経路。
  //
  // Base64 にしてから 1 行 1500 文字ずつ区切って console.info する。生の
  // JSONL のまま流すと、たまたま長い1レコードが hilog の1行上限を超えたときに
  // そこだけ千切れる可能性がある。Base64 化しておけば区切り位置は文字数だけの
  // 問題になり、復元側 (PC 側スクリプト) で単純に連結してから戻せる。
  // 各行に SHUNTILOGDUMP という専用マーカーと連番/総数を入れているので、
  // hilog の他の行に紛れても grep で拾い、番号順に並べ直せる。
  exportInputLog(): void { // [DEBUG-LOG]
    const dir = InputLog.writerDir();
    if (dir.length === 0) {
      console.error('shuntiIME exportInputLog: no writerDir'); // [DEBUG-LOG]
      return;
    }
    const raw = InputLog.readRaw(dir);
    if (raw.length === 0) {
      console.error('shuntiIME exportInputLog: empty'); // [DEBUG-LOG]
      return;
    }
    const bytes = new util.TextEncoder().encodeInto(raw);
    const b64 = new util.Base64Helper().encodeToStringSync(bytes);
    const CHUNK = 1500;
    const total = Math.ceil(b64.length / CHUNK);
    console.info('shuntiIME SHUNTILOGDUMP_BEGIN total=' + String(total)
      + ' rawLen=' + String(raw.length) + ' b64Len=' + String(b64.length)); // [DEBUG-LOG]
    // まとめて書くと hilog 側のバースト制御に引っかかり、実測で733行中
    // 100行前後が静かに落ちた (2回試して毎回ほぼ同じ範囲が欠けた -- ランダムな
    // 取りこぼしではなく、書き込み速度そのものが上限を超えていた)。
    // 1回に少数ずつ・間隔を空けて書くことで確実性を優先する。
    const BATCH = 5;
    const INTERVAL_MS = 120;
    let i = 0;
    const writeBatch = (): void => {
      const end = Math.min(i + BATCH, total);
      for (; i < end; i++) {
        const chunk = b64.slice(i * CHUNK, (i + 1) * CHUNK);
        console.info('shuntiIME SHUNTILOGDUMP ' + String(i) + '/' + String(total) + ' ' + chunk); // [DEBUG-LOG]
      }
      if (i < total) {
        setTimeout(writeBatch, INTERVAL_MS);
      } else {
        console.info('shuntiIME SHUNTILOGDUMP_END'); // [DEBUG-LOG]
      }
    };
    writeBatch();
  }

  clearInputLog(): void { // [DEBUG-LOG]
    const dir = InputLog.writerDir();
    if (dir.length > 0) { InputLog.clear(dir); }
    this.publishInputLogRows();
  }

  // 登録候補をすべて消す。削除を考慮していなかった頃の壊れた対応が大量に
  // 溜まっているため、1件ずつ消さずに済む手段を用意する。
  clearUnknownWords(): void {
    UnknownWordLearner.setLearned({});
    this.saveUnknownWords();
    this.publishDictRows();
  }

  // 登録済みの1件を消す。
  //
  // 辞書から外すだけでなく「削除した候補」にも入れる。外しただけだと、同じ語が
  // 内蔵辞書にもあった場合に変換へ出続けて「消したのに出る」ことになるし、
  // 消した記録がどこにも残らないので戻す手段が無くなる。
  removeUserWord(reading: string, surface: string): void {
    if (!this.imeContext) { return; }
    const ctx = this.imeContext;
    UserDictStore.load(ctx, true)
      .then((dict: Record<string, string[]>) => {
        const next: Record<string, string[]> = {};
        for (const k of Object.keys(dict)) {
          if (k !== reading) { next[k] = dict[k]; continue; }
          const kept = dict[k].filter((w: string) => w !== surface);
          if (kept.length > 0) { next[k] = kept; }
        }
        return UserDictStore.save(ctx, next).then(() => next);
      })
      .then((next: Record<string, string[]>) => {
        this.userDictRaw = next;
        if (SuppressedCandidates.suppress(reading, surface)) {
          this.saveSuppressed();
          this.publishSuppressedRows();
        }
        this.publishDictRows();
        this.reloadUserDict();
      })
      .catch((e: ESObject) => { console.error('shuntiIME removeUserWord failed', JSON.stringify(e)); });
  }

  // 候補の長押し削除で消した語が自分の登録語だったら、登録からも外す。
  // 抑制だけして登録に残すと、「登録済み」に一生変換に出ない語が並んでしまう。
  private unregisterIfUserWord(reading: string, surface: string): void {
    const cur = this.userDictRaw[reading];
    if (cur === undefined || cur.indexOf(surface) < 0) { return; }
    if (!this.imeContext) { return; }
    const ctx = this.imeContext;
    const next: Record<string, string[]> = {};
    for (const k of Object.keys(this.userDictRaw)) {
      if (k !== reading) { next[k] = this.userDictRaw[k]; continue; }
      const kept = this.userDictRaw[k].filter((w: string) => w !== surface);
      if (kept.length > 0) { next[k] = kept; }
    }
    this.userDictRaw = next;
    UserDictStore.save(ctx, next)
      .then(() => { this.publishDictRows(); })
      .catch((e: ESObject) => { console.error('shuntiIME unregisterIfUserWord failed', JSON.stringify(e)); });
  }

  // 登録候補から外す (辞書には入れない)。
  dismissUnknownWord(reading: string, surface: string): void {
    UnknownWordLearner.forget(reading, surface);
    this.saveUnknownWords();
    this.publishDictRows();
  }

  private writeSuppressed(): void {
    if (!this.suppressedDirty) { return; }
    const prefs = this.suppressedPrefs;
    if (!prefs) { return; }
    this.suppressedDirty = false;
    prefs.put(SUPPRESSED_KEY, JSON.stringify(SuppressedCandidates.getSuppressed()))
      .then(() => prefs.flush())
      .catch((e: Error) => { InputLog.recordInit('shunti_suppressed(保存)', e); }); // [DEBUG-LOG]
  }

  private saveSuppressed(): void {
    this.suppressedDirty = true;
    clearTimeout(this.suppressedSaveTimer);
    this.suppressedSaveTimer = setTimeout(() => { this.writeSuppressed(); }, 500);
  }

  // 予約されている保存を今すぐ全部書く。入力欄を離れるとき(onInputStop)と
  // 拡張が終了するとき(onDestroy)に呼ぶ。デバウンス待ちのまま消える経路を
  // 塞ぐのが目的なので、ここを外すと上のコメントの壊れ方に戻る。
  flushPendingSaves(): void {
    clearTimeout(this.learningSaveTimer);
    clearTimeout(this.nextWordSaveTimer);
    clearTimeout(this.unknownWordSaveTimer);
    clearTimeout(this.suppressedSaveTimer);
    this.writeLearning();
    this.writeNextWord();
    this.writeUnknownWords();
    this.writeSuppressed();
  }

  // Re-read the deletion list from disk. The main app's 削除した候補 screen is a
  // different process, so restores made there are invisible here until this
  // runs -- called on every onInputStart, the same refresh point the user
  // dictionary and settings use.
  private reloadSuppressed(): void {
    if (!this.imeContext) { return; }
    SuppressedCandidates.load(this.imeContext, true)
      .then((data: Record<string, string[]>) => {
        SuppressedCandidates.setSuppressed(data);
      })
      .catch((_e: Error) => {});
  }

  // The reading the visible candidates were produced from: the composing text
  // clipped to the conversion range (see splitAtConversionEnd). Shared by
  // updateCandidates and suppressCandidate so a deletion is always keyed on
  // exactly the reading the deleted candidate was offered for.
  private conversionTarget(): string {
    const composing = AppStorage.get<string>('composingText') ?? '';
    const rangeEnd = this.conversionEnd > 0 ? this.conversionEnd : composing.length;
    return composing.slice(0, rangeEnd);
  }

  // Long-press → 削除 on a candidate. Stops that surface being offered for this
  // reading again, and erases the learned records behind it so neither the
  // conversion-learning boost nor unknown-word learning can bring it straight
  // back. Bundled dictionaries are never modified -- see SuppressedCandidates.
  // Returns the deleted surface (for the confirmation toast), or '' if the
  // deletion was refused (e.g. the as-typed kana, which must stay committable).
  suppressCandidate(index: number): string {
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    if (index < 0 || index >= candidates.length) { return ''; }
    const surface = candidates[index];
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    const bunsetsu = state === InputState.BUNSETSU;
    const reading = bunsetsu
      ? (this.bCur < this.bSegs.length ? this.bSegs[this.bCur] : '')
      : this.conversionTarget();
    if (reading.length === 0 || surface.length === 0) { return ''; }
    if (!SuppressedCandidates.suppress(reading, surface)) { return ''; }
    InputLog.recordDeleteCandidate(reading, surface, index, candidates.length); // [DEBUG-LOG]
    KanaKanjiConverter.forgetChoice(reading, surface);
    UnknownWordLearner.forget(reading, surface);
    // 自分で登録した語を消した場合は登録からも外す (両方の一覧の辻褄を合わせる)。
    this.unregisterIfUserWord(reading, surface);
    this.saveSuppressed();
    this.saveLearning();
    this.saveUnknownWords();
    // Rebuild what's on screen so the chip disappears immediately.
    if (bunsetsu) {
      // The segment's chosen surface is held separately from the candidate
      // list (autoConvert, not lookup), so deleting the surface it currently
      // shows would otherwise leave the deleted text in the 文節 display and
      // commit it. Fall back to the best surviving candidate.
      if (this.bChosen[this.bCur] === surface) {
        const left = SuppressedCandidates.filter(reading, this.kanjiConverter.lookup(reading));
        this.bChosen[this.bCur] = left.length > 0 ? left[0] : reading;
      }
      this.updateBunsetsuStorage();
    } else {
      AppStorage.setOrCreate('selectedCandidateIndex', 0);
      this.updateCandidates();
    }
    return surface;
  }

  // "Can the converter already produce this surface for this reading?" -- the
  // test that makes a hand-assembled word count as UNKNOWN (see
  // UnknownWordLearner). Checks the live candidate list rather than the raw
  // dictionaries so a word reachable through any current path (dict.json,
  // mozc, the user dictionary, an earlier unknown-word learn) is never
  // re-learned as if it were missing.
  private isKnownConversion(reading: string, surface: string): boolean {
    if (UnknownWordLearner.candidates(reading).indexOf(surface) >= 0) { return true; }
    if (this.kanjiConverter.lookup(reading).indexOf(surface) >= 0) { return true; }
    // lookup() only answers "is this whole reading a dictionary entry". The
    // converter also reaches compounds by segmenting and auto-converting each
    // segment (the multi-segment branch of updateCandidates), and a word THAT
    // route already produces isn't missing either -- without this check every
    // ordinary kanji compound typed in two commits (会社→見学) would look like
    // an unknown word and crowd out the genuinely unreachable ones.
    const segs = this.kanjiConverter.segment(reading);
    if (segs.length <= 1) { return false; }
    let joined = '';
    for (let i = 0; i < segs.length; i++) {
      joined += this.kanjiConverter.autoConvert(segs[i], segs[i + 1], segs[i - 1]);
    }
    return joined === surface;
  }

  // Feed one committed conversion to the unknown-word learner, then persist if
  // it changed anything. Called from the ordinary commit paths only -- bunsetsu
  // editing and raw-kana commits close the run instead (see endUnknownWordRun).
  private observeUnknownWord(reading: string, surface: string): void {
    // タップされた表記が、確定直前に候補一覧で「準候補」として見えていたか。
    // observe() は既存の run に積むだけで判定を変えてしまうので、その前に
    // AppStorage の表示済みスナップショットを見る。単体タップは run 経由では
    // 絶対にカウントされない (flush の assembled 判定を満たさない) ので、
    // confirmQuasi で直接1つ進める -- これが「押されたら昇進」の実体。
    const quasi = AppStorage.get<string[]>('quasiCandidateSurfaces') ?? [];
    if (quasi.includes(surface)) {
      InputLog.recordQuasiPick(reading, surface); // [DEBUG-LOG]
      UnknownWordLearner.confirmQuasi(reading, surface);
    }
    UnknownWordLearner.observe(reading, surface,
      (r: string, s: string): boolean => this.isKnownConversion(r, s));
    this.saveUnknownWords();
  }

  private endUnknownWordRun(): void {
    UnknownWordLearner.endRun((r: string, s: string): boolean => this.isKnownConversion(r, s));
    this.saveUnknownWords();
  }

  // The individual words a commit consists of, newest-relevant last: every 文節
  // surface when a multi-segment sentence was committed (recovered from the same
  // alignment learnCommit uses), otherwise the whole text as one word. Splitting
  // a committed sentence into its words is what lets next-word learning pick up
  // the sentence-internal flow (映画→を→見る), not just the final word.
  private committedWords(text: string): string[] {
    const a = this.lastAlignment;
    if (a !== undefined && text.length > a.prefixText.length && text.startsWith(a.prefixText)) {
      const words = a.prefixSurfaces.slice();
      words.push(text.slice(a.prefixText.length));
      return words.filter((w: string) => w.length > 0);
    }
    return text.length > 0 ? [text] : [];
  }

  // Learn this commit's word transitions with a rolling 2-word context, then
  // publish the next-word strip. `newWords` are the words just committed (a
  // whole sentence contributes each of its 文節). Called on every commit
  // (conversion or tapped prediction); the strip stays visible in IDLE until a
  // new composition starts (which clears it -- see updateCandidates).
  private pushPredictions(newWords: string[]): void {
    let w1 = this.recentWords.length >= 2 ? this.recentWords[this.recentWords.length - 2] : '';
    let w2 = this.recentWords.length >= 1 ? this.recentWords[this.recentWords.length - 1] : '';
    for (const w of newWords) {
      if (w.length === 0) { continue; }
      // A word with nothing before it, or one right after a sentence-ending
      // word, begins a sentence -- learn it as a habitual opener rather than
      // recording a cross-sentence bigram (which would just be junk context).
      if (w2.length === 0 || NextWordPredictor.isSentenceEnd(w2)) {
        NextWordPredictor.recordOpener(w);
      } else {
        NextWordPredictor.record(w1, w2, w); // (prev2, prev1) -> w
      }
      w1 = w2;
      w2 = w;
    }
    this.saveNextWord();
    this.recentWords = [];
    if (w1.length > 0) { this.recentWords.push(w1); }
    if (w2.length > 0) { this.recentWords.push(w2); }
    // Strip, in priority order: a personal habitual phrase (口癖/定型文, e.g. a
    // recurring sign-off 了解しました！ or a favorite filler like マジで) as ONE
    // multi-word chip when the user has repeated it enough to be a clear habit
    // (see NextWordPredictor.phraseCompletion) -- one tap instead of one per
    // word; then emoji for the last word; then ordinary single-word next-word
    // predictions. predictionWordGroups is kept parallel to the displayed strip
    // so commitPrediction can replay a multi-word chip's OWN words through
    // pushPredictions (correct learning bookkeeping) rather than treating the
    // whole concatenated phrase as a single "word".
    const strip: string[] = [];
    const wordGroups: string[][] = [];
    const pushChip = (text: string, words: string[]): void => {
      if (text.length > 0 && strip.indexOf(text) < 0 && strip.length < 6) {
        strip.push(text);
        wordGroups.push(words);
      }
    };
    if (NextWordPredictor.isSentenceEnd(w2)) {
      // Just finished a sentence: offer this user's habitual next-sentence
      // openers instead of continuations of the punctuation-tailed word (which
      // has none). Keeps the strip useful across sentence boundaries.
      for (const w of NextWordPredictor.openers()) { pushChip(w, [w]); }
    } else if (w2.length > 0) {
      const phrase = NextWordPredictor.phraseCompletion(w2, w1);
      if (phrase.length >= 2) { pushChip(phrase.join(''), phrase); }
      for (const e of EmojiSuggest.forSurface(w2)) { pushChip(e, [e]); }
      for (const w of NextWordPredictor.predict(w2, w1)) { pushChip(w, [w]); }
    }
    AppStorage.setOrCreate('predictions', strip);
    this.predictionWordGroups = wordGroups;
  }

  // In casual JP chat "。" is rarely typed; sentences/clauses are broken with a
  // 全角スペース, a newline, or by sending (Enter). Treat those the same way a
  // sentence-ending mark is treated in pushPredictions: drop the running word
  // context so the NEXT commit is learned as a fresh opener (口癖 の書き出し)
  // rather than chained across the break, and surface this user's habitual
  // openers right now.
  private markSentenceBoundary(): void {
    this.recentWords = [];
    // A finished sentence also finishes whatever word was being assembled.
    this.endUnknownWordRun();
    const openers = NextWordPredictor.openers();
    AppStorage.setOrCreate('predictions', openers);
    this.predictionWordGroups = openers.map((w: string): string[] => [w]);
  }

  // Reorder conversion candidates so any the user has actually written after the
  // current recent-word context lead. General homophone disambiguation from real
  // usage (the learned next-word bigram), the scalable counterpart to the
  // hand-curated CONTEXT_HINTS table: it needs no per-word entries and covers
  // whatever vocabulary this user writes. Stable: matched candidates keep their
  // learned order, everything else keeps its original order.
  private applyContextRerank(candidates: string[]): string[] {
    if (candidates.length < 2 || this.recentWords.length === 0) { return candidates; }
    const prev1 = this.recentWords[this.recentWords.length - 1];
    const prev2 = this.recentWords.length >= 2 ? this.recentWords[this.recentWords.length - 2] : undefined;
    const learned = NextWordPredictor.learnedNext(prev1, prev2);
    if (learned.length === 0) { return candidates; }
    const boosted: string[] = [];
    for (const s of learned) {
      if (candidates.indexOf(s) >= 0 && boosted.indexOf(s) < 0) { boosted.push(s); }
    }
    if (boosted.length === 0) { return candidates; }
    const rest = candidates.filter((c: string) => boosted.indexOf(c) < 0);
    return [...boosted, ...rest];
  }

  // Commit a tapped next-word prediction (a plain word, an emoji, or a
  // multi-word habitual-phrase chip). Nothing is composing, so this inserts
  // the chip's text directly, then replays its OWN word(s) through
  // pushPredictions -- for a phrase chip that both correctly learns each
  // internal transition (reinforcing the habit further) and re-predicts from
  // its true last word, so predictions keep chaining naturally.
  commitPrediction(index: number): void {
    const preds = AppStorage.get<string[]>('predictions') ?? [];
    if (index < 0 || index >= preds.length) { return; }
    const text = preds[index];
    if (text.length === 0) { return; }
    this.insertText(text, { raw: true } as InsertTextOptions);
    KanaKanjiConverter.addContext(text);
    const words = index < this.predictionWordGroups.length && this.predictionWordGroups[index].length > 0
      ? this.predictionWordGroups[index]
      : [text];
    this.pushPredictions(words);
  }

  onInputStart(
    kbCtrl: inputMethodEngine.KeyboardController,
    client: inputMethodEngine.InputClient
  ): void {
    this.kbController = kbCtrl;
    this.inputClient = client;
    // [DEBUG-LOG] Collection is paused until this field's attributes arrive, so
    // a password field is never logged even for the few ms before the async
    // answer lands.
    InputLog.beginField(); // [DEBUG-LOG]
    // 入力中のかなを、キーボード内ではなくホストアプリの入力欄に直接
    // 下線付きで出せるか (setPreviewTextSync)。対応は入力欄ごとに違い、
    // 非対応の欄で呼ぶと 12800011 で失敗するので、必ずここで確認してから使う。
    // 対応していればパネル内の composing 表示を畳んで、その分キーボードを
    // 低くできる (publishPreviewMode)。
    this.previewSupported = false;
    this.publishPreviewMode();
    client.getEditorAttribute()
      .then((attr: inputMethodEngine.EditorAttribute) => {
        this.previewSupported = attr.isTextPreviewSupported === true;
        this.publishPreviewMode();
        InputLog.setFieldPattern(attr.inputPattern); // [DEBUG-LOG]
      })
      .catch((_e: Error) => {
        this.previewSupported = false;
        this.publishPreviewMode();
        InputLog.setFieldPattern(0); // [DEBUG-LOG]
      });
    this.converter.reset();
    this.reloadUserDict();
    this.reloadSettings();
    this.reloadSuppressed();
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    this.insertedBuffer = [];
    this.composingUndoStack = [];
    // 新しい入力欄 = 別のドキュメント/別のアプリの可能性があるので、hostCursor
    // が指す座標系ごと無効になる。持ち越すと別の場所を編集しかねない。
    this.hostUndoStack = [];
    this.hostCursor = 0;
    this.pendingBracketClose = '';
    this.conversionEnd = 0;
    AppStorage.setOrCreate('convEnd', 0);
    if (!AppStorage.has('inputMode')) {
      AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
    }
    this.refreshClipboardPreview();
  }

  onInputStop(): void {
    InputLog.beginField(); // [DEBUG-LOG] flushes, then pauses until the next field is known
    // 欄を離れる前にプレビューを畳む (inputClient を捨てた後では解除できない)。
    this.cancelPreviewText();
    this.previewSupported = false;
    this.publishPreviewMode();
    this.kbController = undefined;
    this.inputClient = undefined;
    this.converter.reset();
    this.insertedBuffer = [];
    this.composingUndoStack = [];
    this.hostUndoStack = [];
    this.hostCursor = 0;
    this.pendingBracketClose = '';
    this.conversionEnd = 0;
    this.composingWatermark = '';
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('predictions', [] as string[]);
    this.recentWords = [];
    this.predictionWordGroups = [];
    // Leaving the field: drop the recent-context buffer so homophone ranking in
    // the next app/text box doesn't inherit this one's context.
    KanaKanjiConverter.clearContext();
    this.endUnknownWordRun();
    // 入力欄を離れた = この拡張プロセスがこの先落とされうる。デバウンス待ちの
    // 保存をここで確定させないと、タイマーごと消えて一度も書かれない
    // (flushPendingSaves のコメント参照)。
    this.flushPendingSaves();
    AppStorage.setOrCreate('inputState', InputState.IDLE);
    AppStorage.setOrCreate('convEnd', 0);
  }

  handleKeyPress(key: string): void {
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;

    if (mode === InputMode.ALPHANUMERIC) {
      this.commitPending();
      this.insertText(key);
      return;
    }

    if (state === InputState.SELECTING) {
      // New key → commit top candidate first, then start new composition
      this.commitTopCandidate();
    }

    const result = this.converter.processKey(key);

    if (result.committed.length > 0) {
      const kana = mode === InputMode.KATAKANA
        ? toKatakana(result.committed)
        : result.committed;
      const current = AppStorage.get<string>('composingText') ?? '';
      AppStorage.setOrCreate('composingText', current + kana);
      this.updateCandidates();
    }

    AppStorage.setOrCreate('pendingRomaji', result.pending);

    const composing = AppStorage.get<string>('composingText') ?? '';
    const pending = result.pending;
    if (composing.length > 0 || pending.length > 0) {
      AppStorage.setOrCreate('inputState', InputState.COMPOSING);
    } else {
      AppStorage.setOrCreate('inputState', InputState.IDLE);
    }
  }

  handleSpaceKey(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    let composing = AppStorage.get<string>('composingText') ?? '';

    if (state === InputState.IDLE || composing.length === 0) {
      const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
      if (mode === InputMode.ALPHANUMERIC) {
        this.insertText(' ');
      } else {
        // A 全角スペース in JP mode is a chat clause break -> sentence boundary.
        this.insertText('　');
        this.markSentenceBoundary();
      }
      return;
    }

    if (state === InputState.COMPOSING) {
      // Flush any pending romaji first
      const pending = this.converter.flushPending();
      const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
      if (pending.length > 0) {
        const kana = mode === InputMode.KATAKANA ? toKatakana(pending) : pending;
        composing = composing + kana;
        AppStorage.setOrCreate('composingText', composing);
        AppStorage.setOrCreate('pendingRomaji', '');
      }
      const candidates = this.kanjiConverter.lookup(composing);
      AppStorage.setOrCreate('candidates', candidates);
      AppStorage.setOrCreate('selectedCandidateIndex', 0);
      AppStorage.setOrCreate('inputState', InputState.SELECTING);
      return;
    }

    if (state === InputState.SELECTING) {
      const candidates = AppStorage.get<string[]>('candidates') ?? [];
      let idx = (AppStorage.get<number>('selectedCandidateIndex') ?? 0) + 1;
      if (idx >= candidates.length) { idx = 0; }
      AppStorage.setOrCreate('selectedCandidateIndex', idx);
    }
  }

  handleBackspace(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;

    if (state === InputState.IDLE) {
      // 自由入力中はパネル内の欄から1文字消す (insertText と対になる出口)。
      if (this.captureTarget.length > 0) {
        this.backspaceCaptured();
        return;
      }
      // 消す文字は「直前に自分が打ち込んだ文字」ではなく「今カーソルの
      // 直前に実際にある文字」を読む。矢印キーでカーソルを動かした後の
      // backspace は別の文字を消すので、insertedBuffer.pop() だけに
      // 頼ると取消キーへ誤った文字を記録してしまう (今回の修正対象)。
      // getBackwardSync が使えない/失敗する欄向けに従来の推測へ落とす。
      let deleted = '';
      try {
        deleted = this.inputClient?.getBackwardSync(1) ?? '';
      } catch (_e) {
        deleted = '';
      }
      if (deleted.length === 0) { deleted = this.insertedBuffer.pop() ?? ''; }
      else { this.insertedBuffer.pop(); }
      if (deleted.length > 0) { this.pushHostOp('delete', deleted); }
      // 括弧を開いた直後に取り消された等、何かを消したら保留中の自動閉じは
      // 前提が崩れているので破棄する (賢く追おうとはしない)。
      this.pendingBracketClose = '';
      this.inputClient?.deleteForward(1);
      // 直前の確定 (熟語など) をバックスペースで削っていく間、漢字の手がかりが
      // 残っている限り truncate() で末尾を追う (かける→翔ける→⌫⌫→翔 のような、
      // 熟語や活用語尾の一部だけを残すケースを検出するため)。全部ひらがな
      // (生のかな確定・助詞など、対応が保証できない) まで削り込んだら
      // truncate() 自身が false を返すので、そこから先は以前と同じ
      // abandonRun() で run ごと捨てる (「〜して」のバグの再発防止 --
      // UnknownWordLearner.truncate のコメント参照)。
      if (!UnknownWordLearner.truncate()) {
        UnknownWordLearner.abandonRun();
      }
      // The committed word the next-word strip was keyed on is being edited
      // away -- retire the strip so a now-stale prediction can't be tapped.
      if (this.recentWords.length > 0) {
        this.recentWords = [];
        this.predictionWordGroups = [];
        AppStorage.setOrCreate('predictions', [] as string[]);
      }
      return;
    }

    if (state === InputState.BUNSETSU) {
      // Exit bunsetsu, restore composing text
      const composing = this.bSegs.join('');
      this.bSegs = [];
      this.bChosen = [];
      this.bCur = 0;
      AppStorage.setOrCreate('bunsetsuTexts', [] as string[]);
      AppStorage.setOrCreate('bunsetsuRaw', [] as string[]);
      AppStorage.setOrCreate('bunsetsuDisplay', '');
      AppStorage.setOrCreate('bunsetsuCurrent', 0);
      AppStorage.setOrCreate('composingText', composing);
      AppStorage.setOrCreate('inputState', InputState.COMPOSING);
      this.updateCandidates();
      return;
    }

    if (state === InputState.SELECTING) {
      AppStorage.setOrCreate('candidates', [] as string[]);
      AppStorage.setOrCreate('inputState', InputState.COMPOSING);
      return;
    }

    if (state === InputState.COMPOSING) {
      const pending = AppStorage.get<string>('pendingRomaji') ?? '';
      if (pending.length > 0) {
        this.converter.backspace();
        AppStorage.setOrCreate('pendingRomaji', pending.slice(0, -1));
      } else {
        const composing = AppStorage.get<string>('composingText') ?? '';
        if (composing.length > 0) {
          const ch = composing.slice(-1);
          this.composingUndoStack.push(ch);
          InputLog.recordDeleteChar(ch, InputState.COMPOSING); // [DEBUG-LOG]
          AppStorage.setOrCreate('composingText', composing.slice(0, -1));
        }
      }

      const composing = AppStorage.get<string>('composingText') ?? '';
      const newPending = AppStorage.get<string>('pendingRomaji') ?? '';
      if (composing.length === 0 && newPending.length === 0) {
        AppStorage.setOrCreate('inputState', InputState.IDLE);
      }
      this.updateCandidates();
    }
  }

  handleEnterKey(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.BUNSETSU) {
      this.commitBunsetsu();
    } else if (state === InputState.SELECTING) {
      this.commitTopCandidate();
    } else if (state === InputState.COMPOSING) {
      this.commitRaw();
    } else {
      this.inputClient?.getEditorAttribute().then((attr: inputMethodEngine.EditorAttribute) => {
        this.inputClient?.sendKeyFunction(attr.enterKeyType);
      }).catch((_e: Error) => {
        this.inputClient?.sendKeyFunction(0);
      });
      // Enter in an idle field sends the message (or inserts a newline): either
      // way the current sentence is finished, so reset context and offer the
      // next-message openers.
      this.markSentenceBoundary();
    }
  }

  commitRaw(): void {
    const composing = AppStorage.get<string>('composingText') ?? '';
    const pending = this.converter.flushPending();
    const all = composing + pending;
    if (all.length > 0) { this.insertText(all); }
    InputLog.recordRaw(composing, all); // [DEBUG-LOG]
    // Committing as raw kana is not a conversion, so it closes any word the
    // user was assembling rather than extending it.
    this.endUnknownWordRun();
    this.resetComposition();
  }

  // When the user has shrunk the conversion range (cursor-left: conversionEnd
  // set to a point before the end of the composing text), only that prefix was
  // converted into `candidates`; everything after it stays as typed kana.
  // Returns [convertedReading, kanaTail] so a commit learns the correct
  // reading→surface (the prefix only) and knows what is left to keep composing
  // (see continueWithTail). With no range adjustment the tail is empty and the
  // reading is the whole composing text -- identical to before.
  private splitAtConversionEnd(composing: string): [string, string] {
    const end = (this.conversionEnd > 0 && this.conversionEnd < composing.length)
      ? this.conversionEnd : composing.length;
    return [composing.slice(0, end), composing.slice(end)];
  }

  commitCandidate(index: number): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.BUNSETSU) {
      this.commitBunsetsuCandidate(index);
      return;
    }
    const composing = AppStorage.get<string>('composingText') ?? '';
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    const text = index < candidates.length ? candidates[index] : '';
    if (text.length > 0) {
      const parts = this.splitAtConversionEnd(composing);
      const reading = parts[0];
      const tail = parts[1];
      // A predictive completion (会社 committed from the prefix かいし) must NOT
      // feed conversion learning: its reading is longer than what was typed, so
      // recordChoice(かいし→会社) would teach a wrong reading. Skip the learn;
      // completion personalisation instead flows from full-word commits (typing
      // かいしゃ→会社 correctly teaches かいしゃ, which then completes かいし).
      if (!this.isNonLearningCandidate(reading, text)) {
        this.learnCommit(reading, text);
        this.saveLearning();
        this.observeUnknownWord(reading, text);
      }
      InputLog.recordCommit(reading, text, index, candidates.length, candidates); // [DEBUG-LOG]
      this.insertText(text);
      KanaKanjiConverter.addContext(text);
      const words = this.committedWords(text);
      // 残りがあるなら、それはまだ変換していない入力。確定させずに composing に
      // 戻して続けて変換できるようにする (continueWithTail のコメント参照)。
      if (tail.length > 0) {
        this.pushPredictions(words);
        this.continueWithTail(tail);
        return;
      }
      this.resetComposition();
      this.pushPredictions(words);
      return;
    }
    this.resetComposition();
  }

  // True when `text` is an ephemeral suggestion offered for the composing
  // prefix -- a predictive completion (reading longer than typed) or a live
  // date/time value -- and so must bypass reading→surface conversion learning
  // (かいし→会社 or きょう→"2026年7月23日" would both be wrong to learn).
  private isNonLearningCandidate(composing: string, text: string): boolean {
    if (PredictiveConversion.predict(composing, KanaKanjiConverter.getLearned(),
        KanaKanjiConverter.prefixCompletions(composing, PREDICT_DICT_HITS)).indexOf(text) >= 0) {
      return true;
    }
    if (DateTimePredictor.predict(composing, new Date()).indexOf(text) >= 0) {
      return true;
    }
    return NumberFormatter.predict(composing).indexOf(text) >= 0;
  }

  // Learn from a committed candidate. For a multi-segment sentence whose
  // committed surface still begins with the auto-converted prefix captured in
  // updateCandidates, peel that prefix off to recover the accepted final-
  // segment surface, then learn every 文節 individually -- so correcting one
  // homophone (しゃしんをとった→写真を撮った) teaches とった→撮った for the
  // next sentence too, the way every mature IME's learning generalizes.
  // Anything else (single segment, symbol prefix, a predictive/alt-segment
  // pick whose surface no longer starts with the prefix) falls back to the
  // plain whole reading→surface record.
  // Longest whole reading still recorded verbatim by learnCommit. Long enough
  // for the names, set phrases and stock sentences people actually retype;
  // past that a reading is a one-off sentence that would only burn a slot in
  // the learning store (and turn into noisy predictive completions, since
  // PredictiveConversion completes straight out of that store).
  private static readonly MAX_WHOLE_LEARN_LEN = 12;

  private learnCommit(composing: string, text: string): void {
    const a = this.lastAlignment;
    if (a !== undefined && text.length > a.prefixText.length && text.startsWith(a.prefixText)) {
      const lastSurface = text.slice(a.prefixText.length);
      const surfaces = a.prefixSurfaces.slice();
      surfaces.push(lastSurface);
      KanaKanjiConverter.recordSegmentedChoice(a.segs, surfaces);
      // ...and the whole reading too. Per-segment records are what make a
      // correction generalize (とった→撮った carries to the next sentence), but
      // they are keyed on the SEGMENTS while the candidate list for a
      // multi-segment reading is reordered by applyLearning under the WHOLE
      // reading -- so picking 写真を取った for しゃしんをとった recorded
      // しゃしん/とった and left しゃしんをとった itself unlearned. Re-typing the
      // exact same phrase therefore never promoted the choice, no matter how
      // many times it was made: the one case a user most expects to stick.
      if (composing.length <= InputHandler.MAX_WHOLE_LEARN_LEN) {
        KanaKanjiConverter.recordChoice(composing, text);
      }
    } else {
      KanaKanjiConverter.recordChoice(composing, text);
    }
  }

  commitTopCandidate(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.BUNSETSU) {
      this.commitBunsetsu();
      return;
    }
    const composing = AppStorage.get<string>('composingText') ?? '';
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    const idx = AppStorage.get<number>('selectedCandidateIndex') ?? 0;
    if (candidates.length > 0) {
      const chosen = candidates[idx];
      const parts = this.splitAtConversionEnd(composing);
      const reading = parts[0];
      const tail = parts[1];
      if (!this.isNonLearningCandidate(reading, chosen)) {
        this.learnCommit(reading, chosen);
        this.saveLearning();
        this.observeUnknownWord(reading, chosen);
      }
      InputLog.recordCommit(reading, chosen, idx, candidates.length, candidates); // [DEBUG-LOG]
      this.insertText(chosen);
      KanaKanjiConverter.addContext(chosen);
      const words = this.committedWords(chosen);
      if (tail.length > 0) {
        this.pushPredictions(words);
        this.continueWithTail(tail);
        return;
      }
      this.resetComposition();
      this.pushPredictions(words);
      return;
    }
    this.commitPending();
  }

  private commitPending(): void {
    const composing = AppStorage.get<string>('composingText') ?? '';
    const pending = this.converter.flushPending();
    const all = composing + pending;
    if (all.length > 0) { this.insertText(all); }
    this.resetComposition();
  }

  // 変換範囲を縮めて確定したときの「残り」を、続けて変換できる状態にする。
  //
  // 「かくていされる」を「かくてい」までで変換して確定したとき、残りの「される」
  // はまだ変換していない入力であって、確定した文字列ではない。それを
  // insertText(text + tail) で一緒に送り出していたので、
  //   ・画面の変換保留欄には「される」が残って見える
  //   ・しかし実際にはかなのまま確定済みで、もう変換できない
  // という食い違いが起きていた。文節ごとに変換していく操作そのものが
  // 成立していない状態で、範囲を縮める機能の存在意義が無くなっていた。
  //
  // 確定するのは変換した部分だけにして、残りは composing に戻す。
  // resetComposition と違って composingText を空にせず、変換範囲も残りの
  // 長さに張り直してから候補を出し直す。
  private continueWithTail(tail: string): void {
    this.converter.reset();
    this.bSegs = [];
    this.bChosen = [];
    this.bCur = 0;
    this.composingUndoStack = [];
    this.conversionEnd = tail.length;
    AppStorage.setOrCreate('composingText', tail);
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('bunsetsuTexts', [] as string[]);
    AppStorage.setOrCreate('bunsetsuRaw', [] as string[]);
    AppStorage.setOrCreate('bunsetsuDisplay', '');
    AppStorage.setOrCreate('bunsetsuCurrent', 0);
    AppStorage.setOrCreate('inputState', InputState.COMPOSING);
    AppStorage.setOrCreate('convEnd', this.conversionEnd);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    this.updateCandidates();
  }

  private resetComposition(): void {
    // 入力欄に残っているプレビューを必ず消す。insertText を経ない経路
    // (取消・欄の切り替えなど) でもここを通るので、消し忘れの受け皿になる。
    this.cancelPreviewText();
    this.converter.reset();
    this.bSegs = [];
    this.bChosen = [];
    this.bCur = 0;
    // NOTE: insertedBuffer is deliberately NOT cleared here. It is a rolling
    // log of characters actually inserted into the field (capped at 50), used
    // by the IDLE backspace as a fallback when getBackwardSync can't read the
    // field. resetComposition runs after every commit, so clearing it here
    // threw away the just-committed word's characters -- backspacing a
    // committed word then had no fallback available. It is cleared only on
    // field start/stop (onInputStart / onInputStop), which is the correct
    // scope for it.
    //
    // composingUndoStack (この回のCOMPOSING中backspace履歴) はここで空にする
    // -- 確定したらその読みの組み立て直しは終わりなので。hostUndoStack
    // (確定済みホストテキストの履歴) はここでは触らない。別の対象なので
    // commit のたびに消す理由が無い。
    this.composingUndoStack = [];
    this.conversionEnd = 0;
    this.composingWatermark = '';
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('bunsetsuTexts', [] as string[]);
    AppStorage.setOrCreate('bunsetsuRaw', [] as string[]);
    AppStorage.setOrCreate('bunsetsuDisplay', '');
    AppStorage.setOrCreate('bunsetsuCurrent', 0);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
    AppStorage.setOrCreate('convEnd', 0);
    this.refreshClipboardPreview();
  }

  // Kept in-memory only (AppStorage), not persisted to disk — clipboard
  // contents can be sensitive, and this app's privacy stance is to keep data
  // on-device only for as long as actually needed. History resets when the
  // keyboard extension process restarts.
  private static readonly MAX_CLIPBOARD_HISTORY = 8;

  // Signature of the clipboard entry the user has already pasted from the
  // suggestion strip. Once pasted, the paste chip stays hidden for that exact
  // content (no more flicker on every refresh) until the system clipboard
  // actually changes to something else. Empty = nothing dismissed.
  private static dismissedClipSig: string = '';

  // Stable signature for a clipboard entry so a re-read can tell "same content
  // I already pasted" from "a new copy". Text/URI/raw-image are namespaced so
  // they can never collide.
  private static clipSig(text: string, uri: string, isImage: boolean): string {
    if (text.length > 0) { return 'T:' + text; }
    if (uri.length > 0) { return 'U:' + uri; }
    if (isImage) { return 'I:'; }
    return '';
  }

  private static setClipboardPreviewState(preview: string, isImage: boolean, isFile: boolean, uri: string): void {
    AppStorage.setOrCreate('clipboardPreview', preview);
    AppStorage.setOrCreate('clipboardIsImage', isImage);
    AppStorage.setOrCreate('clipboardIsFile', isFile);
    AppStorage.setOrCreate('clipboardUri', uri);
  }

  // Public re-read of the system clipboard, for the settings panel to call
  // when it (or its クリップボード履歴 view) opens -- refreshClipboardPreview
  // otherwise only runs on keyboard show (onInputStart) and after a commit
  // (resetComposition), so a copy made in the host app while the keyboard was
  // already up wasn't picked up until the keyboard was closed and reopened
  // (an AppGallery reviewer flagged exactly this staleness). Reading the
  // pasteboard on this deliberate user action is expected and privacy-safe.
  refreshClipboard(): void {
    this.refreshClipboardPreview();
  }

  // 実機の SELinux ログで原因を確定済み:
  //
  //   avc: denied { get } for service=3701
  //     scontext=u:r:input_isolate_debug_hap:s0
  //     tcontext=u:object_r:sa_pasteboard_service:s0  permissive=0
  //   PasteboardClient# proxyService is null
  //
  // 入力方式拡張の隔離ドメイン (input_isolate_debug_hap) から
  // PasteboardService への接続そのものが SELinux で恒久的に拒否されている。
  // 今日判明した振動 (sa_miscdevice_service) の拒否と同じ形の制限で、
  // コード側のバグではなく直せない。setData (exportInputLog 参照) と
  // getData (このメソッド) はどちらも同じ経路を通るので、書き込みが
  // "async call failed" で落ちるのと同じ理由で、読み取りも常に失敗して
  // 静かに空へフォールバックしている -- 「クリップボード検出」チップが
  // 最近ずっと出ないのは、機能が壊れたのではなく、この隔離ドメインからは
  // そもそも一度も届いたことがなかった可能性が高い。
  //
  // OS がこの制限を緩めれば動くようになるので、機構はそのまま残す
  // (振動の markHapticUnavailable と同じ方針)。
  private refreshClipboardPreview(): void {
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      if (!data || data.getRecordCount() === 0) {
        InputHandler.setClipboardPreviewState('', false, false, '');
        return;
      }
      const isImage = data.hasType(pasteboard.MIMETYPE_PIXELMAP);
      const text = data.getPrimaryText();
      if (text && text.length > 0) {
        // Already pasted this exact content once -> keep the chip hidden.
        if (InputHandler.clipSig(text, '', false) === InputHandler.dismissedClipSig) {
          InputHandler.setClipboardPreviewState('', false, false, '');
          return;
        }
        // Different content than what was last pasted -> the dismissal is spent.
        InputHandler.dismissedClipSig = '';
        InputHandler.setClipboardPreviewState(text, false, false, '');
        this.recordClipboardHistory(text);
        return;
      }
      // A file (from Files/a Gallery share sheet) shows up as a URI record.
      // A directly-copied image often carries BOTH a pixelmap record and a
      // URI record (many apps populate both), so check for a URI regardless
      // of isImage. Preview it as a filename rather than the raw URI.
      const uri = data.getPrimaryUri();
      if (uri && uri.length > 0) {
        if (InputHandler.clipSig('', uri, isImage) === InputHandler.dismissedClipSig) {
          InputHandler.setClipboardPreviewState('', false, false, '');
          return;
        }
        InputHandler.dismissedClipSig = '';
        const preview = isImage ? '画像' : InputHandler.formatFileClipPreview(uri);
        InputHandler.setClipboardPreviewState(preview, isImage, true, uri);
        return;
      }
      if (isImage) {
        // Raw pixels only, no URI to point at (e.g. some apps' plain
        // "コピー" on an image) -- pasteClipboard() still works fine here
        // since sendPasteExtendAction doesn't need the URI, just the
        // isImage/isFile flag; only the filename preview text is degraded.
        if (InputHandler.clipSig('', '', true) === InputHandler.dismissedClipSig) {
          InputHandler.setClipboardPreviewState('', false, false, '');
          return;
        }
        InputHandler.dismissedClipSig = '';
        InputHandler.setClipboardPreviewState('画像', true, false, '');
        return;
      }
      InputHandler.setClipboardPreviewState('', false, false, '');
    }).catch((err: Error) => {
      console.error('shuntiIME refreshClipboardPreview error', JSON.stringify(err));
      InputHandler.setClipboardPreviewState('', false, false, '');
    });
  }

  // "国税庁_請求書テンプレート2026.pdf" -> "国税庁_請求書.pdf": first few
  // characters of the filename plus its extension, so the chip stays short
  // without losing the cue of what kind of file it is.
  private static formatFileClipPreview(uri: string): string {
    const clean = uri.split('?')[0].split('#')[0];
    const segments = clean.split('/');
    let rawName = segments[segments.length - 1] ?? '';
    try {
      rawName = decodeURIComponent(rawName);
    } catch {
      // Malformed percent-encoding -- fall back to the raw segment.
    }
    if (rawName.length === 0) { return 'ファイル'; }
    const dotIdx = rawName.lastIndexOf('.');
    const hasExt = dotIdx > 0 && dotIdx < rawName.length - 1;
    const base = hasExt ? rawName.slice(0, dotIdx) : rawName;
    const ext = hasExt ? rawName.slice(dotIdx + 1) : '';
    const truncatedBase = base.length > 8 ? base.slice(0, 8) : base;
    return hasExt ? `${truncatedBase}.${ext}` : truncatedBase;
  }

  private recordClipboardHistory(text: string): void {
    if (text.length === 0) { return; }
    const history = AppStorage.get<string[]>('clipboardHistory') ?? [];
    if (history[0] === text) { return; }
    const next = [text, ...history.filter((t: string) => t !== text)]
      .slice(0, InputHandler.MAX_CLIPBOARD_HISTORY);
    AppStorage.setOrCreate('clipboardHistory', next);
  }

  // No input method on any platform can inject non-text content into an
  // arbitrary third-party app's text field through the standard IME
  // text-commit API (insertText here) -- that's not a bug to fix in this
  // app, it's what every keyboard app is limited to.
  //
  // For image/file clipboard contents this instead asks the host app's OWN
  // focused field to run ITS native paste (sendPasteExtendAction below) --
  // that reads the same system pasteboard the field's own long-press
  // 貼り付け already uses, so any editor that supports pasting an image at
  // all picks it up through its own existing handling. An earlier attempt
  // used ArkUI drag-and-drop instead (dragging the clipboard chip onto the
  // focused field), but that turned out not to work in nearly any real app
  // -- most fields' drop targets don't accept a dragged UnifiedData record
  // the way they accept their own paste action, so this replaces it as the
  // primary mechanism rather than sitting alongside it as a "maybe" path.
  pasteClipboard(): 'text' | 'extendAction' | 'none' {
    const isImage = AppStorage.get<boolean>('clipboardIsImage') ?? false;
    const isFile = AppStorage.get<boolean>('clipboardIsFile') ?? false;
    if (isImage || isFile) {
      const uri = AppStorage.get<string>('clipboardUri') ?? '';
      if (this.sendPasteExtendAction()) {
        // Dismiss the chip for this file/image until the clipboard changes.
        InputHandler.dismissedClipSig = InputHandler.clipSig('', uri, isImage);
        InputHandler.setClipboardPreviewState('', false, false, '');
        return 'extendAction';
      }
      return 'none';
    }
    const text = AppStorage.get<string>('clipboardPreview') ?? '';
    if (text.length === 0) {
      return 'none';
    }
    this.insertText(text, { raw: true } as InsertTextOptions);
    // Hide the paste chip now that it's been used, and remember this content so
    // subsequent refreshes keep it hidden until the user copies something new.
    InputHandler.dismissedClipSig = InputHandler.clipSig(text, '', false);
    InputHandler.setClipboardPreviewState('', false, false, '');
    return 'text';
  }

  // Tells the currently-focused edit box to run its own native paste
  // operation (inputMethodEngine.ExtendAction.PASTE) instead of the IME
  // trying to supply the content itself. Fire-and-forget: sendExtendAction
  // resolves/rejects on whether the *request* was delivered, not on whether
  // the field actually had a paste handler for image/file content -- both
  // "field doesn't support pasting images" and "there's nothing to paste"
  // look the same from here, so the caller can only report that the request
  // was sent, not that it definitely worked.
  private sendPasteExtendAction(): boolean {
    if (!this.inputClient) { return false; }
    try {
      this.inputClient.sendExtendAction(inputMethodEngine.ExtendAction.PASTE)
        .catch((err: Error) => console.error('shuntiIME sendExtendAction(PASTE) error', JSON.stringify(err)));
      return true;
    } catch (e) {
      console.error('shuntiIME sendExtendAction(PASTE) threw', JSON.stringify(e));
      return false;
    }
  }

  // Paste an arbitrary entry from clipboard history (not necessarily the
  // current system clipboard contents).
  pasteFromHistory(index: number): void {
    const history = AppStorage.get<string[]>('clipboardHistory') ?? [];
    const text = history[index];
    if (text === undefined || text.length === 0) { return; }
    this.insertText(text, { raw: true } as InsertTextOptions);
  }

  clearClipboardHistory(): void {
    AppStorage.setOrCreate('clipboardHistory', [] as string[]);
  }

  // ホスト側(確定済み、IDLE状態)テキストへの1回の操作を記録する。
  // insertText() の末尾(挿入)と handleBackspace の IDLE 分岐(削除)から
  // 呼ばれる。at はその時点の hostCursor から自己完結で決まる (フィールド
  // コメント参照)。
  private pushHostOp(kind: 'insert' | 'delete', text: string): void {
    if (text.length === 0) { return; }
    if (kind === 'delete') {
      InputLog.recordDeleteChar(text, InputState.IDLE); // [DEBUG-LOG]
    }
    const at = kind === 'insert' ? this.hostCursor : this.hostCursor - text.length;
    this.hostUndoStack.push({ kind, text, at });
    if (this.hostUndoStack.length > InputHandler.MAX_HOST_UNDO) {
      this.hostUndoStack = this.hostUndoStack.slice(-InputHandler.MAX_HOST_UNDO);
    }
    this.hostCursor += kind === 'insert' ? text.length : -text.length;
  }

  // hostCursor を target まで動かす。1歩ずつ moveCursor の確定を待ってから
  // 次を出す -- insertText 直後に間を置かず moveCursor を出すと、ホスト側が
  // まだ編集を反映していない状態に対して移動が発行され無視される実機バグが
  // あった (コミット 39f4147)。取消キーはユーザーが最後の編集から間を置いて
  // 押す操作なのでこの経路そのものは起きないが、複数歩を連続で出すときの
  // 相互干渉を避けるため、ここでも律儀に1歩ずつ待つ。
  private async moveHostCursorTo(target: number): Promise<void> {
    const dir = target > this.hostCursor
      ? inputMethodEngine.Direction.CURSOR_RIGHT
      : inputMethodEngine.Direction.CURSOR_LEFT;
    const steps = Math.abs(target - this.hostCursor);
    for (let i = 0; i < steps; i++) {
      try {
        await this.inputClient?.moveCursor(dir);
      } catch (_e) {
        break; // 動かせなかった。これ以上ズレを広げずここで諦める。
      }
      this.hostCursor += dir === inputMethodEngine.Direction.CURSOR_RIGHT ? 1 : -1;
    }
  }

  // ホスト側テキストの直近の操作(挿入でも削除でも)を1件取り消す。本当の
  // ctrl+zと同じ順序 -- 挿入の取り消しは削除、削除の取り消しは打ち戻し。
  // 公開の insertText() ラッパーは使わない (それを呼ぶと今の取り消し自体が
  // 新しい操作として hostUndoStack に積まれてしまい、スタックが正しく
  // 縮まなくなる)。
  private async undoLastHostEdit(): Promise<void> {
    const op = this.hostUndoStack.pop();
    if (op === undefined) { return; }
    InputLog.recordUndo(op.text); // [DEBUG-LOG]
    if (op.kind === 'insert') {
      // 挿入の取り消し = その範囲を削除。挿入直後の位置までカーソルを
      // 動かしてから、その直前を deleteForward で削る。
      await this.moveHostCursorTo(op.at + op.text.length);
      try {
        await this.inputClient?.deleteForward(op.text.length);
        this.hostCursor -= op.text.length;
        for (let i = 0; i < op.text.length; i++) { this.insertedBuffer.pop(); }
      } catch (_e) { /* 欄が外れた等。ここで失敗しても入力は続けられる。 */ }
    } else {
      // 削除の取り消し = 元あった位置へ打ち戻す。
      await this.moveHostCursorTo(op.at);
      try {
        await this.inputClient?.insertText(op.text);
        this.hostCursor += op.text.length;
        for (const ch of op.text) { this.insertedBuffer.push(ch); }
      } catch (_e) { /* 同上。 */ }
    }
  }

  // 取消キー。COMPOSING(変換前のかな組み立て中)ならその場で1文字ずつ復元
  // する (このバッファは常に末尾でしか編集できないので位置のズレが起きない)。
  // IDLE(確定済みのホスト側テキスト)なら、直近の操作を実際に起きた位置まで
  // 戻ってから取り消す -- 挿入も削除も貼り付けも区別せず、本当のctrl+zと
  // 同じ順序で遡る。
  undoLastDeletion(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.IDLE) {
      this.undoLastHostEdit();
      return;
    }
    const ch = this.composingUndoStack.pop();
    if (ch === undefined || ch.length === 0) { return; }
    InputLog.recordUndo(ch); // [DEBUG-LOG]
    this.handleDirectKana(ch);
  }

  // Launches the main app (settings / user dictionary screen) from the
  // keyboard's own settings panel. InputMethodExtensionContext extends
  // ExtensionContext, which supports startAbility for abilities in the same
  // bundle.
  openMainApp(): void {
    if (!this.imeContext) { return; }
    const want: Want = {
      bundleName: 'com.shunti.japaneseime',
      abilityName: 'EntryAbility',
    };
    this.imeContext.startAbility(want)
      .catch((err: Error) => console.error('shuntiIME openMainApp error', JSON.stringify(err)));
  }

  // AppGallery's review deep link needs this app's AppGallery Connect app ID,
  // which only exists once it has been published there — until then this
  // stays empty and the caller should show a "not published yet" message
  // instead of firing a broken want.
  private static readonly APP_GALLERY_APP_ID = '';

  openAppGalleryReview(): boolean {
    const id = InputHandler.APP_GALLERY_APP_ID;
    if (id.length === 0 || !this.imeContext) { return false; }
    const want: Want = { uri: `store://appgallery.huawei.com/app/detail?id=${id}` };
    this.imeContext.startAbility(want)
      .catch((err: Error) => console.error('shuntiIME openAppGalleryReview error', JSON.stringify(err)));
    return true;
  }

  // Opens an arbitrary URL in the main app's own in-app browser
  // (pages/WebViewPage, an ArkWeb view) rather than handing off to the
  // system's "choose a browser" chooser -- routed through EntryAbility's
  // want parameters (see EntryAbility.ets/Index.ets) since a URL want here
  // would open the system browser chooser instead.
  openExternalUrl(url: string, title: string): boolean {
    if (!this.imeContext) { return false; }
    const want: Want = {
      bundleName: 'com.shunti.japaneseime',
      abilityName: 'EntryAbility',
      parameters: { openUrl: url, openTitle: title },
    };
    this.imeContext.startAbility(want)
      .catch((err: Error) => console.error('shuntiIME openExternalUrl error', JSON.stringify(err)));
    return true;
  }

  // Opens this project's GitHub repository (README, source code, etc).
  openGithubRepo(): boolean {
    return this.openExternalUrl(
      'https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next', 'GitHub');
  }

  // Hands a URL to the main app to raise the system share sheet on (see
  // EntryAbility's shareUrl param / Index.onPendingShareUrlChanged). Routed
  // through EntryAbility exactly like openExternalUrl -- the share sheet needs
  // a UIAbilityContext, which an input-method extension doesn't have.
  shareUrl(url: string): boolean {
    if (!this.imeContext) { return false; }
    const want: Want = {
      bundleName: 'com.shunti.japaneseime',
      abilityName: 'EntryAbility',
      parameters: { shareUrl: url },
    };
    this.imeContext.startAbility(want)
      .catch((err: Error) => console.error('shuntiIME shareUrl error', JSON.stringify(err)));
    return true;
  }

  // The donation links raise the system share sheet instead of opening an
  // in-app browser: entering card details on a soft-keyboard IME is awkward
  // and the current device may not have a payment method registered at all,
  // so sharing the link (Huawei Share to another device, a messaging app, copy
  // link, …) lets the user complete payment wherever it's convenient. Linked
  // directly from the settings panel's 開発を応援 section (SettingsBar.ets) --
  // a deliberate call after reviewing AppGallery's review guidelines (App
  // Payment/Functions/Content/Ads): no rule found prohibiting a plain external
  // donation link that doesn't gate any app feature, and HUAWEI IAP is stated
  // as recommended, not required.
  openBuyMeACoffeeLink(): boolean {
    return this.shareUrl('https://buymeacoffee.com/shunti');
  }

  openGithubSponsorsLink(): boolean {
    return this.shareUrl('https://github.com/sponsors/shuntilettuce');
  }

  // 入力中のかなの表示先を UI 側へ配る。
  //
  // 入力欄側 (previewInField) は「設定でONかつ入力欄が対応している」ときだけ
  // 実際に効く。パネル側 (showComposingPanel) は設定そのままだが、入力欄側を
  // 選んでいるのに入力欄が非対応で、かつパネルもOFFだと、打っているかなが
  // どこにも出なくなる。それは設定の意図(入力欄に出す)ではなく端末側の都合
  // なので、その場合だけパネルに戻して見えなくならないようにする。
  // 両方を自分でOFFにした場合は意図どおり何も出さない (設定画面で警告済み)。
  private publishPreviewMode(): void {
    const fieldActive = this.composingInField && this.previewSupported;
    AppStorage.setOrCreate('previewInField', fieldActive);
    AppStorage.setOrCreate('showComposingPanel',
      this.composingInPanel || (this.composingInField && !fieldActive));
  }

  // 入力中のかなをホストアプリの入力欄へ反映する。composing が空になったら
  // プレビューを終了する。updateCandidates の入口/出口から呼ぶので、
  // composing を変える経路すべてがここを通る。
  private syncPreviewText(): void {
    if (!this.previewSupported || !this.composingInField) { return; }
    const text = (AppStorage.get<string>('composingText') ?? '')
      + (AppStorage.get<string>('pendingRomaji') ?? '');
    if (text.length === 0) {
      this.cancelPreviewText();
      return;
    }
    try {
      // range は「置き換える範囲」。-1/-1 で現在のプレビュー(無ければ
      // カーソル位置)を差し替える指定になる。
      this.inputClient?.setPreviewTextSync(text, { start: -1, end: -1 });
      this.previewActive = true;
      this.previewLen = text.length;
    } catch (e) {
      // 12800011 = この入力欄はプレビュー非対応。以後は呼ばずパネル内表示へ
      // 戻す (対応可否は欄ごとなので、ここで諦めても次の欄でまた試される)。
      this.previewSupported = false;
      this.previewActive = false;
      this.previewLen = 0;
      this.publishPreviewMode();
      console.info('shuntiIME setPreviewText unsupported, falling back ' + JSON.stringify(e));
    }
  }

  // プレビューを「中身を残さずに」取り消す。
  //
  // finishTextPreviewSync() はプレビューを消すのではなく確定するので、
  // 単に呼ぶと打っていたかながそのまま入力欄に残ってしまう (全消ししたのに
  // 文字が残る)。空文字で置き換えてから確定するのが正しい取り消し方。
  // 空文字を拒否する入力欄向けに、確定してから同じ長さを消す経路も用意する。
  private cancelPreviewText(): void {
    if (!this.previewActive) { return; }
    const len = this.previewLen;
    this.previewActive = false;
    this.previewLen = 0;
    try {
      this.inputClient?.setPreviewTextSync('', { start: -1, end: -1 });
      this.inputClient?.finishTextPreviewSync();
    } catch (_e) {
      try {
        this.inputClient?.finishTextPreviewSync();
        if (len > 0) { this.inputClient?.deleteForward(len); }
      } catch (_e2) {
        // 欄が外れた等。ここで失敗しても入力は続けられる。
      }
    }
  }

  private updateCandidates(): void {
    this.syncPreviewText();
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) {
      // 打っていた読みを変換せず全部消して諦めた (resetComposition 経由の
      // 確定後クリアはこの関数を通らないので、ここに来るのは常に backspace)。
      // この直後に同じ読みが手作業で組み立て直されたら強い確認信号になる。
      if (this.composingWatermark.length > 0) {
        UnknownWordLearner.noteAbandonedReading(this.composingWatermark);
        this.composingWatermark = '';
      }
      AppStorage.setOrCreate('candidates', [] as string[]);
      AppStorage.setOrCreate('quasiCandidateSurfaces', [] as string[]);
      return;
    }
    if (composing.length > this.composingWatermark.length) { this.composingWatermark = composing; }
    // A new composition has started -- retire the post-commit next-word strip
    // so it doesn't linger next to live conversion candidates.
    AppStorage.setOrCreate('predictions', [] as string[]);
    this.predictionWordGroups = [];

    // conversionEnd defines the split point: text before it is converted,
    // text after stays as kana. 0 means convert the full text.
    const target = this.conversionTarget();

    const fullKatakana = KanaKanjiConverter.toKatakana(target);
    const segs = this.kanjiConverter.segment(target);
    let candidates: string[];
    // Recomputed below whenever the composing text is multi-segment. Reset
    // here so a single-segment / symbol-prefix / stale commit falls back to
    // the plain whole-string recordChoice instead of a stale alignment.
    this.lastAlignment = undefined;

    if (segs.length <= 1) {
      candidates = this.kanjiConverter.lookup(target);
    } else {
      // Auto-converted prefix (all but the last segment). Computed once here
      // so BOTH the whole-reading-hit branch and the decompose branch below
      // can capture the same per-segment breakdown for learning -- most
      // natural sentences take the hasRealHit branch (lookup already joins
      // the segments), so an alignment built only inside the decompose branch
      // would miss them.
      const prefixParts = segs.slice(0, -1).map((s: string, i: number) => this.kanjiConverter.autoConvert(s, segs[i + 1], segs[i - 1]));
      const hasSymbolPrefix = prefixParts.some((p: string) => KanaKanjiConverter.isSymbolOnly(p));
      const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
      // A prefix that resolves to a bare symbol (かっこ→"()") isn't a usable
      // learning alignment either -- leave lastAlignment undefined so those
      // commits fall back to whole-string learning.
      if (!hasSymbolPrefix) {
        this.lastAlignment = { segs: segs, prefixSurfaces: prefixParts, prefixText: prefixText };
      }

      // Try full-text lookup first. If it returns a real dictionary hit
      // (not just the katakana/kana fallback), use it — this prevents
      // Viterbi mis-segmentation from producing garbage like 足素ト for あしすと.
      const fullCands = this.kanjiConverter.lookup(target);
      const fullFirst = fullCands[0];
      // A dict-authored loanword (こんびに→コンビニ) has fullFirst === the
      // auto-katakana, so the plain fullFirst!==fullKatakana test would reject
      // it and fall to segmentation (こんび+に → garbage). Treat a whole
      // reading that IS a dictionary word as a real hit regardless.
      const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== target) ||
        KanaKanjiConverter.isDictionaryWord(target);

      if (hasRealHit) {
        candidates = fullCands;
      } else {
        // Multi-segment: auto-convert prefix, show variants for last segment.
        // Viterbi result goes to position 0; katakana is position 1.
        // Putting katakana at 0 unconditionally causes long natural Japanese
        // (e.g. きょうはいいてんきですね) to always show all-katakana first.
        // A prefix segment that resolves to a bare symbol (e.g. かっこ→"()")
        // means Viterbi split a casual word across a symbol "word" — joining
        // it would produce nonsense like "()よ" for かっこよ. Fall back to the
        // plain kana/katakana candidates instead of using that prefix.
        const lastSeg = segs[segs.length - 1];
        let lastCands = this.kanjiConverter.lookup(lastSeg);
        // The last segment is converted here with no context (unlike prefix
        // segments, which go through autoConvert). Let a context rule force its
        // lead -- e.g. a trailing おく auxiliary after a て/で form stays kana
        // (読んで + おいて → 読んでおいて, not 読んで置いて).
        const forcedLead = KanaKanjiConverter.contextLead(lastSeg, prefixText);
        if (forcedLead !== null && lastCands.length > 0 && lastCands[0] !== forcedLead) {
          lastCands = [forcedLead, ...lastCands.filter((c: string) => c !== forcedLead)];
        }
        const segCands = hasSymbolPrefix ? [] : lastCands.map((c: string) => prefixText + c);
        candidates = [];
        if (hasSymbolPrefix) {
          // No usable kanji join — plain kana leads, same as the
          // segmentJoinFallback bail-out for single-lookup composing text.
          candidates.push(target);
        } else if (segCands.length > 0) {
          // Position 0: best Viterbi candidate
          candidates.push(segCands[0]);
        }
        // Position 1: katakana (loanwords reachable with one Space tap)
        if (!candidates.includes(fullKatakana)) {
          candidates.push(fullKatakana);
        }
        // Remaining Viterbi variants
        for (let i = 1; i < segCands.length; i++) {
          if (!candidates.includes(segCands[i])) { candidates.push(segCands[i]); }
        }
        if (!candidates.includes(target)) { candidates.push(target); }
      }
    }

    // Per-segment homophone alternatives for the whole sentence, inserted
    // right after the primary pick and ahead of the katakana/kana fallbacks
    // the branches above appended. Track A used to offer only the last
    // segment's variants (or nothing useful for a whole-phrase entry), so a
    // homophone in any earlier word — 橋/箸 in はしをわたる, 撮る/取る in
    // 写真をとった — never appeared anywhere in the list. (Empty for track B,
    // whose lookup already routed through composeMozcCandidates above.)
    const alts = this.kanjiConverter.sentenceAlternatives(target);
    // Insert the alternatives just ABOVE the katakana/kana fallbacks, not at a
    // fixed position 1: a whole-phrase dict entry can already carry a genuine
    // kanji alternative at candidate[1] (はなをみる → 花を観る, 花を見る), and
    // blindly prepending would bury that real alternative below the injected
    // ones. Find where the junk (full katakana / as-typed kana) starts and
    // slot the alternatives right before it, so both the entry's own
    // alternatives and the per-segment swaps stay above the fallbacks.
    const kIdx = candidates.indexOf(fullKatakana);
    const cIdx = candidates.indexOf(target);
    let insertAt: number;
    if (kIdx < 0 && cIdx < 0) { insertAt = candidates.length; }
    else if (kIdx < 0) { insertAt = cIdx; }
    else if (cIdx < 0) { insertAt = kIdx; }
    else { insertAt = kIdx < cIdx ? kIdx : cIdx; }
    // ただし候補0が辞書の実ヒットなら、その上には入れない。
    //
    // 上の「カタカナ形はゴミ」という前提は、外来語では成り立たない。
    // さみっと の候補は [サミット, さみっと] で、カタカナ形がそのまま辞書の
    // 正解なのに fallback と見なされ、insertAt が 0 になっていた。結果、
    // さ充っと / さ三と / さミッと が サミット より上に挿し込まれ、実機の
    // 入力ログでは サミット が7番目まで沈んでいた (こすぷれ→コスプレ も同じ)。
    // 辞書に載っていない外来語すべてで起きる。
    // 候補0が「打ったかなそのもの」でないなら実ヒットなので、位置0は明け渡さない。
    if (insertAt === 0 && candidates.length > 0 && candidates[0] !== target) {
      insertAt = 1;
    }
    for (const a of alts) {
      if (!candidates.includes(a)) {
        candidates.splice(insertAt, 0, a);
        insertAt++;
      }
    }

    // 自動区切り変更: a candidate from a differently-segmented parse of the
    // same reading (へんかんせいど's single whole-compound entry 変換精度 vs the
    // へんかん+せいど split's 返還制度).
    //
    // 区切りが違う候補が「先頭よりかなが少ない」= 先頭がかなのまま残した所を
    // 漢字にできているなら、候補1に入れる。はいじんじゃ は 廃人じゃ(かな2文字)
    // に対し 廃神社(かな0文字)で、区切りを直せば全部漢字になる型。以前はこれが
    // 同音語(癈人じゃ/俳人じゃ/配陣じゃ)の下、5番目に埋もれていた。
    //
    // かなの数が減らないものは今までどおり下に置く。区切りを変えただけで
    // 漢字の当て方が変わらない候補は、単なる別表記と大差なく、しかも
    // 境界の迂回探索は時々 贅金を修める(ぜいきんをおさめる)や 先生似合う
    // (せんせいにあう)のような妙な再解釈を出す。上げると本当に欲しい
    // 税金を納める が押し下げられる(実測: 候補4→5)。
    const altSeg = this.kanjiConverter.findAlternateSegmentation(target);
    if (altSeg !== null && !candidates.includes(altSeg)) {
      const kanaCount = (t: string): number => {
        let n = 0;
        for (let i = 0; i < t.length; i++) {
          const c = t.charCodeAt(i);
          if (c >= 0x3041 && c <= 0x309F) { n++; }
        }
        return n;
      };
      const lifts = candidates.length > 0 && kanaCount(altSeg) < kanaCount(candidates[0]);
      candidates.splice(lifts ? 1 : insertAt, 0, altSeg);
    }

    // General learned-context rerank: if the user has actually written one of
    // these candidates after the current context before (映画を→見る, 資料を→作る),
    // pull it to the front. Unlike the hand-curated CONTEXT_HINTS table this
    // generalises to EVERY word pair the user types -- no per-homophone coding,
    // it just learns. Empty (no reorder) until the pair has been written, and
    // it only ever matches a full-word candidate, so partial-input candidate
    // lists are untouched.
    candidates = this.applyContextRerank(candidates);

    // Predictive completion: once enough of a known common phrase's reading
    // has been typed to be unambiguous, lead with the whole thing rather than
    // making the user type out a full greeting/set phrase.
    const predictive = findPredictiveCompletion(target);
    if (predictive !== null && !candidates.includes(predictive)) {
      candidates = [predictive, ...candidates];
    }

    // Predictive conversion (予測変換): common words whose reading EXTENDS what's
    // been typed so far (かいし→会社, にほん→日本語), inserted right after the exact
    // conversion so they're one tap away without finishing the reading. Only
    // fires for words that are strictly longer than the prefix, so a fully-typed
    // reading (which the exact conversion already handles) adds nothing here --
    // this is why it never disturbs the whole-sentence conversion candidates.
    let insAt = candidates.length > 0 ? 1 : 0;
    // 未知語学習: a word this user has hand-assembled from single kanji / by
    // trimming a longer conversion enough times (see UnknownWordLearner) is
    // something the dictionaries genuinely cannot produce, so it leads the
    // injected alternatives -- it is the one entry here that exists solely
    // because this user kept asking for it.
    for (const u of UnknownWordLearner.candidates(target)) {
      if (!candidates.includes(u)) { candidates.splice(insAt, 0, u); insAt++; }
    }
    // Date/time expansion (きょう→2026年7月23日, いま→15:05, あした→翌日…) leads the
    // alternatives for its trigger readings -- when someone types きょう the live
    // date is a likelier intent than a prefix-completion (教育 for きょういく).
    // Ephemeral live values -- excluded from conversion learning by
    // isNonLearningCandidate.
    const dateTimes = DateTimePredictor.predict(target, new Date());
    for (const d of dateTimes) {
      if (!candidates.includes(d)) { candidates.splice(insAt, 0, d); insAt++; }
    }

    // Common-word prefix completions (かいし→会社), after any date/time values.
    const completions = PredictiveConversion.predict(target, KanaKanjiConverter.getLearned(),
      KanaKanjiConverter.prefixCompletions(target, PREDICT_DICT_HITS));
    for (const c of completions) {
      if (!candidates.includes(c)) { candidates.splice(insAt, 0, c); insAt++; }
    }

    // Numeral formatting (1000000→1,000,000 / 100万 / 百万) for bare-digit input.
    // Ephemeral like the above -- excluded from conversion learning.
    const numForms = NumberFormatter.predict(target);
    for (const nf of numForms) {
      if (!candidates.includes(nf)) { candidates.splice(insAt, 0, nf); insAt++; }
    }

    // Now that every source has contributed, pull whatever this user has
    // actually been picking for this reading to the front. Applied here rather
    // than relying on lookup()'s own learning boost because most of the list
    // above never passed through lookup() -- see applyLearnedOrder.
    candidates = KanaKanjiConverter.applyLearnedOrder(target, candidates);
    // 準候補 (quasi-candidates): まだ LEARN_THRESHOLD 未満の、組み立てかけの
    // 未知語。確定候補(上の UnknownWordLearner.candidates)とは違い列の末尾に
    // だけ足す -- まだ確認できていない語を目立つ位置に出すと通常の変換を
    // 押しのけてしまうため。CandidateBar 側は quasiCandidateSurfaces を見て
    // うっすら区別して表示する。
    const quasi = UnknownWordLearner.quasiCandidates(target);
    for (const q of quasi) {
      if (!candidates.includes(q)) { candidates.push(q); }
    }
    AppStorage.setOrCreate('quasiCandidateSurfaces', quasi);
    // Candidates the user deleted by long-pressing them are dropped last, so
    // every source above (dictionaries, learning, the injected predictions) is
    // covered by the one filter -- see SuppressedCandidates.
    AppStorage.setOrCreate('candidates', SuppressedCandidates.filter(target, candidates));
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
  }

  handleVariantCycle(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.COMPOSING) { return; }
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) { return; }
    const last = composing.slice(-1);
    const next = VARIANT_CYCLE[last];
    if (next !== undefined) {
      AppStorage.setOrCreate('composingText', composing.slice(0, -1) + next);
      this.updateCandidates();
    }
  }

  handleCursorLeft(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (state === InputState.BUNSETSU) {
      this.selectBunsetsuSegment(this.bCur - 1);
    } else if ((state === InputState.COMPOSING || state === InputState.SELECTING) && composing.length > 0) {
      if (this.conversionEnd === 0) {
        this.conversionEnd = composing.length;
      }
      if (this.conversionEnd > 1) {
        this.conversionEnd--;
        AppStorage.setOrCreate('convEnd', this.conversionEnd);
        InputLog.recordRange(composing, this.conversionEnd); // [DEBUG-LOG]
        this.updateCandidates();
      }
    } else {
      // 実際に動いた分だけ hostCursor に反映する。取消キーの位置追跡は
      // このIME自身が動かした分の自己申告なので、ここを飲むと矢印キーでの
      // 移動後に取消を押しても正しい位置へ戻れる (hostUndoStack のコメント
      // 参照)。動かせたかどうか確認できないので、成功した(=例外が出なかった)
      // ときだけ加算する。
      this.inputClient?.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT)
        .then(() => { this.hostCursor -= 1; })
        .catch((_e: Error) => {});
    }
  }

  handleCursorRight(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (state === InputState.BUNSETSU) {
      this.selectBunsetsuSegment(this.bCur + 1);
    } else if ((state === InputState.COMPOSING || state === InputState.SELECTING) && composing.length > 0) {
      if (this.conversionEnd > 0 && this.conversionEnd < composing.length) {
        this.conversionEnd++;
        AppStorage.setOrCreate('convEnd', this.conversionEnd);
        InputLog.recordRange(composing, this.conversionEnd); // [DEBUG-LOG]
        this.updateCandidates();
      } else if (this.conversionEnd === 0) {
        // Already at full length, no change needed
      }
    } else {
      this.inputClient?.moveCursor(inputMethodEngine.Direction.CURSOR_RIGHT)
        .then(() => { this.hostCursor += 1; })
        .catch((_e: Error) => {});
    }
  }

  handleDirectKana(kana: string): void {
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;

    if (mode === InputMode.ALPHANUMERIC) {
      this.commitPending();
      // raw: true -- 英数モードは1打鍵ごとに insertText が飛ぶ (かなモード
      // のように単語単位でまとまらない)。素のまま扱わないと、括弧を開いた
      // 直後に "t" を1文字打っただけで閉じ括弧が確定してしまい、続く
      // "est" が閉じの外側に出てしまう。保留中の閉じは英数入力では
      // 消費も生成もしない(消さずに残す -- 後で かな側の確定があれば
      // そちらで正しく閉じられる)。
      this.insertText(kana, { raw: true } as InsertTextOptions);
      return;
    }

    if (state === InputState.SELECTING || state === InputState.BUNSETSU) {
      this.commitTopCandidate();
    }

    const current = AppStorage.get<string>('composingText') ?? '';
    AppStorage.setOrCreate('composingText', current + kana);
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('inputState', InputState.COMPOSING);
    this.conversionEnd = (current + kana).length;
    AppStorage.setOrCreate('convEnd', this.conversionEnd);
    // composingUndoStack はここで消さない -- 「けす→ら足す→やっぱりさっき
    // 消した方を戻したい」のように、この回の組み立て中はbackspace履歴を
    // 保ったまま何度でも取消キーで遡れるようにする (resetComposition で
    // 確定したときだけ、その回の組み立ては終わりとして空にする)。
    this.updateCandidates();
  }

  // Enter bunsetsu mode: segment composing text and show first segment's candidates
  handleBunsetsu(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.COMPOSING) { return; }
    let composing = AppStorage.get<string>('composingText') ?? '';
    const pending = this.converter.flushPending();
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    if (pending.length > 0) {
      const kana = mode === InputMode.KATAKANA ? toKatakana(pending) : pending;
      composing = composing + kana;
      AppStorage.setOrCreate('composingText', composing);
      AppStorage.setOrCreate('pendingRomaji', '');
    }
    if (composing.length === 0) { return; }
    this.bSegs = this.kanjiConverter.segment(composing);
    this.bChosen = this.bSegs.map((seg: string, i: number) => this.kanjiConverter.autoConvert(seg, this.bSegs[i + 1], this.bSegs[i - 1]));
    InputLog.recordBunsetsu(composing, this.bSegs); // [DEBUG-LOG]
    this.bCur = 0;
    this.updateBunsetsuStorage();
  }

  // Navigate to a specific segment and refresh candidates
  selectBunsetsuSegment(idx: number): void {
    if (idx < 0 || idx >= this.bSegs.length) { return; }
    this.bCur = idx;
    this.updateBunsetsuStorage();
  }

  // Commit all segments as final text
  commitBunsetsu(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.BUNSETSU) { return; }
    const text = this.bChosen.join('');
    for (let i = 0; i < this.bSegs.length; i++) {
      KanaKanjiConverter.recordChoice(this.bSegs[i], this.bChosen[i]);
    }
    InputLog.recordBunsetsuFinal(this.bSegs.join(''), text); // [DEBUG-LOG]
    this.insertText(text);
    this.bSegs = [];
    this.bChosen = [];
    this.bCur = 0;
    this.resetComposition();
    this.saveLearning();
  }

  // Called when user taps a candidate while in BUNSETSU state
  commitBunsetsuCandidate(index: number): void {
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    if (index < candidates.length) {
      KanaKanjiConverter.recordChoice(this.bSegs[this.bCur], candidates[index]);
      InputLog.recordBunsetsuPick(this.bSegs[this.bCur], candidates[index], index, candidates.length, candidates); // [DEBUG-LOG]
      this.bChosen[this.bCur] = candidates[index];
    }
    // Advance to next segment if available
    if (this.bCur + 1 < this.bSegs.length) {
      this.bCur += 1;
      this.updateBunsetsuStorage();
    } else {
      this.commitBunsetsu();
    }
  }

  private updateBunsetsuStorage(): void {
    const segTexts: string[] = this.bChosen.map((ch: string, i: number) =>
      i === this.bCur ? `[${ch}]` : ch
    );
    AppStorage.setOrCreate('bunsetsuTexts', this.bChosen as string[]);
    AppStorage.setOrCreate('bunsetsuRaw', this.bSegs as string[]);
    AppStorage.setOrCreate('bunsetsuCurrent', this.bCur);
    AppStorage.setOrCreate('bunsetsuDisplay', segTexts.join(''));
    const seg = this.bSegs[this.bCur];
    const cands = SuppressedCandidates.filter(seg, this.kanjiConverter.lookup(seg));
    AppStorage.setOrCreate('candidates', cands);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('inputState', InputState.BUNSETSU);
  }

  handleDakuten(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.COMPOSING) { return; }
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) { return; }
    const last = composing.slice(-1);
    const toggled = DAKUTEN[last];
    if (toggled !== undefined) {
      AppStorage.setOrCreate('composingText', composing.slice(0, -1) + toggled);
    }
  }

  handleHandakuten(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.COMPOSING) { return; }
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) { return; }
    const last = composing.slice(-1);
    const toggled = HANDAKUTEN[last];
    if (toggled !== undefined) {
      AppStorage.setOrCreate('composingText', composing.slice(0, -1) + toggled);
    }
  }

  handleSmall(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.COMPOSING) { return; }
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) { return; }
    const last = composing.slice(-1);
    const toggled = SMALL_KANA[last];
    if (toggled !== undefined) {
      AppStorage.setOrCreate('composingText', composing.slice(0, -1) + toggled);
    }
  }

  // raw: true は括弧の自動閉じを掛けない (貼り付け・予測タップなど、
  // 「打ち込んだ通りそのまま出したい」文字列専用)。ユーザーがコピーした
  // 内容がたまたま "()" のような2文字と一致しても、括弧機能に横取りされて
  // 別の場所へ送られては困るため。
  insertText(text: string, opts?: InsertTextOptions): void {
    // 辞書の自由入力中は、確定した文字をホストアプリではなくパネル内の欄に送る。
    //
    // キーボードのパネルに TextInput を置いても、キーボード自身が入力対象に
    // なるため通常の経路では文字を入れられない。一方で「確定した文字が外に出る
    // 唯一の出口」はこの insertText なので、ここだけ差し替えれば、ローマ字入力・
    // かな漢字変換・候補選択といった仕組みはそのまま使える。
    if (this.captureTarget.length > 0) {
      this.appendCaptured(text);
      return;
    }

    // 括弧の自動閉じ (設計意図は BRACKET_PAIRS のコメント参照)。
    // カーソルは一切動かさず、開きだけを今確定して、閉じは次の確定の
    // 直後まで保留する。
    let finalText = text;
    if (opts?.raw !== true) {
      let newOpen: string | undefined;
      let newClose: string | undefined;
      if (text.length === 2 && BRACKET_PAIRS[text[0]] === text[1]) {
        // 「（）」のように開き+閉じ1組で確定された(かっこ等の変換候補)。
        newOpen = text[0];
        newClose = text[1];
      } else if (text.length === 1 && BRACKET_PAIRS[text] !== undefined) {
        // 記号パネルで開き括弧を単体でタップした場合も同様に扱う。
        newOpen = text;
        newClose = BRACKET_PAIRS[text];
      }
      if (newOpen !== undefined && newClose !== undefined) {
        // 保留中の古い閉じがあれば、入れ子にはせず先に閉じてしまう。次の
        // 確定が古い括弧の中身か新しい括弧の中身か区別する手段が無いため、
        // 単純に「前のは前ので完結させ、新しい括弧を開く」にしてある。
        finalText = this.pendingBracketClose + newOpen;
        this.pendingBracketClose = newClose;
      } else if (this.pendingBracketClose.length > 0) {
        finalText = text + this.pendingBracketClose;
        this.pendingBracketClose = '';
      }
    }

    // 入力欄プレビューが出ているときは insertText を使わない。
    //
    // finishTextPreviewSync() は「プレビューを消す」のではなく「プレビューの
    // 内容をその場で確定する」API だった。そのため 解除 → insertText の順に
    // 呼ぶと、確定したかな + 変換結果 で入力欄に二重に残る (実機で確認)。
    // 正しくは、プレビュー自体を最終的な文字列で置き換えてから確定する。
    let previewCommitted = false;
    if (this.previewActive) {
      try {
        this.inputClient?.setPreviewTextSync(finalText, { start: -1, end: -1 });
        this.inputClient?.finishTextPreviewSync();
        this.previewActive = false;
        previewCommitted = true;
      } catch (_e) {
        // 置き換えに失敗したらプレビューを畳んで通常の挿入に落とす。
        this.cancelPreviewText();
      }
    }
    if (!previewCommitted) { this.inputClient?.insertText(finalText); }
    if (finalText.length > 0) {
      for (let i = 0; i < finalText.length; i++) {
        this.insertedBuffer.push(finalText[i]);
      }
      if (this.insertedBuffer.length > 50) {
        this.insertedBuffer = this.insertedBuffer.slice(-50);
      }
      // 変換確定・生かな確定・記号/絵文字タップ・予測変換タップ・
      // クリップボード貼り付け...どの経路で来ても、ホストへ実際に文字が
      // 出た時点はここ1箇所なので、取消キー用の記録もここで行う。
      this.pushHostOp('insert', finalText);
      KanaKanjiConverter.setLastCommitText(finalText);
    }
  }

  hideKeyboard(): void {
    this.kbController?.hide();
  }
}

// ---------- KeyboardController ----------

const USE_DICT_JSON: boolean = true;

// 予測変換に渡す辞書由来の前方一致の件数。PredictiveConversion 側は学習・
// 手書き表を先に詰めてから残り枠にこれを入れるので、実際に表に出るのは
// MAX_COMPLETIONS まで。多めに渡して選ばせる。
const PREDICT_DICT_HITS = 8;

export class KeyboardController {
  private panel: inputMethodEngine.Panel | undefined;
  private inputHandle: InputHandler = InputHandler.getInstance();
  private kbDelegate: inputMethodEngine.KeyboardDelegate | undefined;

  private context: InputMethodExtensionContext;

  constructor(context: InputMethodExtensionContext) {
    this.context = context;
  }

  onCreate(): void {
    // The Japanese font is registered by KeyboardPage.aboutToAppear, not here:
    // initPanel/setUiContent hasn't run yet, so there is no UI instance to
    // register into (see components/JpFont.ets).
    this.inputHandle.setContext(this.context);
    this.inputHandle.setKeyboardControllerRef(this);
    this.applyColorMode();
    this.initPanel();
    this.registerListeners();
    this.loadDictionary();
    this.loadGlobalDictionary();
    this.loadVocabPacks();
    this.loadViterbiData();
  }

  // Re-resolves the live OS color mode via resourceManager (see
  // isDarkFromResourceManager's comment for why this, not context.config,
  // is what must be called anywhere isDark needs to be current -- including
  // repeatedly, from inputStart, not just once at onCreate).
  applyColorMode(): void {
    const mode = AppStorage.get<string>('themeMode') ?? 'system';
    AppStorage.setOrCreate('isDark', resolveIsDark(mode, isDarkFromResourceManager(this.context as ESObject)));
  }

  // Applies the Configuration object handed directly to onConfigurationUpdate
  // (InputMethodExtAbility's own onConfigurationUpdate calls this), on the
  // rare OS versions/timings where that callback does fire for this
  // extension. isDarkFromConfiguration's comment covers why the object
  // handed to the callback (not a context.config re-read) is what's safe to
  // trust here.
  applyColorModeFrom(config: ESObject): void {
    const mode = AppStorage.get<string>('themeMode') ?? 'system';
    AppStorage.setOrCreate('isDark', resolveIsDark(mode, isDarkFromConfiguration(config)));
  }

  onDestroy(): void {
    // 予約中の学習・削除候補の保存を確定させてから畳む。
    this.inputHandle.flushPendingSaves();
    InputLog.flush(); // [DEBUG-LOG] 未書き出しの記録を落とさない
    this.unregisterListeners();
    if (this.panel) {
      IMEAbility.destroyPanel(this.panel);
      this.panel = undefined;
    }
  }

  // 独自辞書 (dict.json / global_dict.json) はパック済みバイナリで読む。
  //
  // JSON.parse した状態は実機で ArkTS ヒープ約144MB を占めていた -- mozc の
  // データ全部より重い。読み383,383件と表記594,173個をJSオブジェクトとして
  // 持てばそうなる。中身は一切変えず、mozc の表と同じ形式 (blob + 長さ +
  // ブロック基準、触れた文字列だけ復号) に移してある。
  // 書き出しは tools/pack_dicts.py、等価性の検証は tools/verify_dicts.js。
  private loadPackedDict(name: string,
      apply: (kb: Uint8Array, kl: Uint8Array, kbase: Uint32Array,
              vb: Uint8Array, vl: Uint8Array, vbase: Uint32Array,
              idx: Uint32Array) => void): void {
    const rm = this.context.resourceManager;
    const toU32 = (d: Uint8Array): Uint32Array =>
      new Uint32Array(d.buffer.slice(d.byteOffset, d.byteOffset + d.byteLength));
    const names: string[] = [
      name + '.keys.blob', name + '.keys.len', name + '.keys.base',
      name + '.vals.blob', name + '.vals.len', name + '.vals.base',
      name + '.idx.bin',
    ];
    Promise.all(names.map((n: string) => rm.getRawFileContent(n)))
      .then((all: Uint8Array[]) => {
        apply(all[0], all[1], toU32(all[2]), all[3], all[4], toU32(all[5]), toU32(all[6]));
      })
      .catch((e: Error) => {
        // 黙って落とさない。辞書が読めていない状態は変換品質が静かに下がる
        // だけで表からは見えず、実際 KeyboardPage 側の重複ロードが
        // dict.json 削除後に無言で死んでいた。
        console.error('shuntiIME packed dict load failed: ' + name, JSON.stringify(e));
      });
  }

  private loadDictionary(): void {
    if (!USE_DICT_JSON) { return; }
    this.loadPackedDict('dict',
      (kb: Uint8Array, kl: Uint8Array, kbase: Uint32Array, vb: Uint8Array,
       vl: Uint8Array, vbase: Uint32Array, idx: Uint32Array) => {
        KanaKanjiConverter.loadDictionaryPacked(kb, kl, kbase, vb, vl, vbase, idx);
      });
  }

  // Build the Viterbi connection matrix from inline grammar rules (no external file).
  private loadViterbiData(): void {
    KanaKanjiConverter.initConnectionMatrix();
  }

  // Developer-curated dictionary bundled as rawfile/global_dict.json.
  // Bundled with the app and committed to the repo (the old DevDict editor is gone);
  // applies to all users from the next patch. Highest conversion priority.
  private loadGlobalDictionary(): void {
    this.loadPackedDict('global_dict',
      (kb: Uint8Array, kl: Uint8Array, kbase: Uint32Array, vb: Uint8Array,
       vl: Uint8Array, vbase: Uint32Array, idx: Uint32Array) => {
        KanaKanjiConverter.setGlobalDictPacked(kb, kl, kbase, vb, vl, vbase, idx);
      });
  }

  // 語彙パック (淫夢語録・なんJ語など、既定OFFの追加インストール的な
  // ニッチ語彙)。どのパックが存在するかはアプリ側にハードコードせず、
  // rawfile/pack_manifest.json (tools/build_vocab_packs.py が
  // tools/vocab_packs/*.pack から生成) を読んで決める -- こうしないと
  // 「パックを1つ足すのに .ets の編集が要る」ことになり、語彙パックの
  // 目的 (誰でも語彙を足せる) が崩れる。
  //
  // 各パックは数十件しかないので mozc のような遅延読み込みはせず、
  // manifest が読めた時点で全部バイナリを読んでおく -- ロードしただけでは
  // まだ何も変換に効かない (KanaKanjiConverter.enabledPacks が空のまま)。
  // 実際に候補へ混ざるかどうかは reloadSettings 側で setEnabledPackIds を
  // 呼んだときだけ決まる。
  private loadVocabPacks(): void {
    this.context.resourceManager.getRawFileContent('pack_manifest.json')
      .then((data: Uint8Array) => {
        const text = util.TextDecoder.create('utf-8').decodeToString(data);
        const list = JSON.parse(text) as VocabPackInfo[];
        KanaKanjiConverter.setVocabPackManifest(list);
        for (const p of list) {
          // 活用展開 (五段/一段/形容詞) は品詞が付いた語だけの話で、その語は
          // manifest の pos に読みと表記の両方が入っている。そこから最小限の
          // 入力を組み立てて ConjugationEngine に通す -- ユーザー辞書と
          // まったく同じ関数なので活用ロジックの二重実装は無い。
          // 語彙本体 (バイナリ) を JS へ展開する必要はない。
          const seed: Record<string, string[]> = {};
          const posMap: Record<string, UserPosEntry> = {};
          for (const key of Object.keys(p.pos)) {
            const v = p.pos[key];
            posMap[key] = { pos: v.pos as PosKind, group: v.group as VerbGroup | undefined };
            const parts = key.split('	');
            if (parts.length === 2) {
              const cur = seed[parts[0]];
              if (cur === undefined) { seed[parts[0]] = [parts[1]]; }
              else if (!cur.includes(parts[1])) { cur.push(parts[1]); }
            }
          }
          const expanded = buildUserExpansion(seed, posMap);
          // 活用展開で得たクラス (がばって→[14,17] など) の上に、.pack の
          // @指定を重ねる。明示指定のほうが後勝ちで強い。
          const classes: Record<string, number[]> = {};
          for (const k of Object.keys(expanded.classMap)) { classes[k] = expanded.classMap[k]; }
          for (const k of Object.keys(p.classes)) { classes[k] = p.classes[k]; }
          KanaKanjiConverter.setVocabPackOverlay(p.id, expanded.dict, classes);
        }
        AppStorage.setOrCreate('vocabPackIds', list.map((p: VocabPackInfo) => p.id));
        // 設定より先に manifest が来るとは限らないので、ここでもう一度
        // 有効なパックを決め直す (順序に依存させない)。有効判定と読み込みは
        // 設定を持っている InputHandler 側が担当する。
        this.inputHandle.refreshVocabPacks();
      })
      .catch((e: Error) => {
        // 語彙パックが読めなくても変換自体は動く (全部OFFと同じ状態)。
        // ただし黙って消えると原因が分からないので必ず残す。
        console.error('shuntiIME vocab pack manifest load failed', JSON.stringify(e));
      });
  }

  private computeKeyWidths(dis: display.Display): void {
    const safeDPI = dis.densityDPI > 0 ? dis.densityDPI : 460;
    const density = safeDPI / 160;
    const fullVp = dis.width / density;
    // On foldables/tablets the unfolded inner screen is very wide; stretching
    // 10 keys across it makes each key huge and hard to reach. Cap the keyboard
    // content width and let the rows center themselves (justifyContent.Center),
    // matching how phone-style keyboards float centered on large displays.
    // Detect tablet/foldable class by the device's SHORTER physical dimension,
    // not by whichever dimension is currently "width" — a normal phone rotated
    // to landscape also reports a large dis.width, but its narrow dimension
    // (the portrait width) is still phone-sized, so it must NOT be capped like
    // a tablet. Without this, every phone in landscape rendered a narrow,
    // centered keyboard with large empty margins on both sides (looked tiny,
    // unlike Gboard which fills the full landscape width).
    const shortVp = Math.min(dis.width, dis.height) / density;
    const isTabletClass = shortVp > 600;
    AppStorage.setOrCreate('isTabletClass', isTabletClass);
    AppStorage.setOrCreate('isWideScreen', isTabletClass && fullVp > MAX_KB_VP);

    // This is only a best-effort guess from raw display metrics — on-device
    // diagnostics confirmed this device's IME panel framework silently shrinks
    // the panel to a fraction of the width requested via panel.resize() (~76%
    // observed, with no corresponding cutout reported — a software policy, not
    // a hardware inset), so display metrics alone can't be trusted.
    // KeyboardPage.onAreaChange measures the real width and both applies the
    // correction AND records a scale factor (measured/guessed) here, per
    // orientation. Apply that learned scale up front: after the very first
    // launch, this panel is reused across show/hide (see the 'inputStop'
    // handler), so initPanel() never runs again and a later resizePanel() call
    // (e.g. from a display 'change' event that doesn't actually alter the
    // panel's on-screen size) may not be followed by a fresh onAreaChange —
    // without this, that would silently overwrite the corrected widths with
    // the raw (wrong) guess again, with nothing left to re-correct them.
    // Tablet-class devices are excluded: their narrower width there is our own
    // deliberate MAX_KB_VP cap, not the shrink bug, so it shouldn't be learned
    // as a scale factor.
    const isLandscape = dis.width > dis.height;
    const scaleKey = isLandscape ? 'widthScaleLandscape' : 'widthScalePortrait';
    const learnedScale = isTabletClass ? 1 : (AppStorage.get<number>(scaleKey) ?? 1);
    AppStorage.setOrCreate('lastRawFullVp', fullVp);
    AppStorage.setOrCreate('lastRawFullVpIsLandscape', isLandscape);
    applyKeyboardWidthsForVp(fullVp * learnedScale, isTabletClass);
  }

  // densityDPI/160 gives the px-per-vp ratio (e.g. 460dpi/160 = 2.875 on Pura 70)
  private computeKeyHeight(dis: display.Display, isLandscape: boolean): number {
    const density = dis.densityDPI > 0 ? dis.densityDPI / 160 : 3.0;
    // Landscape screens are short, so the keyboard needs a larger share of that
    // short dimension to stay comfortably tappable (Gboard-style) rather than
    // shrinking rows down — portrait: clamp 25–60%; landscape: allow up to 80%.
    const contentPx = Math.ceil((isLandscape ? 420 : 360) * density);
    const maxFrac = isLandscape ? 0.80 : 0.60;
    const base = Math.max(
      Math.floor(dis.height * 0.25),
      Math.min(contentPx, Math.floor(dis.height * maxFrac))
    );
    // 設定 → レイアウト調整 の縦の長さスライダー。既定 1.0 で今までどおり。
    // ±30% にクランプ -- それ以上は行の当たり判定が崩れる/画面の大半を
    // 覆ってしまう。
    const scale = Math.min(1.3, Math.max(0.7, AppStorage.get<number>('keyboardHeightScale') ?? 1.0));
    return Math.floor(base * scale);
  }

  private initPanel(): void {
    try {
      const dis = display.getDefaultDisplaySync();
      const isLandscape = dis.width > dis.height;
      const keyHeight = this.computeKeyHeight(dis, isLandscape);

      AppStorage.setOrCreate('isLandscape', isLandscape);
      AppStorage.setOrCreate('displayWidth', dis.width);
      AppStorage.setOrCreate('keyboardHeight', keyHeight);
      this.computeKeyWidths(dis);

      const panelInfo: inputMethodEngine.PanelInfo = {
        type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
        flag: inputMethodEngine.PanelFlag.FLG_FIXED,
      };

      IMEAbility.createPanel(this.context, panelInfo)
        .then((panel: inputMethodEngine.Panel) => {
          this.panel = panel;
          panel.resize(dis.width, keyHeight)
            .then(() => panel.moveTo(0, dis.height - keyHeight))
            .then(() => panel.setUiContent('pages/KeyboardPage'))
            .catch((err: Error) => console.error('shuntiIME panel init error', err));
        })
        .catch((err: Error) => console.error('shuntiIME createPanel error', err));
    } catch (err) {
      console.error('shuntiIME initPanel error', err);
    }
  }

  // 設定 → レイアウト調整 のスライダーからライブに呼ばれるので公開している
  // (InputHandler.applyKeyboardHeightScaleLive 参照)。パネルの実サイズは
  // panel.resize() でしか変えられず、それを持っているのはこのクラスだけ。
  resizePanel(): void {
    try {
      const dis = display.getDefaultDisplaySync();
      const isLandscape = dis.width > dis.height;
      const keyHeight = this.computeKeyHeight(dis, isLandscape);

      AppStorage.setOrCreate('isLandscape', isLandscape);
      AppStorage.setOrCreate('displayWidth', dis.width);
      AppStorage.setOrCreate('keyboardHeight', keyHeight);
      this.computeKeyWidths(dis);

      this.panel?.resize(dis.width, keyHeight)
        .then(() => this.panel?.moveTo(0, dis.height - keyHeight));
    } catch (err) {
      console.error('shuntiIME resizePanel error', err);
    }
  }

  private registerListeners(): void {
    try {
      display.on('change', () => { this.resizePanel(); this.applyColorMode(); });
    } catch (err) {
      console.error('shuntiIME display.on error', err);
    }

    try {
      IMEAbility.on('inputStart', (
        kbCtrl: inputMethodEngine.KeyboardController,
        client: inputMethodEngine.InputClient
      ) => {
        // Re-resolve the live color mode on every keyboard invocation --
        // see applyColorMode's comment. An earlier attempt at this called
        // the old context.config-reading applyColorMode() here, which
        // didn't help (that read was just as stale as the one it was
        // replacing); applyColorMode() itself is now backed by
        // resourceManager, which actually is live.
        this.applyColorMode();
        this.inputHandle.onInputStart(kbCtrl, client);
        this.panel?.show();
      });

      IMEAbility.on('inputStop', () => {
        // Only hide — don't tear down the context/panel here. initPanel()
        // (which creates this.panel) only runs once, from onCreate(), so
        // destroying the context on every inputStop left no panel to show()
        // for the *next* inputStart unless the OS happened to fully restart
        // the extension in between. That's what made the keyboard vanish
        // after a couple of show/hide cycles until something (e.g. rotating
        // back to portrait and switching IME) forced a fresh restart.
        // The real teardown belongs in the ability's own onDestroy(), which
        // already calls KeyboardController.onDestroy() when the IME service
        // is actually shut down.
        this.inputHandle.onInputStop();
        this.panel?.hide();
      });

      IMEAbility.on('setSubtype', (subtype: InputMethodSubtype) => {
        const modeMap: Record<string, string> = {
          'hiragana': InputMode.HIRAGANA,
          'katakana': InputMode.KATAKANA,
          'alphanumeric': InputMode.ALPHANUMERIC,
        };
        const mode = modeMap[subtype.id];
        if (mode) {
          this.inputHandle.commitTopCandidate();
          AppStorage.setOrCreate('inputMode', mode);
        }
      });
    } catch (err) {
      console.error('shuntiIME IMEAbility.on error', err);
    }

    try {
      this.kbDelegate = inputMethodEngine.getKeyboardDelegate();
      this.kbDelegate.on('keyDown', (_keyEvent: inputMethodEngine.KeyEvent) => {
        return false;
      });
    } catch (err) {
      console.error('shuntiIME getKeyboardDelegate error', err);
    }
  }

  private unregisterListeners(): void {
    display.off('change');
    this.kbDelegate?.off('keyDown');
  }
}
