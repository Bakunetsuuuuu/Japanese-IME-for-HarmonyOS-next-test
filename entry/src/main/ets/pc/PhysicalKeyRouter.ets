// PCモードの物理キーの処理。KeyboardDelegate.on('keyEvent') から呼ぶ。
//
// 使い勝手は Windows の IME (Microsoft IME の既定、US 配列) に合わせる。
//   ・英字モード (A) は直接入力: IME の切り替えキー以外はすべてアプリへ素通し
//   ・Ctrl / Alt / Win との同時押しはアプリのショートカット: 入力中なら確定してから素通し
//   ・何も入力していないときの Enter・BackSpace・矢印・Tab・Esc などは素通し
//
// keyEvent は「消費したか」をその場で返す決まりなので、判断は今の状態と
// キーの種類だけで同期で行う。変換そのもの (InputHandler) も同期で状態を
// 書き換えるので、打鍵の順番が入れ替わることは無い (AI 変換の結果は後から
// 届くが、届いた結果は候補を差し替えるだけで状態は進めない)。
//
// keyDown を消費したキーは keyUp も必ず消費する (片方だけアプリに届くと、
// 押しっぱなし・離しっぱなしのキーがアプリ側に残る)。
import type { KeyEvent as InputKeyEvent } from '@ohos.multimodalInput.keyEvent';
import { KeyCode } from '@kit.InputKit';
import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
import { JapaneseConverter, toKatakana } from '../ime/JapaneseConverter';
import { KeyMap, toJapaneseInputChar, toFullWidth, toHalfWidthKatakana, toHiragana, kanaToRomaji } from './KeyMap';
import { CANDIDATE_PAGE_SIZE } from './PcStyle';

// @ohos.multimodalInput.keyEvent の Action
const ACTION_CANCEL: number = 0;
const ACTION_DOWN: number = 1;
const ACTION_UP: number = 2;

// PhysicalKeyRouter が PcModeController に頼むこと
export interface PcKeyHost {
  isPcActive(): boolean;
  // PCモードが入っていないときに文字キーが届いた: 物理キーボードからなら PCモードに入る。
  // 入ったら true (その打鍵はそのまま PCモードで処理する)
  activateFromKey(deviceId: number): boolean;
  // 打鍵で状態が変わった (候補ウィンドウ・言語バーを合わせ直す)
  onImeStateChanged(): void;
  // 絵文字・設定を開いているときに文字を打った (閉じて候補ウィンドウに戻す)
  closePopupForTyping(): void;
  toggleImeOnOff(): void;
  setImeOn(on: boolean): void;
}

// 押していても IME が何もしない修飾キー (単独の押下はアプリへ)
const MODIFIER_KEYS: Set<number> = new Set<number>([
  KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_SHIFT_RIGHT,
  KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_CTRL_RIGHT,
  KeyCode.KEYCODE_ALT_LEFT, KeyCode.KEYCODE_ALT_RIGHT,
  KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_META_RIGHT,
  KeyCode.KEYCODE_CAPS_LOCK, KeyCode.KEYCODE_NUM_LOCK, KeyCode.KEYCODE_SCROLL_LOCK,
  KeyCode.KEYCODE_FN, KeyCode.KEYCODE_FUNCTION, KeyCode.KEYCODE_SYM,
]);

const CTRL_KEYS: number[] = [KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_CTRL_RIGHT];
const ALT_KEYS: number[] = [KeyCode.KEYCODE_ALT_LEFT, KeyCode.KEYCODE_ALT_RIGHT];
const META_KEYS: number[] = [KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_META_RIGHT];
const SHIFT_KEYS: number[] = [KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_SHIFT_RIGHT];

// 入力中でも何もしないで飲み込むキー (アプリに渡すと、確定前の文字の外で
// カーソルが動いたり文字が消えたりする)
const SWALLOW_WHILE_BUSY: Set<number> = new Set<number>([
  KeyCode.KEYCODE_FORWARD_DEL, KeyCode.KEYCODE_MOVE_HOME, KeyCode.KEYCODE_MOVE_END,
  KeyCode.KEYCODE_INSERT,
]);

interface Modifiers {
  ctrl: boolean;
  alt: boolean;
  meta: boolean;
  shift: boolean;
}

export class PhysicalKeyRouter {
  private handler: InputHandler;
  private host: PcKeyHost;
  // keyDown を消費したキー。対になる keyUp も消費する
  private consumed: Set<number> = new Set<number>();
  // 今の読みを打ったキーそのまま (F9・F10 用)。読みが空になったら捨てる
  private rawKeys: string = '';
  // F9・F10 を続けて押した回数 (押すたびに 小文字 → 大文字 → 先頭だけ大文字)
  private lastFKey: number = -1;
  private fKeyRepeat: number = 0;

  constructor(handler: InputHandler, host: PcKeyHost) {
    this.handler = handler;
    this.host = host;
  }

  // 入力欄が変わった・PCモードが切れた: 押したままのキーの記録も捨てる
  // (keyUp を消費し損ねても、次の欄で無関係なキーを飲み込まないように)
  reset(): void {
    this.consumed.clear();
    this.rawKeys = '';
    this.lastFKey = -1;
    this.fKeyRepeat = 0;
  }

  onKeyEvent(e: InputKeyEvent): boolean {
    const code: number = e.key.code;
    const action: number = e.action;
    if (action === ACTION_UP || action === ACTION_CANCEL) {
      if (this.consumed.has(code)) {
        this.consumed.delete(code);
        return true;
      }
      return false;
    }
    if (action !== ACTION_DOWN) { return false; }
    if (!this.host.isPcActive()) {
      // 自動の判定が拾えなかった物理キーボード: 文字キーが届いたら調べ直す
      const printable = KeyMap.isLetter(code) || KeyMap.digitOf(code, false) >= 0;
      if (!printable || !this.host.activateFromKey(e.deviceId)) { return false; }
    }
    let consume = false;
    try {
      consume = this.handleDown(e, code);
    } catch (err) {
      console.error('shuntiIME PhysicalKeyRouter error', JSON.stringify(err));
      consume = false;
    }
    if (consume) {
      this.consumed.add(code);
      this.handler.refreshPreview();
      this.host.onImeStateChanged();
    } else {
      this.consumed.delete(code);
    }
    return consume;
  }

  private static modifiers(e: InputKeyEvent): Modifiers {
    const pressed = new Set<number>();
    for (const k of e.keys ?? []) { pressed.add(k.code); }
    const held = (codes: number[]): boolean => codes.some((c: number) => pressed.has(c));
    return {
      ctrl: e.ctrlKey === true || held(CTRL_KEYS),
      alt: e.altKey === true || held(ALT_KEYS),
      meta: e.logoKey === true || held(META_KEYS),
      shift: e.shiftKey === true || held(SHIFT_KEYS),
    };
  }

  private handleDown(e: InputKeyEvent, code: number): boolean {
    if (MODIFIER_KEYS.has(code)) { return false; }
    const mods = PhysicalKeyRouter.modifiers(e);
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    const busy = state !== InputState.IDLE;
    if (code !== KeyCode.KEYCODE_F9 && code !== KeyCode.KEYCODE_F10) {
      this.lastFKey = -1;
      this.fKeyRepeat = 0;
    }

    // IME のオン・オフ: 半角/全角キー、Alt+` (US 配列の Windows の既定)
    if (code === KeyCode.KEYCODE_ZENKAKU_HANKAKU
        || (mods.alt && !mods.ctrl && !mods.meta && code === KeyCode.KEYCODE_GRAVE)) {
      this.host.toggleImeOnOff();
      return true;
    }
    if (code === KeyCode.KEYCODE_KATAKANA_HIRAGANA || code === KeyCode.KEYCODE_HIRAGANA) {
      this.host.setImeOn(true);
      return true;
    }

    // Ctrl・Alt・Win との同時押しはアプリのショートカット。入力中なら確定してから素通し。
    // 確定は入力欄の表示 (setPreviewTextSync) を確定する同期の呼び出しなので、
    // ショートカットより先に入力欄へ反映される
    if (mods.ctrl || mods.alt || mods.meta) {
      if (busy) {
        this.handler.commitComposition();
        this.rawKeys = '';
        this.host.onImeStateChanged();
      }
      return false;
    }

    if (mode === InputMode.ALPHANUMERIC) {
      // 直接入力。変換キーだけは IME をオンにする
      if (code === KeyCode.KEYCODE_HENKAN) {
        this.host.setImeOn(true);
        return true;
      }
      return false;
    }

    const ch = KeyMap.charFor(code, mods.shift, e.capsLock === true, e.numLock !== false, e.unicodeChar ?? 0);
    if (state === InputState.IDLE) {
      return this.onIdle(code, ch, mods);
    }
    if (state === InputState.COMPOSING) {
      return this.onComposing(code, ch, mods);
    }
    if (state === InputState.SELECTING) {
      return this.onSelecting(code, ch, mods, e.numLock !== false);
    }
    if (state === InputState.BUNSETSU) {
      return this.onBunsetsu(code, ch, mods, e.numLock !== false);
    }
    return false;
  }

  // ---------- 何も入力していないとき ----------

  private onIdle(code: number, ch: string, mods: Modifiers): boolean {
    if (code === KeyCode.KEYCODE_SPACE) {
      // ひらがなモードの空白は全角 (Windows の既定「入力モードに従う」)。Shift+空白は半角
      if (mods.shift) {
        this.handler.insertText(' ');
      } else {
        this.handler.handleSpaceKey();
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_HENKAN) {
      // 再変換は未対応。アプリにも渡さない (変換キーにアプリ側の意味は無い)
      return true;
    }
    if (code === KeyCode.KEYCODE_MUHENKAN) {
      return true;
    }
    if (ch.length > 0) {
      this.rawKeys = '';
      this.typeChar(code, ch);
      return true;
    }
    return false;
  }

  // ---------- 読みを打っているとき (COMPOSING) ----------

  private onComposing(code: number, ch: string, mods: Modifiers): boolean {
    switch (code) {
      case KeyCode.KEYCODE_SPACE:
      case KeyCode.KEYCODE_HENKAN:
      case KeyCode.KEYCODE_DPAD_DOWN:
      case KeyCode.KEYCODE_TAB:
        this.handler.handleSpaceKey();
        return true;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        this.handler.handleEnterKey();
        this.rawKeys = '';
        return true;
      case KeyCode.KEYCODE_DEL:
        this.handler.handleBackspace();
        return true;
      case KeyCode.KEYCODE_ESCAPE:
        this.handler.cancelComposition();
        this.rawKeys = '';
        return true;
      case KeyCode.KEYCODE_DPAD_LEFT:
        // Shift+← で変換する範囲を縮める (Windows の IME と同じ)。読みの中のカーソル移動は
        // 無いので、Shift 無しは飲み込むだけ (以前は Shift 無しでも範囲を縮めていて、
        // カーソルを動かすつもりで押すと先頭の数文字しか変換されなくなっていた)
        if (mods.shift) { this.handler.handleCursorLeft(); }
        return true;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        if (mods.shift) { this.handler.handleCursorRight(); }
        return true;
      case KeyCode.KEYCODE_DPAD_UP:
      case KeyCode.KEYCODE_PAGE_UP:
      case KeyCode.KEYCODE_PAGE_DOWN:
        return true;
      case KeyCode.KEYCODE_MUHENKAN:
        this.fixedConversion(KeyCode.KEYCODE_F7);
        return true;
      default:
        break;
    }
    if (this.isConversionFKey(code)) {
      this.fixedConversion(code);
      return true;
    }
    if (SWALLOW_WHILE_BUSY.has(code)) { return true; }
    if (ch.length > 0) {
      this.typeChar(code, ch);
      return true;
    }
    return this.commitAndPass();
  }

  // ---------- 変換中 (SELECTING) ----------

  private onSelecting(code: number, ch: string, mods: Modifiers, numLock: boolean): boolean {
    switch (code) {
      case KeyCode.KEYCODE_SPACE:
        if (mods.shift) {
          this.handler.moveCandidateSelection(-1);
        } else {
          this.handler.handleSpaceKey();
        }
        return true;
      case KeyCode.KEYCODE_HENKAN:
      case KeyCode.KEYCODE_DPAD_DOWN:
        this.handler.moveCandidateSelection(1);
        return true;
      case KeyCode.KEYCODE_TAB:
        this.handler.moveCandidateSelection(mods.shift ? -1 : 1);
        return true;
      case KeyCode.KEYCODE_DPAD_UP:
        this.handler.moveCandidateSelection(-1);
        return true;
      case KeyCode.KEYCODE_PAGE_DOWN:
        this.movePage(1);
        return true;
      case KeyCode.KEYCODE_PAGE_UP:
        this.movePage(-1);
        return true;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        this.handler.handleEnterKey();
        this.rawKeys = '';
        return true;
      case KeyCode.KEYCODE_ESCAPE:
      case KeyCode.KEYCODE_DEL:
        // 読みに戻る (ソフトキーボードの handleBackspace は候補を空にするが、
        // PCモードでは候補ウィンドウが消えてしまうので、打っている間の候補を出し直す)
        this.handler.returnToComposing();
        return true;
      case KeyCode.KEYCODE_DPAD_LEFT:
        if (mods.shift) {
          this.handler.handleCursorLeft();
        } else {
          this.handler.beginBunsetsuEdit(true);
        }
        return true;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        if (mods.shift) {
          this.handler.handleCursorRight();
        } else {
          this.handler.beginBunsetsuEdit(false);
        }
        return true;
      case KeyCode.KEYCODE_MUHENKAN:
        this.fixedConversion(KeyCode.KEYCODE_F7);
        return true;
      default:
        break;
    }
    if (this.selectByNumber(code, numLock)) { return true; }
    if (this.isConversionFKey(code)) {
      this.fixedConversion(code);
      return true;
    }
    if (SWALLOW_WHILE_BUSY.has(code)) { return true; }
    if (ch.length > 0) {
      // 選んでいる候補で確定して、次の読みを打ち始める (handleKeyPress が確定する)
      this.rawKeys = '';
      this.typeChar(code, ch);
      return true;
    }
    return this.commitAndPass();
  }

  // ---------- 文節ごとに選び直しているとき (BUNSETSU) ----------

  private onBunsetsu(code: number, ch: string, mods: Modifiers, numLock: boolean): boolean {
    switch (code) {
      case KeyCode.KEYCODE_DPAD_LEFT:
        // Shift+←→ (文節の区切りを動かす) は未対応。飲み込むだけ
        if (!mods.shift) { this.handler.handleCursorLeft(); }
        return true;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        if (!mods.shift) { this.handler.handleCursorRight(); }
        return true;
      case KeyCode.KEYCODE_SPACE:
        this.handler.moveCandidateSelection(mods.shift ? -1 : 1);
        return true;
      case KeyCode.KEYCODE_HENKAN:
      case KeyCode.KEYCODE_DPAD_DOWN:
        this.handler.moveCandidateSelection(1);
        return true;
      case KeyCode.KEYCODE_TAB:
        this.handler.moveCandidateSelection(mods.shift ? -1 : 1);
        return true;
      case KeyCode.KEYCODE_DPAD_UP:
        this.handler.moveCandidateSelection(-1);
        return true;
      case KeyCode.KEYCODE_PAGE_DOWN:
        this.movePage(1);
        return true;
      case KeyCode.KEYCODE_PAGE_UP:
        this.movePage(-1);
        return true;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        this.handler.handleEnterKey();
        this.rawKeys = '';
        return true;
      case KeyCode.KEYCODE_ESCAPE:
      case KeyCode.KEYCODE_DEL:
        // 文節の編集をやめて読みに戻る
        this.handler.handleBackspace();
        return true;
      case KeyCode.KEYCODE_MUHENKAN:
        this.fixedConversion(KeyCode.KEYCODE_F7);
        return true;
      default:
        break;
    }
    if (this.selectByNumber(code, numLock)) { return true; }
    if (this.isConversionFKey(code)) {
      this.fixedConversion(code);
      return true;
    }
    if (SWALLOW_WHILE_BUSY.has(code)) { return true; }
    if (ch.length > 0) {
      // handleKeyPress は文節の編集中に確定しないので、先に全部確定する
      this.handler.commitComposition();
      this.rawKeys = '';
      this.typeChar(code, ch);
      return true;
    }
    return this.commitAndPass();
  }

  // ---------- 共通 ----------

  private typeChar(code: number, ch: string): void {
    this.host.closePopupForTyping();
    // テンキーは Windows の既定 (常に半角) のまま。それ以外の記号・数字は和文の字に
    const out = KeyMap.isNumpad(code) ? ch : toJapaneseInputChar(ch);
    this.rawKeys += ch;
    this.handler.handleKeyPress(out);
  }

  // IME が扱わないキー (F1〜F5・F11・F12・メニューキーなど) を、入力中のものを
  // 確定してからアプリへ渡す
  private commitAndPass(): boolean {
    this.handler.commitComposition();
    this.rawKeys = '';
    this.host.onImeStateChanged();
    return false;
  }

  private movePage(deltaPages: number): void {
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    if (candidates.length === 0) { return; }
    const cur = AppStorage.get<number>('selectedCandidateIndex') ?? 0;
    const page = Math.floor(cur / CANDIDATE_PAGE_SIZE) + deltaPages;
    const lastPage = Math.floor((candidates.length - 1) / CANDIDATE_PAGE_SIZE);
    const target = Math.max(0, Math.min(lastPage, page));
    this.handler.setCandidateSelection(target * CANDIDATE_PAGE_SIZE);
  }

  // 1〜9: 今のページの n 番目の候補で確定する (文節の編集中はその文節を決めて次の文節へ)
  private selectByNumber(code: number, numLock: boolean): boolean {
    const d = KeyMap.digitOf(code, numLock);
    if (d < 0) { return false; }
    if (d === 0) { return true; }
    const candidates = AppStorage.get<string[]>('candidates') ?? [];
    const cur = AppStorage.get<number>('selectedCandidateIndex') ?? 0;
    const index = Math.floor(cur / CANDIDATE_PAGE_SIZE) * CANDIDATE_PAGE_SIZE + d - 1;
    if (index < candidates.length) {
      this.handler.commitCandidate(index);
      const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
      if (state === InputState.IDLE) { this.rawKeys = ''; }
    }
    return true;
  }

  private isConversionFKey(code: number): boolean {
    return code === KeyCode.KEYCODE_F6 || code === KeyCode.KEYCODE_F7 || code === KeyCode.KEYCODE_F8
      || code === KeyCode.KEYCODE_F9 || code === KeyCode.KEYCODE_F10;
  }

  // F6 ひらがな / F7 全角カタカナ / F8 半角カタカナ / F9 全角英数 / F10 半角英数
  private fixedConversion(code: number): void {
    if (code === this.lastFKey) {
      this.fKeyRepeat++;
    } else {
      this.lastFKey = code;
      this.fKeyRepeat = 0;
    }
    const repeat = this.fKeyRepeat;
    this.handler.presentFixedConversion((reading: string): string => {
      switch (code) {
        case KeyCode.KEYCODE_F6:
          return toHiragana(reading);
        case KeyCode.KEYCODE_F7:
          return toKatakana(toHiragana(reading));
        case KeyCode.KEYCODE_F8:
          return toHalfWidthKatakana(toKatakana(toHiragana(reading)));
        case KeyCode.KEYCODE_F9:
          return toFullWidth(PhysicalKeyRouter.letterCase(this.romajiFor(reading), repeat));
        case KeyCode.KEYCODE_F10:
          return PhysicalKeyRouter.letterCase(this.romajiFor(reading), repeat);
        default:
          return reading;
      }
    });
  }

  // 0 回目 小文字、1 回目 大文字、2 回目 先頭だけ大文字 (以後くり返し)
  private static letterCase(s: string, repeat: number): string {
    const r = repeat % 3;
    if (r === 1) { return s.toUpperCase(); }
    if (r === 2) { return s.length > 0 ? s[0].toUpperCase() + s.slice(1).toLowerCase() : s; }
    return s.toLowerCase();
  }

  // 読みのローマ字。覚えている打鍵から今の読みがそのまま作れるならそれを使い、
  // 途中を消した・前の方だけ確定したなどで食い違えば、読みから作り直す。
  private romajiFor(reading: string): string {
    if (this.rawKeys.length > 0) {
      const conv = new JapaneseConverter();
      let kana = '';
      for (let i = 0; i < this.rawKeys.length; i++) {
        kana += conv.processKey(toJapaneseInputChar(this.rawKeys[i])).committed;
      }
      kana += conv.flushPending();
      if (toHiragana(kana) === toHiragana(reading)) {
        return this.rawKeys;
      }
    }
    return kanaToRomaji(reading);
  }
}
