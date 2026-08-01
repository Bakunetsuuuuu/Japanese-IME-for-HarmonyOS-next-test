import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import type { Want } from '@kit.AbilityKit';
import display from '@ohos.display';
import util from '@ohos.util';
import dataPreferences from '@ohos.data.preferences';
import pasteboard from '@ohos.pasteboard';
import { JapaneseConverter, toKatakana } from './JapaneseConverter';
import { KanaKanjiConverter, MozcMatrixData } from './KanaKanjiConverter';
import { UserDictStore } from './UserDictStore';
import { UserPosStore } from './UserPosStore';
import type { UserPosEntry } from './ConjugationEngine';
import { buildUserExpansion } from './ConjugationEngine';
import { SettingsStore, KeyboardSettings, isDarkFromConfiguration, isDarkFromResourceManager } from './SettingsStore';
import { findPredictiveCompletion } from './PredictivePhrases';
import { NextWordPredictor } from './NextWordPredictor';
import { PredictiveConversion } from './PredictiveConversion';
import { UnknownWordLearner } from './UnknownWordLearner';
import { SuppressedCandidates, SUPPRESSED_STORE, SUPPRESSED_KEY } from './SuppressedCandidates';
import { DateTimePredictor } from './DateTimePredictor';
import { NumberFormatter } from './NumberFormatter';
import { EmojiSuggest } from './EmojiSuggest';
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
  // Flick keys: 5 columns + 4 gaps × 4vp (FlickKeyboardView's Row({space:4}))
  // + 0vp H-padding (its Column has no left/right padding) = 16vp overhead --
  // same total as the old "4 gaps × 3vp + 4vp H-padding" comment assumed, by
  // coincidence, so this one was never actually broken.
  const flickKwVp = Math.max(Math.floor((screenVp - 16) / 5), 60);
  AppStorage.setOrCreate('keyWidthVp', kwVp);
  AppStorage.setOrCreate('specialKeyWidthVp', skwVp);
  AppStorage.setOrCreate('spaceKeyWidthVp', spaceVp);
  AppStorage.setOrCreate('flickKeyWidthVp', flickKwVp);
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
  private lastDeletedChar: string = '';
  private insertedBuffer: string[] = [];
  private restoreStack: string[] = [];
  private conversionEnd: number = 0;
  // Cap for the persistent deleted-character log (recordDeletedChar) --
  // unlike restoreStack above (a short-lived undo stack wiped by the next
  // keystroke, see insertText), this survives typing and is only capped by
  // size. Powers the 取消 key's sequential undo (undoLastDeletion).
  private static readonly MAX_DELETED_CHAR_HISTORY = 100;
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
      // モジュール単位 -> アプリ単位の順。読み手は両方見る (InputLog.findDir)。 // [DEBUG-LOG]
      let appDir = ''; // [DEBUG-LOG]
      try { appDir = ctx.getApplicationContext().filesDir; } catch (_e) { appDir = ''; } // [DEBUG-LOG]
      const used = InputLog.setWritableDir([ctx.filesDir, appDir]); // [DEBUG-LOG]
      console.info('shuntiIME InputLog dir=' + used + ' (module=' + ctx.filesDir + ' app=' + appDir + ')'); // [DEBUG-LOG]
      InputLog.recordPaths('setContext', // [DEBUG-LOG]
        used.length > 0 ? used : '書き込めるディレクトリ無し', // [DEBUG-LOG]
        ctx.filesDir, ctx.preferencesDir); // [DEBUG-LOG]
      UnknownWordLearner.onLearn = (r: string, s: string) => { InputLog.recordUnknownWord(r, s); }; // [DEBUG-LOG]
    } catch (e) { // [DEBUG-LOG]
      console.error('shuntiIME InputLog setup failed', JSON.stringify(e)); // [DEBUG-LOG]
    } // [DEBUG-LOG]
  } // [DEBUG-LOG]
      InputLog.setFilesDir(dir); // [DEBUG-LOG]
      InputLog.recordPaths(`${level} ${dir}`, ctx.filesDir, ctx.preferencesDir); // [DEBUG-LOG]
      UnknownWordLearner.onLearn = (r: string, s: string) => { InputLog.recordUnknownWord(r, s); }; // [DEBUG-LOG]
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
  // app), plus its 品詞 metadata (DictionaryEditPage's POS picker) --
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
        this.applyConversionEngine(s.conversionEngine);
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
  private loadMozcRawfiles(ctx: InputMethodExtensionContext, target: 'mozc' | 'hybrid' = 'mozc'): void {
    const rm = ctx.resourceManager;
    const decoder = new util.TextDecoder('utf-8');
    // toU16Array: getRawFileContent's Uint8Array may sit at a non-even
    // byteOffset, which Uint16Array/Int32Array can't wrap directly -- copy
    // into a fresh aligned buffer first. Device is little-endian, matching
    // the files written by convert_to_binary.py.
    const toBuf = (data: Uint8Array, byteOffset: number, byteLength: number): ArrayBuffer =>
      data.buffer.slice(data.byteOffset + byteOffset, data.byteOffset + byteOffset + byteLength);
    // Chained (not Promise.all + destructuring) to match this file's existing
    // getRawFileContent().then() style (see loadDictionary/loadGlobalDictionary
    // above) rather than introduce a new pattern.
    rm.getRawFileContent('mozc_readings.json')
      .then((readingsData: Uint8Array) => {
        const readings = JSON.parse(decoder.decode(readingsData)) as string[];
        return rm.getRawFileContent('mozc_dict_surfaces.json').then((dictSurfacesData: Uint8Array) => {
          const dictSurfaces = JSON.parse(decoder.decode(dictSurfacesData)) as string[];
          return rm.getRawFileContent('mozc_dict_index.bin').then((dictIndexData: Uint8Array) => {
            const dictIndex = new Uint32Array(toBuf(dictIndexData, 0, dictIndexData.byteLength));
            return rm.getRawFileContent('mozc_costs_surfaces.json').then((costsSurfacesData: Uint8Array) => {
              const costsSurfaces = JSON.parse(decoder.decode(costsSurfacesData)) as string[];
              return rm.getRawFileContent('mozc_costs_index.bin').then((costsIndexData: Uint8Array) => {
                const costsIndex = new Uint32Array(toBuf(costsIndexData, 0, costsIndexData.byteLength));
                return rm.getRawFileContent('mozc_costs.bin').then((costsBinData: Uint8Array) => {
                  // mozc_costs.bin layout: int32 cost[n] + uint16 left[n] + uint16 right[n]
                  // (see convert_to_binary.py write_outputs). n_senses = last cumulative index.
                  const nSenses = costsIndex[costsIndex.length - 1];
                  const costsCost = new Int32Array(toBuf(costsBinData, 0, nSenses * 4));
                  const costsLeft = new Uint16Array(toBuf(costsBinData, nSenses * 4, nSenses * 2));
                  const costsRight = new Uint16Array(toBuf(costsBinData, nSenses * 4 + nSenses * 2, nSenses * 2));
                  return rm.getRawFileContent('mozc_matrix.json').then((matrixData: Uint8Array) => {
                    const matrix = JSON.parse(decoder.decode(matrixData)) as MozcMatrixData;
                    // The connection matrix cells ship as a separate flat uint16 binary
                    // (mozc_matrix.bin) rather than inside the JSON, so it can be read
                    // straight into a Uint16Array without a multi-megabyte JSON parse or
                    // a boxed number[][] -- the change that keeps mozc inside the heap.
                    return rm.getRawFileContent('mozc_matrix.bin').then((binData: Uint8Array) => {
                      const cells = new Uint16Array(toBuf(binData, 0, binData.byteLength));
                      KanaKanjiConverter.loadMozcEngine(readings, dictSurfaces, dictIndex,
                        costsSurfaces, costsIndex, costsCost, costsLeft, costsRight, matrix, cells);
                      KanaKanjiConverter.setEngine(target);
                      console.info('shuntiIME mozc engine loaded, engine =', target);
                    });
                  });
                });
              });
            });
          });
        });
      })
      .catch((e: Error) => {
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
    this.learningSaveTimer = setTimeout(() => { this.writeLearning(); }, 2000);
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
    this.nextWordSaveTimer = setTimeout(() => { this.writeNextWord(); }, 2000);
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
    this.unknownWordSaveTimer = setTimeout(() => { this.writeUnknownWords(); }, 2000);
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
    InputLog.recordDeleteCandidate(reading, surface, index); // [DEBUG-LOG]
    KanaKanjiConverter.forgetChoice(reading, surface);
    UnknownWordLearner.forget(reading, surface);
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
    this.insertText(text);
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
    client.getEditorAttribute() // [DEBUG-LOG]
      .then((attr: inputMethodEngine.EditorAttribute) => { InputLog.setFieldPattern(attr.inputPattern); }) // [DEBUG-LOG]
      .catch((_e: Error) => { InputLog.setFieldPattern(0); }); // [DEBUG-LOG]
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
    this.lastDeletedChar = '';
    this.insertedBuffer = [];
    this.restoreStack = [];
    this.conversionEnd = 0;
    AppStorage.setOrCreate('convEnd', 0);
    if (!AppStorage.has('inputMode')) {
      AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
    }
    this.refreshClipboardPreview();
  }

  onInputStop(): void {
    InputLog.beginField(); // [DEBUG-LOG] flushes, then pauses until the next field is known
    this.kbController = undefined;
    this.inputClient = undefined;
    this.converter.reset();
    this.lastDeletedChar = '';
    this.insertedBuffer = [];
    this.restoreStack = [];
    this.conversionEnd = 0;
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
      const deleted = this.insertedBuffer.pop() ?? '';
      if (deleted.length > 0) { this.restoreStack.push(deleted); this.recordDeletedChar(deleted); }
      this.inputClient?.deleteForward(1);
      // Backspacing the okurigana off a just-committed word (かける→翔ける→翔)
      // is one of the two ways users hand-build a word the dictionary lacks --
      // shorten the learner's view of the run to match what's left on screen.
      UnknownWordLearner.truncate();
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
          this.lastDeletedChar = composing.slice(-1);
          this.recordDeletedChar(this.lastDeletedChar);
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
      InputLog.recordCommit(reading, text, index, candidates.length); // [DEBUG-LOG]
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
    if (PredictiveConversion.predict(composing, KanaKanjiConverter.getLearned()).indexOf(text) >= 0) {
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
      InputLog.recordCommit(reading, chosen, idx, candidates.length); // [DEBUG-LOG]
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
    this.lastDeletedChar = '';
    this.restoreStack = [];
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
    this.converter.reset();
    this.bSegs = [];
    this.bChosen = [];
    this.bCur = 0;
    this.lastDeletedChar = '';
    // NOTE: insertedBuffer is deliberately NOT cleared here. It is a rolling
    // log of characters actually inserted into the field (capped at 50), used
    // by the IDLE backspace to know which char it is deleting so the 取消 key
    // can restore it. resetComposition runs after every commit, so clearing it
    // here threw away the just-committed word's characters -- backspacing a
    // committed word then recorded nothing, and 取消 kept replaying whatever
    // stale history remained. It is cleared only on field start/stop
    // (onInputStart / onInputStop), which is the correct scope for it.
    this.restoreStack = [];
    this.conversionEnd = 0;
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
    this.insertText(text);
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
    this.insertText(text);
  }

  clearClipboardHistory(): void {
    AppStorage.setOrCreate('clipboardHistory', [] as string[]);
  }

  // Newest-first, capped-size log of individually deleted characters --
  // called from both handleBackspace branches that know exactly which
  // character just disappeared (IDLE's own-typed-char pop, COMPOSING's
  // pre-commit slice). Deliberately never cleared by subsequent typing
  // (unlike restoreStack, wiped on the next insertText) so it survives across
  // a whole typing session -- consumed newest-first by the 取消 key's
  // sequential undo (undoLastDeletion).
  private recordDeletedChar(ch: string): void {
    if (ch.length === 0) { return; }
    InputLog.recordDeleteChar(ch, AppStorage.get<string>('inputState') ?? InputState.IDLE); // [DEBUG-LOG]
    const history = AppStorage.get<string[]>('deletedCharHistory') ?? [];
    const next = [ch, ...history].slice(0, InputHandler.MAX_DELETED_CHAR_HISTORY);
    AppStorage.setOrCreate('deletedCharHistory', next);
  }

  // Restore the most recently deleted character (or whole composing chunk),
  // consuming it from the log. Pressing 取消 N times right after deleting too
  // much brings back the last N deleted characters in order, as if they were
  // never deleted -- a simple sequential undo of over-deletion, not a
  // pick-any-past-character panel. handleBackspace pushes newest-first, so
  // history[0] is always the last thing removed; restoring and popping it in
  // turn replays the deletions in reverse, reconstructing the original text.
  undoLastDeletion(): void {
    const history = AppStorage.get<string[]>('deletedCharHistory') ?? [];
    if (history.length === 0) { return; }
    const ch = history[0];
    AppStorage.setOrCreate('deletedCharHistory', history.slice(1));
    if (ch.length === 0) { return; }
    InputLog.recordUndo(ch); // [DEBUG-LOG]
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.IDLE) {
      this.insertText(ch);
    } else {
      this.handleDirectKana(ch);
    }
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

  private updateCandidates(): void {
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) {
      AppStorage.setOrCreate('candidates', [] as string[]);
      return;
    }
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
    const completions = PredictiveConversion.predict(target, KanaKanjiConverter.getLearned());
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
      this.inputClient?.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT)
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
        .catch((_e: Error) => {});
    }
  }

  handleDirectKana(kana: string): void {
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;

    if (mode === InputMode.ALPHANUMERIC) {
      this.commitPending();
      this.insertText(kana);
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
    this.lastDeletedChar = '';
    this.restoreStack = [];
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
      InputLog.recordBunsetsuPick(this.bSegs[this.bCur], candidates[index], index, candidates.length); // [DEBUG-LOG]
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

  handleUndo(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.BUNSETSU) {
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
      if (this.lastDeletedChar.length === 0) { return; }
      const composing = AppStorage.get<string>('composingText') ?? '';
      AppStorage.setOrCreate('composingText', composing + this.lastDeletedChar);
      this.lastDeletedChar = '';
      this.updateCandidates();
      return;
    }
    if (state === InputState.IDLE) {
      const ch = this.restoreStack.pop() ?? '';
      if (ch.length > 0) {
        this.inputClient?.insertText(ch);
        this.insertedBuffer.push(ch);
      }
    }
  }

  insertText(text: string): void {
    // Brackets used to auto-place the caret between the pair (「|」), but no
    // caret-move primitive worked reliably across the editors this IME runs in
    // -- moveCursor was a no-op on some, and the absolute-index selectByRange
    // overshot on others -- so the pair is now inserted plainly and the caret
    // stays after it, same as any other committed text.
    this.inputClient?.insertText(text);
    if (text.length > 0) {
      for (let i = 0; i < text.length; i++) {
        this.insertedBuffer.push(text[i]);
      }
      if (this.insertedBuffer.length > 50) {
        this.insertedBuffer = this.insertedBuffer.slice(-50);
      }
      this.restoreStack = [];
      KanaKanjiConverter.setLastCommitText(text);
    }
  }

  hideKeyboard(): void {
    this.kbController?.hide();
  }
}

// ---------- KeyboardController ----------

const USE_DICT_JSON: boolean = true;

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
    this.applyColorMode();
    this.initPanel();
    this.registerListeners();
    this.loadDictionary();
    this.loadGlobalDictionary();
    this.loadViterbiData();
  }

  // Re-resolves the live OS color mode via resourceManager (see
  // isDarkFromResourceManager's comment for why this, not context.config,
  // is what must be called anywhere isDark needs to be current -- including
  // repeatedly, from inputStart, not just once at onCreate).
  applyColorMode(): void {
    AppStorage.setOrCreate('isDark', isDarkFromResourceManager(this.context as ESObject));
  }

  // Applies the Configuration object handed directly to onConfigurationUpdate
  // (InputMethodExtAbility's own onConfigurationUpdate calls this), on the
  // rare OS versions/timings where that callback does fire for this
  // extension. isDarkFromConfiguration's comment covers why the object
  // handed to the callback (not a context.config re-read) is what's safe to
  // trust here.
  applyColorModeFrom(config: ESObject): void {
    AppStorage.setOrCreate('isDark', isDarkFromConfiguration(config));
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

  private loadDictionary(): void {
    if (!USE_DICT_JSON) { return; }
    this.context.resourceManager.getRawFileContent('dict.json')
      .then((data: Uint8Array) => {
        const decoder = new util.TextDecoder('utf-8');
        const text = decoder.decode(data);
        const dict = JSON.parse(text) as Record<string, string[]>;
        KanaKanjiConverter.loadDictionary(dict);
      })
      .catch((_e: Error) => { /* fall back to inline static dict */ });
  }

  // Build the Viterbi connection matrix from inline grammar rules (no external file).
  private loadViterbiData(): void {
    KanaKanjiConverter.initConnectionMatrix();
  }

  // Developer-curated dictionary bundled as rawfile/global_dict.json.
  // Edited via the hidden DevDict screen, exported, and committed to the repo;
  // applies to all users from the next patch. Highest conversion priority.
  private loadGlobalDictionary(): void {
    this.context.resourceManager.getRawFileContent('global_dict.json')
      .then((data: Uint8Array) => {
        const decoder = new util.TextDecoder('utf-8');
        const text = decoder.decode(data);
        const dict = JSON.parse(text) as Record<string, string[]>;
        KanaKanjiConverter.setGlobalDict(dict);
      })
      .catch((_e: Error) => { /* no global dict bundled yet */ });
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
    return Math.max(
      Math.floor(dis.height * 0.25),
      Math.min(contentPx, Math.floor(dis.height * maxFrac))
    );
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

  private resizePanel(): void {
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
