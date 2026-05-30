import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import display from '@ohos.display';
import { JapaneseConverter, toKatakana } from './JapaneseConverter';
import { KanaKanjiConverter } from './KanaKanjiConverter';

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
}

export const enum InputMode {
  HIRAGANA = 'HIRAGANA',
  KATAKANA = 'KATAKANA',
  ALPHANUMERIC = 'ALPHANUMERIC',
}

const IMEAbility = inputMethodEngine.getInputMethodAbility();

// ---------- InputHandler ----------

export class InputHandler {
  private static _instance: InputHandler | undefined = undefined;
  private kbController: inputMethodEngine.KeyboardController | undefined;
  private inputClient: inputMethodEngine.InputClient | undefined;
  private converter: JapaneseConverter = new JapaneseConverter();
  private kanjiConverter: KanaKanjiConverter = new KanaKanjiConverter();

  static getInstance(): InputHandler {
    if (!InputHandler._instance) {
      InputHandler._instance = new InputHandler();
    }
    return InputHandler._instance;
  }

  onInputStart(
    kbCtrl: inputMethodEngine.KeyboardController,
    client: inputMethodEngine.InputClient
  ): void {
    this.kbController = kbCtrl;
    this.inputClient = client;
    this.converter.reset();
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
    if (!AppStorage.has('inputMode')) {
      AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
    }
  }

  onInputStop(): void {
    this.kbController = undefined;
    this.inputClient = undefined;
    this.converter.reset();
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
      this.inputClient?.deleteForward(1);
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
          AppStorage.setOrCreate('composingText', composing.slice(0, -1));
        }
      }

      const composing = AppStorage.get<string>('composingText') ?? '';
      const newPending = AppStorage.get<string>('pendingRomaji') ?? '';
      if (composing.length === 0 && newPending.length === 0) {
        AppStorage.setOrCreate('inputState', InputState.IDLE);
      }
    }
  }

  handleEnterKey(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state !== InputState.IDLE) {
      this.commitTopCandidate();
    } else {
      this.inputClient?.sendKeyFunction(0);
    }
  }

  commitCandidate(index: number): void {
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    const text = index < candidates.length ? candidates[index] : '';
    if (text.length > 0) { this.insertText(text); }
    this.resetComposition();
  }

  commitTopCandidate(): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.SELECTING) {
      const candidates = AppStorage.get<string[]>('candidates') ?? [];
      const idx = AppStorage.get<number>('selectedCandidateIndex') ?? 0;
      const text = candidates.length > 0 ? candidates[idx] : '';
      if (text.length > 0) { this.insertText(text); }
      this.resetComposition();
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
    AppStorage.setOrCreate('composingText', '');
    AppStorage.setOrCreate('pendingRomaji', '');
    AppStorage.setOrCreate('candidates', [] as string[]);
    AppStorage.setOrCreate('selectedCandidateIndex', 0);
    AppStorage.setOrCreate('inputState', InputState.IDLE);
  }

  insertText(text: string): void {
    this.inputClient?.insertText(text);
  }

  hideKeyboard(): void {
    this.kbController?.hide();
  }
}

// ---------- KeyboardController ----------

export class KeyboardController {
  private panel: inputMethodEngine.Panel | undefined;
  private inputHandle: InputHandler = InputHandler.getInstance();
  private kbDelegate: inputMethodEngine.KeyboardDelegate | undefined;

  private context: InputMethodExtensionContext;

  constructor(context: InputMethodExtensionContext) {
    this.context = context;
  }

  onCreate(): void {
    this.initPanel();
    this.registerListeners();
  }

  onDestroy(): void {
    this.unregisterListeners();
    if (this.panel) {
      IMEAbility.destroyPanel(this.panel);
      this.panel = undefined;
    }
  }

  private initPanel(): void {
    const dis = display.getDefaultDisplaySync();
    const isLandscape = dis.width > dis.height;
    // densityDPI/160 gives the px-per-vp ratio (e.g. 460dpi/160 = 2.875 on Pura 70)
    // content: 48vp bar + 5×44vp rows + 4×5vp gaps + 12vp padding = 300vp portrait
    const density = dis.densityDPI / 160;
    const contentPx = Math.ceil((isLandscape ? 264 : 300) * density);
    // clamp to 25–60% of screen height in case densityDPI returns an odd value
    const keyHeight = Math.max(
      Math.floor(dis.height * 0.25),
      Math.min(contentPx, Math.floor(dis.height * 0.60))
    );

    AppStorage.setOrCreate('isLandscape', isLandscape);
    AppStorage.setOrCreate('displayWidth', dis.width);
    AppStorage.setOrCreate('keyboardHeight', keyHeight);

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
  }

  private resizePanel(): void {
    const dis = display.getDefaultDisplaySync();
    const isLandscape = dis.width > dis.height;
    const density = dis.densityDPI / 160;
    const contentPx = Math.ceil((isLandscape ? 264 : 300) * density);
    const keyHeight = Math.max(
      Math.floor(dis.height * 0.25),
      Math.min(contentPx, Math.floor(dis.height * 0.60))
    );

    AppStorage.setOrCreate('isLandscape', isLandscape);
    AppStorage.setOrCreate('displayWidth', dis.width);
    AppStorage.setOrCreate('keyboardHeight', keyHeight);

    this.panel?.resize(dis.width, keyHeight)
      .then(() => this.panel?.moveTo(0, dis.height - keyHeight));
  }

  private registerListeners(): void {
    display.on('change', () => this.resizePanel());

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

    this.kbDelegate = inputMethodEngine.getKeyboardDelegate();
    this.kbDelegate.on('keyDown', (_keyEvent: inputMethodEngine.KeyEvent) => {
      return false;
    });
  }

  private unregisterListeners(): void {
    display.off('change');
    this.kbDelegate?.off('keyDown');
  }
}
