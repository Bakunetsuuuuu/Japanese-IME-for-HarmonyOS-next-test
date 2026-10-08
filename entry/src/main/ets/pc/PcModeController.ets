// PCモード (物理キーボード) のまとめ役。
//
// ・物理キーボードがつながっている間 (設定「自動」) は PCモードに入る
// ・言語バー: STATUS_BAR パネル (入力メソッド 1 つにつき 1 枚まで作れる)。
//   入力欄にいる間だけ出す
// ・ソフトキーボードのパネル (SOFT_KEYBOARD、これも 1 枚まで) を使い回す:
//     'candidate' = 候補ウィンドウ (FLAG_CANDIDATE。サービスが勝手に出し入れ
//                   しないので、入力中だけ自分で出す)。カーソルの下に置く
//     'popup'     = 言語バーから開いた絵文字・設定 (同じく FLAG_CANDIDATE で、
//                   言語バーの上に置く)
//     'keyboard'  = 仮想キー (今までのソフトキーボード。固定/フローティング)
//   中身の切り替えは KeyboardPage が AppStorage('pcSoftContent') を見て描き分ける
//   (setUiContent をやり直すと遅く、ちらつくため)。
// ・PCモードを使っていないとき、このクラスは何もしない (今までどおり)。
import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import display from '@ohos.display';
import type { KeyEvent as InputKeyEvent } from '@ohos.multimodalInput.keyEvent';
import type { InputHandler, KeyboardController } from '../ime/KeyboardController';
import { InputState, InputMode } from '../ime/KeyboardController';
import { InputLog } from '../ime/InputLog';
import { KeyboardDeviceMonitor } from './KeyboardDeviceMonitor';
import { PhysicalKeyRouter, PcKeyHost } from './PhysicalKeyRouter';
import { PcSettingsStore, PcSettings, PC_MODE_AUTO, PC_MODE_ON, PC_MODE_OFF } from './PcSettings';
import { currentCandidateView, candidateWindowSizeVp, CandidateViewModel, SizeVp } from './CandidateViewModel';
import {
  CAND_MARGIN_VP, CAND_MIN_W_VP, CAND_ROW_H_VP, LANGBAR_W_VP, LANGBAR_H_VP, LANGBAR_EDGE_GAP_VP, POPUP_W_VP, POPUP_H_VP, POPUP_GAP_VP
} from './PcStyle';

const IMEAbility = inputMethodEngine.getInputMethodAbility();

// 'keyboard' | 'candidate' | 'popup' (上の説明参照)
export const PC_SOFT_KEYBOARD: string = 'keyboard';
export const PC_SOFT_CANDIDATE: string = 'candidate';
export const PC_SOFT_POPUP: string = 'popup';

// 言語バーから開ける中身 (keyboardSubMode の値。EmojiView から記号一覧へも行ける)
const POPUP_SUB_MODES: string[] = ['emoji', 'symbol', 'settings'];

// cursorContextChange で届くカーソルの位置。SDK の説明では y は「カーソルの下端」だが、
// 実機 (HarmonyOS PC) では上端が届く (下端として置くと候補ウィンドウが 1 行ぶん上にずれ、
// 画面上の方の入力欄に重なっていた)。上端として扱う
interface CursorInfo {
  x: number;       // カーソルの左端の x (px)
  y: number;       // カーソルの上端の y (px)
  height: number;  // カーソルの高さ (px)。0 で届く欄もある (そのときは FALLBACK_LINE_H_VP)
}

// カーソルの高さが届かない (0) ときに仮に使う 1 行の高さ (vp)
const FALLBACK_LINE_H_VP: number = 20;
// カーソルと候補ウィンドウの本体の間 (vp)
const CAND_CURSOR_GAP_VP: number = 4;

interface RectPx {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface ScreenInfo {
  w: number;
  h: number;
  density: number;
  avail: RectPx;   // Dock・ステータスバーを除いた範囲
}

export class PcModeController implements PcKeyHost {
  private static instance: PcModeController | undefined = undefined;

  static getInstance(): PcModeController {
    if (PcModeController.instance === undefined) {
      PcModeController.instance = new PcModeController();
    }
    return PcModeController.instance;
  }

  private host: KeyboardController | undefined = undefined;
  private handler: InputHandler | undefined = undefined;
  private context: InputMethodExtensionContext | undefined = undefined;
  private router: PhysicalKeyRouter | undefined = undefined;
  private monitor: KeyboardDeviceMonitor | undefined = undefined;
  private preference: string = PC_MODE_AUTO;
  private active: boolean = false;
  // inputStart 〜 inputStop の間 (入力欄にいる)
  private sessionActive: boolean = false;

  // 言語バー (STATUS_BAR パネル)
  private statusPanel: inputMethodEngine.Panel | undefined = undefined;
  // 作っている途中のパネル。作っている間に来た「出して」も、これの完了を待って出す
  private statusPanelPromise: Promise<inputMethodEngine.Panel | undefined> | undefined = undefined;
  // 作るのに失敗した回数。STATUS_BAR を作れない端末で、欄に入るたびに作り直し続けないための上限
  private statusPanelFailures: number = 0;
  private static readonly MAX_STATUS_PANEL_FAILURES: number = 3;
  // こちらが出したつもりか (langBarShown) と、OS から知らされた実際の状態 (langBarVisible)。
  // 欄を素早く移ったときなどに OS 側が言語バーを隠すことがあり、自分の印だけで
  // 「出ている」と思い込むと show() を呼ばなくなって、言語バーが出ないままになっていた
  private langBarShown: boolean = false;
  private langBarVisible: boolean = false;
  // 出しているつもりなのに OS に隠されたとき、出し直した回数 (入力欄ごと)。隠し合いを続けない上限
  private langBarReshows: number = 0;
  private static readonly MAX_LANGBAR_RESHOWS: number = 3;
  private langBarRecheckTimer: number = -1;
  private langBarRect: RectPx = { x: 0, y: 0, w: 0, h: 0 };
  private langBarXFrac: number = -1;
  private langBarYFrac: number = -1;
  private langBarDragStart: RectPx | undefined = undefined;
  private hideLangBarTimer: number = -1;

  // ソフトキーボードのパネル
  private softState: string = PC_SOFT_KEYBOARD;
  private softShown: boolean = false;
  // PCモードに入った時点でソフトキーボードのパネルがまだ無かった
  // (initPanel の createPanel は非同期)。できたら FLAG_CANDIDATE にする
  private candidateFlagPending: boolean = false;
  private softRect: RectPx = { x: -1, y: -1, w: -1, h: -1 };

  // カーソル (cursorContextChange)。anchor は読みを打ち始めた時点のカーソルで、
  // 入力中は候補ウィンドウをそこに留める (打つたびに窓が右へ逃げないように)
  private cursor: CursorInfo | undefined = undefined;
  private anchor: CursorInfo | undefined = undefined;

  private screen: ScreenInfo | undefined = undefined;
  // 使える範囲 (Dock を除いた範囲) を getAvailableArea で知っているか。知らないうちは
  // 画面全体で計算することになり、言語バーを Dock の裏に置いてしまう
  private availKnown: boolean = false;
  private availPromise: Promise<void> | undefined = undefined;
  private syncTimer: number = -1;

  // ---------- 起動・終了 (KeyboardController から) ----------

  attach(host: KeyboardController, handler: InputHandler, context: InputMethodExtensionContext): void {
    this.host = host;
    this.handler = handler;
    this.context = context;
    this.router = new PhysicalKeyRouter(handler, this);
    AppStorage.setOrCreate('pcModeActive', false);
    AppStorage.setOrCreate('pcSoftContent', PC_SOFT_KEYBOARD);
    AppStorage.setOrCreate('pcModePreference', PC_MODE_AUTO);
    this.monitor = new KeyboardDeviceMonitor((_connected: boolean) => { this.recompute(); });
    PcSettingsStore.load(context).then((s: PcSettings) => {
      this.preference = s.pcModePreference;
      this.langBarXFrac = s.langBarXFrac;
      this.langBarYFrac = s.langBarYFrac;
      AppStorage.setOrCreate('pcModePreference', s.pcModePreference);
      this.monitor?.start();
      this.recompute();
    });
  }

  detach(): void {
    this.monitor?.stop();
    clearTimeout(this.syncTimer);
    clearTimeout(this.hideLangBarTimer);
    clearTimeout(this.langBarRecheckTimer);
    if (this.statusPanel !== undefined) {
      this.statusPanel.off('show');
      this.statusPanel.off('hide');
      IMEAbility.destroyPanel(this.statusPanel).catch((_e: Error) => {});
      this.statusPanel = undefined;
    }
  }

  isPcActive(): boolean {
    return this.active;
  }

  // ソフトキーボードのパネルを PCモードが候補ウィンドウ・展開に使っているか
  // (KeyboardController はこの間、パネルの大きさ・flag を変えてはいけない)
  ownsSoftPanel(): boolean {
    return this.active && this.softState !== PC_SOFT_KEYBOARD;
  }

  // ---------- 設定 (SettingsBar から) ----------

  setPreference(pref: string): void {
    const p = (pref === PC_MODE_ON || pref === PC_MODE_OFF) ? pref : PC_MODE_AUTO;
    this.preference = p;
    AppStorage.setOrCreate('pcModePreference', p);
    if (this.context !== undefined) {
      PcSettingsStore.savePreference(this.context, p);
    }
    this.recompute();
  }

  private recompute(): void {
    const connected = this.monitor?.isConnected() ?? false;
    const want = this.preference === PC_MODE_ON || (this.preference === PC_MODE_AUTO && connected);
    if (want !== this.active) {
      this.setActive(want);
    }
  }

  activateFromKey(deviceId: number): boolean {
    if (this.preference !== PC_MODE_AUTO || this.monitor === undefined) { return false; }
    this.monitor.noteKeyFrom(deviceId);   // つながったと分かれば recompute が走る
    return this.active;
  }

  private setActive(v: boolean): void {
    console.info(`shuntiIME pc mode ${v ? 'on' : 'off'} (preference=${this.preference})`);
    this.active = v;
    AppStorage.setOrCreate('pcModeActive', v);
    InputLog.recordMode(`pcMode=${v}`);
    this.router?.reset();
    this.anchor = undefined;
    if (v) {
      this.refreshScreen();
      // ソフトキーボードで入力中だったものは確定してから切り替える
      this.handler?.commitComposition();
      AppStorage.setOrCreate('keyboardSubMode', 'kana');
      AppStorage.setOrCreate('pcVirtualKeyboard', false);
      this.enterCandidateMode();
      this.statusPanelFailures = 0;
      if (this.sessionActive) { this.showLangBar(); }
    } else {
      this.hideLangBar();
      this.candidateFlagPending = false;
      const wasOwned = this.softState !== PC_SOFT_KEYBOARD;
      this.setSoftState(PC_SOFT_KEYBOARD);
      AppStorage.setOrCreate('keyboardSubMode', 'kana');
      AppStorage.setOrCreate('pcVirtualKeyboard', false);
      if (wasOwned) {
        // キーボードを外した: 入力欄にいるなら今までのソフトキーボードを出す
        this.softShown = false;
        this.host?.restoreSoftKeyboardForPc(this.sessionActive);
      }
    }
  }

  private setSoftState(s: string): void {
    this.softState = s;
    AppStorage.setOrCreate('pcSoftContent', s);
  }

  // ソフトキーボードのパネルを候補ウィンドウ用 (FLAG_CANDIDATE・隠した状態) にする
  private enterCandidateMode(): void {
    const wasKeyboard = this.softState === PC_SOFT_KEYBOARD;
    this.setSoftState(PC_SOFT_CANDIDATE);
    this.softShown = false;
    this.softRect = { x: -1, y: -1, w: -1, h: -1 };
    if (!wasKeyboard) { return; }
    if (this.host?.getSoftPanel() === undefined) {
      this.candidateFlagPending = true;
      return;
    }
    this.candidateFlagPending = false;
    this.host?.changeSoftPanelFlagForPc(inputMethodEngine.PanelFlag.FLAG_CANDIDATE, false, () => {
      this.afterCandidateFlag();
    });
  }

  // 候補ウィンドウ用の flag にした直後。パネルはまだキーボードの大きさ (画面幅 × キーボードの
  // 高さ) のままで、この状態で出ると中身の無い大きな板が画面に出てしまう。出す前に小さくしておく
  // (本当の大きさ・置き場所は候補を出すときに syncSoftPanel が決める)
  private afterCandidateFlag(): void {
    const panel = this.host?.getSoftPanel();
    if (panel !== undefined && !this.softShown) {
      const sc = this.screenInfo();
      const w = Math.round(CAND_MIN_W_VP * sc.density);
      const h = Math.round(CAND_ROW_H_VP * sc.density);
      this.softRect = { x: -1, y: -1, w: w, h: h };
      panel.resize(w, h).catch((_e: Error) => {});
      // 隠しておく (flag を変える前の hide と行き違って出たままになることがある)
      panel.hide().catch((_e: Error) => {});
      this.host?.noteSoftPanelVisible(false);
    }
    this.scheduleSync();
  }

  // KeyboardController.initPanel でソフトキーボードのパネルができた
  onSoftPanelReady(): void {
    const panel = this.host?.getSoftPanel();
    if (panel !== undefined) { this.watchSoftPanel(panel); }
    if (!this.candidateFlagPending) { return; }
    this.candidateFlagPending = false;
    if (!this.active || this.softState === PC_SOFT_KEYBOARD) { return; }
    this.host?.changeSoftPanelFlagForPc(inputMethodEngine.PanelFlag.FLAG_CANDIDATE, false, () => {
      this.afterCandidateFlag();
    });
  }

  // PCモードが候補ウィンドウ・展開に使っている間に、こちらが出していないのにパネルが
  // 出た (アプリがキーボードを求めたときに OS が出すなど) ら、すぐ隠す。
  // 起動直後に画面の上端へ大きな空白の板が出ていたのはこれ
  private watchSoftPanel(panel: inputMethodEngine.Panel): void {
    try {
      panel.on('show', () => {
        if (this.ownsSoftPanel() && !this.softShown) {
          console.info('shuntiIME pc soft panel shown unexpectedly, hiding');
          panel.hide().catch((_e: Error) => {});
          this.host?.noteSoftPanelVisible(false);
        }
      });
    } catch (err) {
      console.error('shuntiIME soft panel on(show) error', JSON.stringify(err));
    }
  }

  // ---------- 入力欄の出入り (KeyboardController から) ----------

  // 入力欄に入った。PCモードでソフトキーボードを出さないなら true
  // (KeyboardController はパネルを show しない)
  onInputStart(): boolean {
    this.sessionActive = true;
    clearTimeout(this.hideLangBarTimer);
    this.cursor = undefined;
    this.anchor = undefined;
    this.router?.reset();
    this.langBarReshows = 0;
    console.info(`shuntiIME pc inputStart active=${this.active} soft=${this.softState} langbar=${this.langBarShown}/${this.langBarVisible}`);
    if (!this.active) { return false; }
    this.refreshScreen();
    this.showLangBar();
    if (this.softState === PC_SOFT_KEYBOARD) {
      return false;   // 仮想キーを出している: いつもどおり出す
    }
    if (this.softState === PC_SOFT_POPUP) {
      this.closePopup();
    }
    this.scheduleSync();
    return true;
  }

  onInputStop(): void {
    console.info(`shuntiIME pc inputStop active=${this.active} soft=${this.softState}`);
    this.sessionActive = false;
    this.router?.reset();
    this.cursor = undefined;
    this.anchor = undefined;
    if (!this.active) { return; }
    if (this.softState === PC_SOFT_POPUP) {
      this.closePopup();
    }
    this.hideSoftPanel();
    // 欄を移るだけなら inputStop の直後に inputStart が来る。そのたびに
    // 言語バーが消えて出るとちらつくので、少し待ってから隠す
    clearTimeout(this.hideLangBarTimer);
    this.hideLangBarTimer = setTimeout(() => {
      if (!this.sessionActive) { this.hideLangBar(); }
    }, 300);
  }

  onDisplayChanged(): void {
    if (!this.active) { return; }
    // 大きさが変わっていなければ何もしない (使える範囲が変わっていれば refreshScreen が直す)
    if (!this.refreshScreen()) { return; }
    if (this.langBarShown) { this.placeLangBar(); }
    this.scheduleSync();
  }

  // KeyboardController.resizePanel から (PCモードがパネルを持っている間)。
  // 置き場所が変わっていなければ placeSoftPanel が何もしないので、そのまま合わせ直すだけ
  relayout(): void {
    this.scheduleSync();
  }

  // ---------- キー・カーソル (KeyboardDelegate から) ----------

  onKeyEvent(e: InputKeyEvent): boolean {
    if (this.router === undefined) { return false; }
    // 何も入力していないときに来た打鍵の時点のカーソル = これから打つ読みの頭
    if ((AppStorage.get<string>('inputState') ?? InputState.IDLE) === InputState.IDLE) {
      this.anchor = this.cursor;
    }
    return this.router.onKeyEvent(e);
  }

  onCursorContextChange(x: number, y: number, height: number): void {
    // 位置が分からない欄は 0,0,0 を送ってくることがある
    if (x === 0 && y === 0 && height === 0) { return; }
    this.cursor = { x: x, y: y, height: height };
    if (this.active && this.softState === PC_SOFT_CANDIDATE && this.softShown) {
      this.scheduleSync();
    }
  }

  // ---------- 状態が変わった (打鍵・候補のクリック・裏の変換の到着) ----------

  onImeStateChanged(): void {
    this.scheduleSync();
  }

  // 同じ打鍵の中で何度呼ばれても、パネルを動かすのは 1 回にまとめる
  private scheduleSync(): void {
    if (this.syncTimer >= 0) { return; }
    this.syncTimer = setTimeout(() => {
      this.syncTimer = -1;
      this.syncSoftPanel();
    }, 0);
  }

  private syncSoftPanel(): void {
    if (!this.active) { return; }
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.IDLE) { this.anchor = undefined; }
    if (this.softState === PC_SOFT_POPUP) {
      this.placeSoftPanel(this.popupRect(), true);
      return;
    }
    if (this.softState !== PC_SOFT_CANDIDATE) { return; }
    const vm = currentCandidateView();
    if (!this.sessionActive || !vm.visible) {
      this.hideSoftPanel();
      return;
    }
    this.placeSoftPanel(this.candidateRect(vm), true);
  }

  // ---------- 候補ウィンドウの置き場所 ----------

  private candidateRect(vm: CandidateViewModel): RectPx {
    const sc = this.screenInfo();
    const size: SizeVp = candidateWindowSizeVp(vm);
    const w = Math.round(size.w * sc.density);
    const h = Math.round(size.h * sc.density);
    const margin = Math.round(CAND_MARGIN_VP * sc.density);
    const cur = this.cursorForCandidate();
    let x: number;
    let y: number;
    if (cur !== undefined) {
      // 本体の左上をカーソルの真下に (窓の余白のぶん左上へずらす)
      const lineH = cur.height > 0 ? cur.height : Math.round(FALLBACK_LINE_H_VP * sc.density);
      const gap = Math.round(CAND_CURSOR_GAP_VP * sc.density);
      x = cur.x - margin;
      y = cur.y + lineH + gap - margin;
      if (y + h > sc.avail.y + sc.avail.h) {
        // 下に入らない: カーソルの上に (本体の下端がカーソルの上端より gap だけ上)
        y = cur.y - gap - (h - margin);
      }
    } else {
      // カーソルの位置が分からない欄: 言語バーの上 (右端を揃える)
      const lb = this.langBarRectPx();
      x = lb.x + lb.w - w;
      y = lb.y - h;
      if (y < sc.avail.y) { y = lb.y + lb.h; }
    }
    x = Math.max(0, Math.min(sc.w - w, x));
    y = Math.max(0, Math.min(sc.h - h, y));
    return { x: Math.round(x), y: Math.round(y), w: w, h: h };
  }

  private cursorForCandidate(): CursorInfo | undefined {
    const cur = this.cursor;
    const a = this.anchor;
    if (cur === undefined) { return a; }
    if (a === undefined) { return cur; }
    // 折り返して次の行へ移ったら、そちらに付いていく
    if (Math.abs(cur.y - a.y) > Math.max(4, a.height / 2)) {
      this.anchor = cur;
      return cur;
    }
    return { x: Math.min(a.x, cur.x), y: cur.y, height: cur.height };
  }

  // ---------- 言語バー ----------

  private langBarWanted(): boolean {
    return this.active && this.sessionActive;
  }

  private ensureStatusPanel(): Promise<inputMethodEngine.Panel | undefined> {
    if (this.statusPanel !== undefined) { return Promise.resolve(this.statusPanel); }
    if (this.statusPanelPromise !== undefined) { return this.statusPanelPromise; }
    if (this.context === undefined
        || this.statusPanelFailures >= PcModeController.MAX_STATUS_PANEL_FAILURES) {
      return Promise.resolve(undefined);
    }
    // moveTo は FLG_FIXED (PanelInfo の flag の既定) のパネルには効かないので、
    // 動かせるよう FLG_FLOATING で作る (changeFlag は SOFT_KEYBOARD にしか効かない)
    const info: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.STATUS_BAR,
      flag: inputMethodEngine.PanelFlag.FLG_FLOATING,
    };
    let created: inputMethodEngine.Panel | undefined = undefined;
    this.statusPanelPromise = IMEAbility.createPanel(this.context, info)
      .then((panel: inputMethodEngine.Panel) => {
        created = panel;
        return panel.setUiContent('pages/LangBarPage');
      })
      .then((): inputMethodEngine.Panel | undefined => {
        this.statusPanelPromise = undefined;
        if (created !== undefined) {
          this.statusPanel = created;
          this.watchStatusPanel(created);
        }
        return this.statusPanel;
      })
      .catch((err: Error): inputMethodEngine.Panel | undefined => {
        // 作れない端末 (STATUS_BAR 非対応など) では言語バー無しで続ける (モードはキーで
        // 切り替えられる)。中身を載せるところで失敗したパネルは捨てて、次の欄で作り直す
        console.error('shuntiIME create STATUS_BAR panel error', JSON.stringify(err));
        this.statusPanelPromise = undefined;
        this.statusPanelFailures++;
        if (created !== undefined) {
          IMEAbility.destroyPanel(created).catch((_e: Error) => {});
        }
        return undefined;
      });
    return this.statusPanelPromise;
  }

  // OS が言語バーを出した・隠したことを知る。こちらは出しているつもりなのに隠された
  // (入力欄を移ったときに OS が隠すことがある) ら、少し待って出し直す
  private watchStatusPanel(panel: inputMethodEngine.Panel): void {
    try {
      panel.on('show', () => {
        this.langBarVisible = true;
      });
      panel.on('hide', () => {
        this.langBarVisible = false;
        if (!this.langBarShown || !this.langBarWanted()
            || this.langBarReshows >= PcModeController.MAX_LANGBAR_RESHOWS) {
          return;
        }
        this.langBarReshows++;
        console.info(`shuntiIME langbar hidden by system, showing again (${this.langBarReshows})`);
        setTimeout(() => {
          if (this.langBarWanted()) { this.showLangBar(); }
        }, 150);
      });
    } catch (err) {
      console.error('shuntiIME langbar on(show/hide) error', JSON.stringify(err));
    }
  }

  private showLangBar(): void {
    clearTimeout(this.hideLangBarTimer);
    this.ensureStatusPanel().then((panel: inputMethodEngine.Panel | undefined) => {
      if (panel === undefined) { return; }
      // 使える範囲が分かるまで待つ (分からないまま出すと Dock の裏に置いてしまう)。
      // 実機では Promise が解決しないことがある (KeyboardController の resizePanel 参照) ので、
      // 待つのは 300ms まで
      if (!this.availKnown && this.availPromise !== undefined) {
        let done = false;
        const go = (): void => {
          if (done) { return; }
          done = true;
          this.showLangBarNow(panel);
        };
        this.availPromise.then(go);
        setTimeout(go, 300);
      } else {
        this.showLangBarNow(panel);
      }
    });
  }

  private showLangBarNow(panel: inputMethodEngine.Panel): void {
    // 作っている間に入力欄を離れた・PCモードが切れたなら出さない (確かめるのは今の状態)
    if (!this.langBarWanted()) { return; }
    this.placeLangBar(true);
    // 出ているつもりでも毎回 show() する (OS 側が隠していても印は変わらないので、
    // 印を見て省くと出ないままになる)。もう出ていれば何も起きない
    this.langBarShown = true;
    panel.show().catch((err: Error) => {
      console.error('shuntiIME langbar show error', JSON.stringify(err));
    });
    // 作った直後や欄を移った直後は、窓の準備・OS 側の後始末と行き違って show() が
    // 効かないことがあるので、少し後に実際に出ているかを確かめてもう一度
    clearTimeout(this.langBarRecheckTimer);
    this.langBarRecheckTimer = setTimeout(() => {
      this.langBarRecheckTimer = -1;
      if (this.langBarWanted() && this.langBarShown && !this.langBarVisible
          && this.statusPanel !== undefined) {
        this.placeLangBar(true);
        this.statusPanel.show().catch((_e: Error) => {});
      }
    }, 300);
  }

  private hideLangBar(): void {
    clearTimeout(this.langBarRecheckTimer);
    // 先に印を下ろす (下ろす前に hide の知らせが来ると「隠された」と思って出し直してしまう)
    this.langBarShown = false;
    if (this.statusPanel === undefined) { return; }
    this.statusPanel.hide().catch((_e: Error) => {});
  }

  private langBarRectPx(): RectPx {
    const sc = this.screenInfo();
    const w = Math.round(LANGBAR_W_VP * sc.density);
    const h = Math.round(LANGBAR_H_VP * sc.density);
    let x: number;
    let y: number;
    if (this.langBarXFrac < 0 || this.langBarYFrac < 0) {
      // まだ動かしていない: 使える範囲の右下 (Windows のタスクバーの入力インジケーターの辺り)
      const gap = Math.round(LANGBAR_EDGE_GAP_VP * sc.density);
      x = sc.avail.x + sc.avail.w - w - gap;
      y = sc.avail.y + sc.avail.h - h - gap;
    } else {
      x = this.langBarXFrac * sc.w;
      y = this.langBarYFrac * sc.h;
    }
    x = Math.max(0, Math.min(sc.w - w, x));
    y = Math.max(0, Math.min(sc.h - h, y));
    return { x: Math.round(x), y: Math.round(y), w: w, h: h };
  }

  // force: 大きさが変わっていなくても resize する (出す前。作った直後の resize が
  // 窓の準備前で効いていないと、大きさ 0 のまま見えないことがある)
  private placeLangBar(force: boolean = false): void {
    const panel = this.statusPanel;
    if (panel === undefined) { return; }
    const r = this.langBarRectPx();
    const resize = force || r.w !== this.langBarRect.w || r.h !== this.langBarRect.h;
    const move = force || r.x !== this.langBarRect.x || r.y !== this.langBarRect.y;
    this.langBarRect = r;
    // resize と moveTo の Promise が実機で確実に解決しない件 (KeyboardController の
    // resizePanel 参照) があるので、つなげずに投げっぱなしにする
    if (resize) {
      panel.resize(r.w, r.h).catch((err: Error) => {
        console.error('shuntiIME langbar resize error', JSON.stringify(err));
      });
    }
    if (move) {
      panel.moveTo(r.x, r.y).catch((err: Error) => {
        console.error('shuntiIME langbar moveTo error', JSON.stringify(err));
      });
    }
  }

  // 言語バーの左端のつまみのドラッグ (LangBarPage から、vp のずれで)
  beginLangBarDrag(): void {
    this.langBarDragStart = this.langBarRectPx();
  }

  moveLangBarLive(offsetXVp: number, offsetYVp: number): void {
    const start = this.langBarDragStart;
    const panel = this.statusPanel;
    if (start === undefined || panel === undefined) { return; }
    const sc = this.screenInfo();
    const x = Math.max(0, Math.min(sc.w - start.w, start.x + offsetXVp * sc.density));
    const y = Math.max(0, Math.min(sc.h - start.h, start.y + offsetYVp * sc.density));
    this.langBarXFrac = x / sc.w;
    this.langBarYFrac = y / sc.h;
    this.langBarRect = { x: Math.round(x), y: Math.round(y), w: start.w, h: start.h };
    panel.moveTo(Math.round(x), Math.round(y)).catch((_e: Error) => {});
  }

  endLangBarDrag(): void {
    if (this.langBarDragStart === undefined) { return; }
    this.langBarDragStart = undefined;
    if (this.context !== undefined) {
      PcSettingsStore.saveLangBarPosition(this.context, this.langBarXFrac, this.langBarYFrac);
    }
    // 展開を開いていれば言語バーに付いていく
    this.scheduleSync();
  }

  // ---------- 言語バーのボタン ----------

  toggleImeOnOff(): void {
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    this.setImeOn(mode === InputMode.ALPHANUMERIC);
  }

  setImeOn(on: boolean): void {
    const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
    const next = on
      ? (mode === InputMode.ALPHANUMERIC ? InputMode.HIRAGANA : mode)
      : InputMode.ALPHANUMERIC;
    if (next === mode) { return; }
    // 切り替える前に入力中のものを確定する (Windows の IME をオフにしたときと同じ)
    this.handler?.commitComposition();
    AppStorage.setOrCreate('inputMode', next);
    InputLog.recordMode(`input=${next}`);
    this.scheduleSync();
  }

  isVirtualKeyboardShown(): boolean {
    return this.active && this.softState === PC_SOFT_KEYBOARD;
  }

  // 仮想キー (今までのソフトキーボード) の出し入れ。出している間も物理キーは使える
  toggleVirtualKeyboard(): void {
    if (!this.active) { return; }
    if (this.softState === PC_SOFT_KEYBOARD) {
      AppStorage.setOrCreate('keyboardSubMode', 'kana');
      this.enterCandidateMode();
    } else {
      if (this.softState === PC_SOFT_POPUP) {
        AppStorage.setOrCreate('keyboardSubMode', 'kana');
      }
      this.setSoftState(PC_SOFT_KEYBOARD);
      this.softShown = false;
      this.host?.restoreSoftKeyboardForPc(this.sessionActive);
    }
    AppStorage.setOrCreate('pcVirtualKeyboard', this.softState === PC_SOFT_KEYBOARD);
  }

  // 絵文字 / 設定 を言語バーから開く。同じボタンをもう一度押したら閉じる
  togglePopup(subMode: string): void {
    if (!this.active) { return; }
    if (this.softState === PC_SOFT_KEYBOARD) {
      // 仮想キーを出しているときは、そのキーボードの中で切り替える
      const cur = AppStorage.get<string>('keyboardSubMode') ?? 'kana';
      AppStorage.setOrCreate('keyboardSubMode', cur === subMode ? 'kana' : subMode);
      return;
    }
    if (this.softState === PC_SOFT_POPUP
        && (AppStorage.get<string>('keyboardSubMode') ?? 'kana') === subMode) {
      this.closePopup();
      return;
    }
    // 入力中のものは確定してから開く (候補ウィンドウと同じパネルを使うため)
    this.handler?.commitComposition();
    this.setSoftState(PC_SOFT_POPUP);
    AppStorage.setOrCreate('keyboardSubMode', subMode);
    this.softRect = { x: -1, y: -1, w: -1, h: -1 };
    this.placeSoftPanel(this.popupRect(), true);
  }

  closePopup(): void {
    if (this.softState !== PC_SOFT_POPUP) { return; }
    this.setSoftState(PC_SOFT_CANDIDATE);
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    this.hideSoftPanel();
    this.softRect = { x: -1, y: -1, w: -1, h: -1 };
  }

  closePopupForTyping(): void {
    this.closePopup();
  }

  // keyboardSubMode が変わった (LangBarPage が見張っている)。展開の中の
  // 「戻る」は keyboardSubMode を 'kana' にするだけなので、それで閉じる。
  // 設定の「レイアウト調整」は実物のキーボードが要るので仮想キーに切り替える
  onSubModeChanged(subMode: string): void {
    if (!this.active || this.softState !== PC_SOFT_POPUP) { return; }
    if (subMode === 'layoutAdjust') {
      this.setSoftState(PC_SOFT_KEYBOARD);
      this.softShown = false;
      AppStorage.setOrCreate('pcVirtualKeyboard', true);
      this.host?.restoreSoftKeyboardForPc(this.sessionActive);
      return;
    }
    if (POPUP_SUB_MODES.indexOf(subMode) < 0) {
      this.closePopup();
    }
  }

  // 設定から辞書の登録を始めた (dictEditMode)。登録欄 (DictEditBar) は
  // ソフトキーボードの画面にしか無いので、仮想キーに切り替えて出す
  onDictEditChanged(editing: boolean): void {
    if (!editing || !this.active || this.softState === PC_SOFT_KEYBOARD) { return; }
    this.setSoftState(PC_SOFT_KEYBOARD);
    this.softShown = false;
    AppStorage.setOrCreate('pcVirtualKeyboard', true);
    this.host?.restoreSoftKeyboardForPc(this.sessionActive);
  }

  private popupRect(): RectPx {
    const sc = this.screenInfo();
    const w = Math.round(Math.min(POPUP_W_VP * sc.density, sc.avail.w));
    const h = Math.round(Math.min(POPUP_H_VP * sc.density, sc.avail.h));
    const gap = Math.round(POPUP_GAP_VP * sc.density);
    const lb = this.langBarRectPx();
    let x = lb.x + lb.w - w;
    // 言語バーが画面の下半分にあれば上へ、上半分にあれば下へ開く
    let y = (lb.y + lb.h / 2 > sc.h / 2) ? lb.y - h - gap : lb.y + lb.h + gap;
    x = Math.max(0, Math.min(sc.w - w, x));
    y = Math.max(0, Math.min(sc.h - h, y));
    return { x: Math.round(x), y: Math.round(y), w: w, h: h };
  }

  // ---------- ソフトキーボードのパネル (候補・展開) ----------

  private placeSoftPanel(r: RectPx, show: boolean): void {
    const panel = this.host?.getSoftPanel();
    if (panel === undefined) { return; }
    const resize = r.w !== this.softRect.w || r.h !== this.softRect.h;
    const move = r.x !== this.softRect.x || r.y !== this.softRect.y;
    this.softRect = r;
    if (resize) {
      panel.resize(r.w, r.h).catch((err: Error) => {
        console.error('shuntiIME pc soft panel resize error', JSON.stringify(err));
      });
    }
    if (move) {
      panel.moveTo(r.x, r.y).catch((err: Error) => {
        console.error('shuntiIME pc soft panel moveTo error', JSON.stringify(err));
      });
    }
    if (show && !this.softShown) {
      this.softShown = true;
      this.host?.noteSoftPanelVisible(true);
      panel.show().catch((err: Error) => {
        console.error('shuntiIME pc soft panel show error', JSON.stringify(err));
      });
    }
  }

  private hideSoftPanel(): void {
    if (!this.softShown) { return; }
    this.softShown = false;
    this.host?.noteSoftPanelVisible(false);
    this.host?.getSoftPanel()?.hide().catch((_e: Error) => {});
  }

  // ---------- 画面の大きさ ----------

  // 画面の大きさを読み直す。大きさ・密度が変わったら true。
  // 使える範囲は前回の値を使い続け、getAvailableArea の結果が違っていたときだけ置き直す。
  // 以前は読み直すたびに使える範囲を「画面全体」に戻していたので、そのたびに言語バーを
  // いったん画面全体の右下 (Dock の裏) へ動かしてから正しい位置へ戻していた。この 2 回の
  // moveTo は別のスレッドで処理されるので、順番が入れ替わると Dock の裏で止まり、
  // 言語バーが見えなくなっていた (display の change は PC では数秒おきに届く)
  private refreshScreen(): boolean {
    let changed = false;
    try {
      const dis = display.getDefaultDisplaySync();
      const density = dis.densityDPI > 0 ? dis.densityDPI / 160 : 2.0;
      const prev = this.screen;
      changed = prev === undefined || prev.w !== dis.width || prev.h !== dis.height || prev.density !== density;
      const full: RectPx = { x: 0, y: 0, w: dis.width, h: dis.height };
      const avail: RectPx = (!changed && prev !== undefined) ? prev.avail : full;
      if (changed) { this.availKnown = false; }
      this.screen = { w: dis.width, h: dis.height, density: density, avail: avail };
      this.availPromise = dis.getAvailableArea()
        .then((a: display.Rect) => {
          if (this.screen === undefined || a.width <= 0 || a.height <= 0) {
            this.availKnown = true;
            return;
          }
          const next: RectPx = { x: a.left, y: a.top, w: a.width, h: a.height };
          const cur = this.screen.avail;
          const same = this.availKnown && cur.x === next.x && cur.y === next.y
            && cur.w === next.w && cur.h === next.h;
          this.screen.avail = next;
          this.availKnown = true;
          if (same) { return; }
          if (this.langBarShown) { this.placeLangBar(); }
          this.scheduleSync();
        })
        .catch((_e: Error) => {
          // 取れない端末は画面全体のまま
          this.availKnown = true;
        });
    } catch (err) {
      console.error('shuntiIME pc refreshScreen error', JSON.stringify(err));
    }
    return changed;
  }

  private screenInfo(): ScreenInfo {
    if (this.screen === undefined) { this.refreshScreen(); }
    if (this.screen === undefined) {
      const fallback: RectPx = { x: 0, y: 0, w: 1920, h: 1080 };
      return { w: 1920, h: 1080, density: 2.0, avail: fallback };
    }
    return this.screen;
  }
}
