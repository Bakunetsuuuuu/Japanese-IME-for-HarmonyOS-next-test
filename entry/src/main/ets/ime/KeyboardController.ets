import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import display from '@ohos.display';
import util from '@ohos.util';
import dataPreferences from '@ohos.data.preferences';
import { JapaneseConverter, toKatakana } from './JapaneseConverter';
import { KanaKanjiConverter } from './KanaKanjiConverter';
import { UserDictStore } from './UserDictStore';

interface InputMethodSubtype {
  id: string;
  label?: string;
  locale?: string;
  mode?: string;
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
    this.reloadUserDict();
  }

  // Reload the user dictionary from disk (picks up words added in the main app).
  private reloadUserDict(): void {
    if (!this.imeContext) { return; }
    UserDictStore.load(this.imeContext, true)
      .then((dict: Record<string, string[]>) => {
        KanaKanjiConverter.setUserDict(dict);
      });
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
      const hasRealHit = fullFirst !== fullKatakana && fullFirst !== composing;

      if (hasRealHit) {
        candidates = fullCands;
      } else {
        // Multi-segment: auto-convert prefix, show variants for last segment.
        // Viterbi result goes to position 0; katakana is position 1.
        // Putting katakana at 0 unconditionally causes long natural Japanese
        // (e.g. きょうはいいてんきですね) to always show all-katakana first.
        const prefixText = segs.slice(0, -1)
          .map((s: string) => this.kanjiConverter.autoConvert(s))
          .join('');
        const lastSeg = segs[segs.length - 1];
        const lastCands = this.kanjiConverter.lookup(lastSeg);
        const segCands = lastCands.map((c: string) => prefixText + c);
        candidates = [];
        // Position 0: best Viterbi candidate
        if (segCands.length > 0) {
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

  insertText(text: string): void {
    if (InputHandler.BRACKET_PAIRS.has(text) && this.inputClient) {
      const client = this.inputClient;
      client.insertText(text).then(() => {
        client.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT).catch((_e: Error) => {});
      }).catch((_e: Error) => {});
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
    this.inputHandle.setContext(this.context);
    this.applyColorMode();
    this.initPanel();
    this.registerListeners();
    this.loadDictionary();
    this.loadGlobalDictionary();
    this.loadViterbiData();
  }

  // Detect system dark mode via the extension context configuration.
  // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1.
  applyColorMode(): void {
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

  // Load Viterbi cost data from rawfile/reading_cost.json and matrix.json.
  // Generated by tools/build_viterbi_dict.py from mecab-ipadic. If the files are
  // not bundled yet, segmentation silently falls back to the heuristic cost model.
  private loadViterbiData(): void {
    this.context.resourceManager.getRawFileContent('reading_cost.json')
      .then((data: Uint8Array) => {
        const decoder = new util.TextDecoder('utf-8');
        const text = decoder.decode(data);
        KanaKanjiConverter.setCostDict(JSON.parse(text) as Record<string, number[]>);
      })
      .catch((_e: Error) => { /* reading_cost.json not bundled yet — use heuristics */ });
    this.context.resourceManager.getRawFileContent('matrix.json')
      .then((data: Uint8Array) => {
        const decoder = new util.TextDecoder('utf-8');
        const text = decoder.decode(data);
        KanaKanjiConverter.setConnectionMatrix(JSON.parse(text) as number[][]);
      })
      .catch((_e: Error) => { /* matrix.json not bundled yet — edge costs = 0 */ });
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
    const MAX_KB_VP = 620;
    const screenVp = Math.min(fullVp, MAX_KB_VP);
    AppStorage.setOrCreate('isWideScreen', fullVp > MAX_KB_VP);
    AppStorage.setOrCreate('keyboardContentVp', screenVp);
    // 10-key rows: 4vp total H-padding + 9 gaps × 2vp = 22vp overhead
    const kwVp = Math.max(Math.floor((screenVp - 22) / 10), 24);
    const skwVp = Math.round(kwVp * 1.2);
    // Space bar = remaining after mode + 、 + 。 + enter + 4 gaps
    const spaceVp = Math.max(Math.floor(screenVp - 4 - 2 * skwVp - 2 * kwVp - 8), 60);
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

  private initPanel(): void {
    try {
      const dis = display.getDefaultDisplaySync();
      const isLandscape = dis.width > dis.height;
      // densityDPI/160 gives the px-per-vp ratio (e.g. 460dpi/160 = 2.875 on Pura 70)
      // content: 48vp bar + 5×44vp rows + 4×5vp gaps + 12vp padding = 300vp portrait
      const density = dis.densityDPI > 0 ? dis.densityDPI / 160 : 3.0;
      const contentPx = Math.ceil((isLandscape ? 310 : 360) * density);
      // clamp to 25–60% of screen height in case densityDPI returns an odd value
      const keyHeight = Math.max(
        Math.floor(dis.height * 0.25),
        Math.min(contentPx, Math.floor(dis.height * 0.60))
      );

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
      const density = dis.densityDPI > 0 ? dis.densityDPI / 160 : 3.0;
      const contentPx = Math.ceil((isLandscape ? 310 : 360) * density);
      const keyHeight = Math.max(
        Math.floor(dis.height * 0.25),
        Math.min(contentPx, Math.floor(dis.height * 0.60))
      );

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
        this.inputHandle.onInputStop();
        this.panel?.hide();
        this.onDestroy();
        this.context.destroy();
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
