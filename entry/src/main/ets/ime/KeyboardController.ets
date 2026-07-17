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
import { SettingsStore, KeyboardSettings } from './SettingsStore';
import { findPredictiveCompletion } from './PredictivePhrases';
import { registerJpFont } from '../components/JpFont';

interface InputMethodSubtype {
  id: string;
  label?: string;
  locale?: string;
  mode?: string;
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
  // 10-key rows: 4vp total H-padding + 9 gaps × 2vp = 22vp overhead. The
  // middle letter row (asdfghjkl + ー) and bottom row (shift + zxcvbnm +
  // backspace) also reuse this width; they aren't a fixed-width fit like
  // this row, just centered, so a different key count is harmless.
  const kwVp = Math.max(Math.floor((screenVp - 22) / 10), 24);
  const skwVp = Math.round(kwVp * 1.2);
  // Space bar = remaining after mode + 、 + 文節 + 。 + enter + 5 gaps
  // (文節 sits right after space, at the same special-key width as
  // mode/enter — the row would overflow if it were sized on top of them
  // instead of space giving up the room).
  const spaceVp = Math.max(Math.floor(screenVp - 4 - 3 * skwVp - 2 * kwVp - 10), 60);
  // Flick keys: 5 columns + 4 gaps × 3vp + 4vp H-padding
  const flickKwVp = Math.max(Math.floor((screenVp - 16) / 5), 60);
  AppStorage.setOrCreate('keyWidthVp', kwVp);
  AppStorage.setOrCreate('specialKeyWidthVp', skwVp);
  AppStorage.setOrCreate('spaceKeyWidthVp', spaceVp);
  AppStorage.setOrCreate('flickKeyWidthVp', flickKwVp);
  // Symbol panel: 8 columns + 7 gaps × 2vp + 6vp H-padding
  const symKwVp = Math.max(Math.floor((screenVp - 20) / 8), 36);
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
  private lastDeletedChar: string = '';
  private insertedBuffer: string[] = [];
  private restoreStack: string[] = [];
  private imeContext: InputMethodExtensionContext | undefined = undefined;
  private learningPrefs: dataPreferences.Preferences | undefined = undefined;
  private learningSaveTimer: number = -1;
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
      .catch((_e: Error) => {});
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
      .catch((_e: Error) => {});
    this.reloadUserDict();
    this.reloadSettings();
  }

  // Called whenever the user taps a symbol in SymbolView, so its "recent" tab
  // can be ranked by what this user actually reaches for instead of a fixed
  // guess at common punctuation.
  recordSymbolUse(sym: string): void {
    InputHandler.symbolFreq[sym] = (InputHandler.symbolFreq[sym] ?? 0) + 1;
    InputHandler.publishFrequentSymbols();
    clearTimeout(this.symbolSaveTimer);
    this.symbolSaveTimer = setTimeout(() => {
      const prefs = this.symbolPrefs;
      if (!prefs) { return; }
      prefs.put('v1', JSON.stringify(InputHandler.symbolFreq))
        .then(() => prefs.flush())
        .catch((_e: Error) => {});
    }, 2000);
  }

  private static publishFrequentSymbols(): void {
    const syms = Object.keys(InputHandler.symbolFreq);
    syms.sort((a: string, b: string) =>
      (InputHandler.symbolFreq[b] ?? 0) - (InputHandler.symbolFreq[a] ?? 0));
    AppStorage.setOrCreate('frequentSymbols', syms.slice(0, 24));
  }

  // Reload the user dictionary from disk (picks up words added in the main app).
  private reloadUserDict(): void {
    if (!this.imeContext) { return; }
    UserDictStore.load(this.imeContext, true)
      .then((dict: Record<string, string[]>) => {
        KanaKanjiConverter.setUserDict(dict);
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
        AppStorage.setOrCreate('keyboardLayout', s.keyboardLayout);
        AppStorage.setOrCreate('oneHandedMode', s.oneHandedMode);
        AppStorage.setOrCreate('oneHandedSide', s.oneHandedSide);
        AppStorage.setOrCreate('conversionEngine', s.conversionEngine);
        AppStorage.setOrCreate('themeMode', s.themeMode);
        this.applyConversionEngine(s.conversionEngine);
        this.applyThemeMode(s.themeMode);
      });
  }

  // Resolves isDark from a themeMode setting ('system'/'light'/'dark'),
  // reading the OS color mode itself only when actually needed ('system').
  // Mirrors KeyboardController.applyColorMode's system-read but is callable
  // from InputHandler, which has its own imeContext rather than sharing
  // KeyboardController's.
  private applyThemeMode(mode: string): void {
    if (mode === 'light') { AppStorage.setOrCreate('isDark', false); return; }
    if (mode === 'dark') { AppStorage.setOrCreate('isDark', true); return; }
    try {
      // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1.
      const cm = (this.imeContext?.config as ESObject)['colorMode'] as number;
      AppStorage.setOrCreate('isDark', cm === 0);
    } catch (_e) {
      AppStorage.setOrCreate('isDark', false);
    }
  }

  // Settings-panel テーマ control (外観 > テーマ) — pins the keyboard's own
  // theme independent of the OS color mode, or 'system' to go back to
  // following it. Applies immediately, same pattern as setKeyboardLayout.
  setThemeMode(mode: string): void {
    AppStorage.setOrCreate('themeMode', mode);
    this.applyThemeMode(mode);
    if (this.imeContext) {
      SettingsStore.saveThemeMode(this.imeContext, mode);
    }
  }

  // Track B (mozc-derived) is loaded lazily -- only the first time the
  // conversionEngine setting is actually 'mozc' -- so users who never touch
  // the toggle pay zero extra startup cost/memory for it. Safe to call
  // repeatedly: loadMozcEngine() is a no-op cost-wise once already loaded
  // (isMozcLoaded() short-circuits), and setEngine('custom') is always cheap.
  private applyConversionEngine(engine: string): void {
    if (engine !== 'mozc') {
      KanaKanjiConverter.setEngine('custom');
      return;
    }
    if (KanaKanjiConverter.isMozcLoaded()) {
      KanaKanjiConverter.setEngine('mozc');
      return;
    }
    if (!this.imeContext) { return; }
    const rm = this.imeContext.resourceManager;
    const decoder = new util.TextDecoder('utf-8');
    // Chained (not Promise.all + destructuring) to match this file's existing
    // getRawFileContent().then() style (see loadDictionary/loadGlobalDictionary
    // above) rather than introduce a new pattern.
    rm.getRawFileContent('mozc_dict.json')
      .then((dictData: Uint8Array) => {
        const dict = JSON.parse(decoder.decode(dictData)) as Record<string, string[]>;
        return rm.getRawFileContent('mozc_costs.json').then((costsData: Uint8Array) => {
          const costs = JSON.parse(decoder.decode(costsData)) as Record<string, (number | string)[][]>;
          return rm.getRawFileContent('mozc_matrix.json').then((matrixData: Uint8Array) => {
            const matrix = JSON.parse(decoder.decode(matrixData)) as MozcMatrixData;
            KanaKanjiConverter.loadMozcEngine(dict, costs, matrix);
            KanaKanjiConverter.setEngine('mozc');
            console.info('shuntiIME mozc engine loaded');
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

  // Switching the keyboard layout from the keyboard's own settings panel
  // takes effect immediately (same process, no reload round-trip needed) —
  // more reliable than the main-app toggle, which depends on the extension
  // picking the change back up on its own next reload.
  setKeyboardLayout(layout: string): void {
    AppStorage.setOrCreate('keyboardLayout', layout);
    if (this.imeContext) {
      SettingsStore.saveKeyboardLayout(this.imeContext, layout);
    }
  }

  // Same immediate-switch pattern as setKeyboardLayout above. applyConversionEngine
  // lazily fetches the mozc rawfiles the first time 'mozc' is actually selected.
  setConversionEngine(engine: string): void {
    AppStorage.setOrCreate('conversionEngine', engine);
    this.applyConversionEngine(engine);
    if (this.imeContext) {
      SettingsStore.saveConversionEngine(this.imeContext, engine);
    }
  }

  private saveLearning(): void {
    clearTimeout(this.learningSaveTimer);
    this.learningSaveTimer = setTimeout(() => {
      const prefs = this.learningPrefs;
      if (!prefs) { return; }
      prefs.put('v1', JSON.stringify(KanaKanjiConverter.getLearned()))
        .then(() => prefs.flush())
        .catch((_e: Error) => {});
    }, 2000);
  }

  onInputStart(
    kbCtrl: inputMethodEngine.KeyboardController,
    client: inputMethodEngine.InputClient
  ): void {
    this.kbController = kbCtrl;
    this.inputClient = client;
    this.converter.reset();
    this.reloadUserDict();
    this.reloadSettings();
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    this.lastDeletedChar = '';
    this.insertedBuffer = [];
    this.restoreStack = [];
    if (!AppStorage.has('inputMode')) {
      AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
    }
    this.refreshClipboardPreview();
  }

  onInputStop(): void {
    this.kbController = undefined;
    this.inputClient = undefined;
    this.converter.reset();
    this.lastDeletedChar = '';
    this.insertedBuffer = [];
    this.restoreStack = [];
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
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
      this.insertText(mode === InputMode.ALPHANUMERIC ? ' ' : '　');
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
      if (deleted.length > 0) { this.restoreStack.push(deleted); }
      this.inputClient?.deleteForward(1);
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
    }
  }

  commitRaw(): void {
    const composing = AppStorage.get<string>('composingText') ?? '';
    const pending = this.converter.flushPending();
    const all = composing + pending;
    if (all.length > 0) { this.insertText(all); }
    this.resetComposition();
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
      KanaKanjiConverter.recordChoice(composing, text);
      this.insertText(text);
      KanaKanjiConverter.addContext(text);
      this.saveLearning();
    }
    this.resetComposition();
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
      KanaKanjiConverter.recordChoice(composing, candidates[idx]);
      this.insertText(candidates[idx]);
      KanaKanjiConverter.addContext(candidates[idx]);
      this.resetComposition();
      this.saveLearning();
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

  private resetComposition(): void {
    this.converter.reset();
    this.bSegs = [];
    this.bChosen = [];
    this.bCur = 0;
    this.lastDeletedChar = '';
    this.insertedBuffer = [];
    this.restoreStack = [];
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('bunsetsuTexts', [] as string[]);
    AppStorage.setOrCreate('bunsetsuRaw', [] as string[]);
    AppStorage.setOrCreate('bunsetsuDisplay', '');
    AppStorage.setOrCreate('bunsetsuCurrent', 0);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
    this.refreshClipboardPreview();
  }

  // Kept in-memory only (AppStorage), not persisted to disk — clipboard
  // contents can be sensitive, and this app's privacy stance is to keep data
  // on-device only for as long as actually needed. History resets when the
  // keyboard extension process restarts.
  private static readonly MAX_CLIPBOARD_HISTORY = 8;

  private static setClipboardPreviewState(preview: string, isImage: boolean, isFile: boolean, uri: string): void {
    AppStorage.setOrCreate('clipboardPreview', preview);
    AppStorage.setOrCreate('clipboardIsImage', isImage);
    AppStorage.setOrCreate('clipboardIsFile', isFile);
    AppStorage.setOrCreate('clipboardUri', uri);
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
        InputHandler.setClipboardPreviewState(text, false, false, '');
        this.recordClipboardHistory(text);
        return;
      }
      // A file (from Files/a Gallery share sheet) shows up as a URI record.
      // A directly-copied image often carries BOTH a pixelmap record and a
      // URI record (many apps populate both), so check for a URI regardless
      // of isImage -- it's what lets pasteClipboard's drag-out path (see
      // KeyboardPage.ets) attach real content instead of just a preview
      // string. Preview it as a filename rather than the raw URI.
      const uri = data.getPrimaryUri();
      if (uri && uri.length > 0) {
        const preview = isImage ? '画像' : InputHandler.formatFileClipPreview(uri);
        InputHandler.setClipboardPreviewState(preview, isImage, true, uri);
        return;
      }
      if (isImage) {
        // Raw pixels only, no URI to point at (e.g. some apps' plain
        // "コピー" on an image) -- preview-only, same as before; see
        // pasteClipboard()'s comment for why this can't go further.
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

  // Returns false (and pastes nothing) for image/file clipboard contents.
  // No input method on any platform can inject non-text content into an
  // arbitrary third-party app's text field through the standard IME
  // text-commit API (insertText here) -- that's not a bug to fix in this
  // app, it's what every keyboard app is limited to. Twitter/Discord/etc.
  // pasting an image already works today via their OWN paste UI (long-press
  // → 貼り付け, or Ctrl+V), which reads the system clipboard directly and
  // doesn't go through the keyboard at all. The caller uses this return
  // value to tell the user that, instead of silently doing nothing.
  //
  // When a real file/image URI is available (clipboardUri, set by
  // refreshClipboardPreview above), KeyboardPage.ets's clipboard chip offers
  // a SEPARATE drag-out path via ArkUI's system drag-and-drop
  // (unifiedDataChannel/DragEvent), which unlike insertText() can carry
  // arbitrary content -- dragging the chip onto a compatible drop target
  // (e.g. Twitter/LINE/Discord's own attachment/input area) can work where
  // a tap-to-paste never could. This is best-effort and unverified: it
  // depends on (a) this keyboard panel being allowed to originate a system
  // drag at all, and (b) the target app's field actually implementing
  // onDrop for the dragged type -- neither is guaranteed, and there's no
  // way to detect either failure ahead of time, so it may just silently not
  // work in some apps. Tap-to-paste keeps failing the same documented way.
  pasteClipboard(): boolean {
    const isImage = AppStorage.get<boolean>('clipboardIsImage') ?? false;
    const isFile = AppStorage.get<boolean>('clipboardIsFile') ?? false;
    if (isImage || isFile) {
      return false;
    }
    const text = AppStorage.get<string>('clipboardPreview') ?? '';
    if (text.length === 0) {
      return false;
    }
    this.insertText(text);
    this.refreshClipboardPreview();
    return true;
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

  // Opens this project's GitHub repository (README, source code, and the
  // GitHub Sponsors link at the top of the README) in the main app's own
  // in-app browser (pages/WebViewPage, an ArkWeb view) rather than handing
  // off to the system's "choose a browser" chooser -- routed through
  // EntryAbility's want parameters (see EntryAbility.ets/Index.ets) since a
  // URL want here would open the system browser chooser instead.
  // Deliberately routed through GitHub rather than a payment link embedded
  // directly in the app -- keeps any donation ask entirely outside the
  // app binary/store listing, avoiding AppGallery review ambiguity around
  // in-app payment/donation solicitation.
  openGithubRepo(): boolean {
    if (!this.imeContext) { return false; }
    const want: Want = {
      bundleName: 'com.shunti.japaneseime',
      abilityName: 'EntryAbility',
      parameters: {
        openUrl: 'https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next',
        openTitle: 'GitHub',
      },
    };
    this.imeContext.startAbility(want)
      .catch((err: Error) => console.error('shuntiIME openGithubRepo error', JSON.stringify(err)));
    return true;
  }

  private updateCandidates(): void {
    const composing = AppStorage.get<string>('composingText') ?? '';
    if (composing.length === 0) {
      AppStorage.setOrCreate('candidates', [] as string[]);
      return;
    }

    const fullKatakana = KanaKanjiConverter.toKatakana(composing);
    const segs = this.kanjiConverter.segment(composing);
    let candidates: string[];

    if (segs.length <= 1) {
      candidates = this.kanjiConverter.lookup(composing);
    } else {
      // Try full-text lookup first. If it returns a real dictionary hit
      // (not just the katakana/kana fallback), use it — this prevents
      // Viterbi mis-segmentation from producing garbage like 足素ト for あしすと.
      const fullCands = this.kanjiConverter.lookup(composing);
      const fullFirst = fullCands[0];
      // A dict-authored loanword (こんびに→コンビニ) has fullFirst === the
      // auto-katakana, so the plain fullFirst!==fullKatakana test would reject
      // it and fall to segmentation (こんび+に → garbage). Treat a whole
      // reading that IS a dictionary word as a real hit regardless.
      const hasRealHit = (fullFirst !== fullKatakana && fullFirst !== composing) ||
        KanaKanjiConverter.isDictionaryWord(composing);

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
        const prefixParts = segs.slice(0, -1).map((s: string) => this.kanjiConverter.autoConvert(s));
        const hasSymbolPrefix = prefixParts.some((p: string) => KanaKanjiConverter.isSymbolOnly(p));
        const prefixText = hasSymbolPrefix ? '' : prefixParts.join('');
        const lastSeg = segs[segs.length - 1];
        const lastCands = this.kanjiConverter.lookup(lastSeg);
        const segCands = hasSymbolPrefix ? [] : lastCands.map((c: string) => prefixText + c);
        candidates = [];
        if (hasSymbolPrefix) {
          // No usable kanji join — plain kana leads, same as the
          // segmentJoinFallback bail-out for single-lookup composing text.
          candidates.push(composing);
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
        if (!candidates.includes(composing)) { candidates.push(composing); }
      }
    }

    // 自動区切り変更: a second candidate from a differently-segmented parse
    // of the same reading (へんかんせいど's single whole-compound entry
    // 変換精度 vs the へんかん+せいど split's 返還制度) — inserted right after
    // the primary pick, not replacing it.
    const altSeg = this.kanjiConverter.findAlternateSegmentation(composing);
    if (altSeg !== null && !candidates.includes(altSeg)) {
      candidates.splice(1, 0, altSeg);
    }

    // Predictive completion: once enough of a known common phrase's reading
    // has been typed to be unambiguous, lead with the whole thing rather than
    // making the user type out a full greeting/set phrase.
    const predictive = findPredictiveCompletion(composing);
    if (predictive !== null && !candidates.includes(predictive)) {
      candidates = [predictive, ...candidates];
    }

    AppStorage.setOrCreate('candidates', candidates);
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
    if (state === InputState.BUNSETSU) {
      this.selectBunsetsuSegment(this.bCur - 1);
    } else {
      this.inputClient?.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT)
        .catch((_e: Error) => {});
    }
  }

  handleCursorRight(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.BUNSETSU) {
      this.selectBunsetsuSegment(this.bCur + 1);
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
    this.bChosen = this.bSegs.map((seg: string) => this.kanjiConverter.autoConvert(seg));
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
    const cands = this.kanjiConverter.lookup(this.bSegs[this.bCur]);
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

  private static readonly BRACKET_PAIRS: Set<string> =
    new Set(['()', '（）', '「」', '[]', '{}', '【】', '『』', '〔〕', '［］', '｛｝']);

  // Move the caret one position left after inserting a bracket pair so it lands
  // between them. Read the caret's absolute index (getTextIndexAtCursor resolves
  // after the editor has applied the just-inserted pair, since requests to the
  // editor are processed in order) and collapse the selection one code unit
  // earlier via selectByRange — timing-independent and exact. Fall back to a
  // relative moveCursor for editors that reject range selection.
  private placeCaretBetweenBrackets(client: inputMethodEngine.InputClient): void {
    const moveBack = (delayed: boolean): void => {
      const step = (): void => {
        client.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT)
          .catch((e: Error) => console.error('shuntiIME moveCursor(bracket) failed', JSON.stringify(e)));
      };
      if (delayed) { setTimeout(step, 16); } else { step(); }
    };
    client.getTextIndexAtCursor().then((idx: number) => {
      const target: number = idx > 0 ? idx - 1 : 0;
      client.selectByRange({ start: target, end: target }).catch((e: Error) => {
        console.error('shuntiIME selectByRange(bracket) failed', JSON.stringify(e));
        moveBack(false);
      });
    }).catch((e: Error) => {
      console.error('shuntiIME getTextIndexAtCursor(bracket) failed', JSON.stringify(e));
      moveBack(true);
    });
  }

  insertText(text: string): void {
    if (InputHandler.BRACKET_PAIRS.has(text) && this.inputClient) {
      const client = this.inputClient;
      client.insertText(text).then(() => {
        this.placeCaretBetweenBrackets(client);
      }).catch((e: Error) => console.error('shuntiIME insertText(bracket) failed', JSON.stringify(e)));
    } else {
      this.inputClient?.insertText(text);
    }
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
    registerJpFont();
    this.inputHandle.setContext(this.context);
    this.applyColorMode();
    this.initPanel();
    this.registerListeners();
    this.loadDictionary();
    this.loadGlobalDictionary();
    this.loadViterbiData();
  }

  // Detect system dark mode via the extension context configuration —
  // unless the user has pinned an explicit テーマ (themeMode 'light'/'dark'
  // in the settings panel), in which case that wins over the OS setting
  // until they switch back to 'system'.
  // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1.
  applyColorMode(): void {
    const mode = AppStorage.get<string>('themeMode') ?? 'system';
    if (mode === 'light') { AppStorage.setOrCreate('isDark', false); return; }
    if (mode === 'dark') { AppStorage.setOrCreate('isDark', true); return; }
    try {
      const cm = (this.context.config as ESObject)['colorMode'] as number;
      AppStorage.setOrCreate('isDark', cm === 0);
    } catch (_e) {
      AppStorage.setOrCreate('isDark', false);
    }
  }

  onDestroy(): void {
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
