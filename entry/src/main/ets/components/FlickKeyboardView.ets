import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { toKatakana } from '../ime/JapaneseConverter';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

type FlickDir = 'center' | 'up' | 'right' | 'down' | 'left';

interface FlickKeyDef {
  center: string;
  up?: string;
  right?: string;
  down?: string;
  left?: string;
  special?: string;
}

function getKanaByDir(key: FlickKeyDef, dir: FlickDir): string {
  if (dir === 'up' && key.up !== undefined) { return key.up; }
  if (dir === 'right' && key.right !== undefined) { return key.right; }
  if (dir === 'down' && key.down !== undefined) { return key.down; }
  if (dir === 'left' && key.left !== undefined) { return key.left; }
  return key.center;
}

// 3 center kana columns (displayed in cols 1-3 of the 5-col layout)
const FLICK_GRID: FlickKeyDef[][] = [
  [
    { center: 'あ', up: 'う', right: 'え', down: 'お', left: 'い' },
    { center: 'か', up: 'く', right: 'け', down: 'こ', left: 'き' },
    { center: 'さ', up: 'す', right: 'せ', down: 'そ', left: 'し' },
  ],
  [
    { center: 'た', up: 'つ', right: 'て', down: 'と', left: 'ち' },
    { center: 'な', up: 'ぬ', right: 'ね', down: 'の', left: 'に' },
    { center: 'は', up: 'ふ', right: 'へ', down: 'ほ', left: 'ひ' },
  ],
  [
    { center: 'ま', up: 'む', right: 'め', down: 'も', left: 'み' },
    { center: 'や', up: 'ゆ', left: '（', right: '）', down: 'よ' },
    { center: 'ら', up: 'る', right: 'れ', down: 'ろ', left: 'り' },
  ],
  [
    { center: '゛', up: '゜', down: '小', special: 'dakuten' },
    { center: 'わ', up: 'ん', right: 'ー', down: '～', left: 'を' },
    { center: '、', up: '？', right: '！', down: '…', left: '。', special: 'punct' },
  ],
];

// Flick cell corner radius (design tokens: "flick cells 8px").
const CELL_RADIUS = 8;

@Component
export struct FlickKeyboardView {
  @Prop inputMode: string = InputMode.HIRAGANA;
  @Prop isLandscape: boolean = false;
  @StorageLink('flickKeyWidthVp') flickKeyWidthVp: number = 72;
  @StorageLink('inputState') inputState: string = 'IDLE';
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('keyChromeEnabled') keyChromeEnabled: boolean = true;
  // 数字パッドが有効だと「あA」キーは 日本語→アルファベット→数字 の3段階に
  // なるので、ラベルも切り替わる順に並べる (あA1 / A1あ / 1あA)。
  // 半角の A/1 は ひらがな と字形の大きさが厳密には揃わないが、
  // 全角にすると見た目が野暮ったくなるため半角のままにしている。
  @StorageLink('numericPadEnabled') numericPadEnabled: boolean = false;

  @State activeRow: number = -1;
  @State activeCol: number = -1;
  @State touchStartX: number = 0;
  @State touchStartY: number = 0;
  @State flickDir: FlickDir = 'center';
  // '' | 'right' | 'left' -- which one-handed hint popup is showing (armed by a
  // long-press on the space / 記号 key; an up-flick while it shows commits).
  @State oneHandHint: string = '';

  private readonly THRESHOLD: number = 20;

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;
  private curDelayTimer: number = -1;
  private curRepeatTimer: number = -1;
  private curAccelTimer: number = -1;
  private ohHintTimer: number = -1;

  private h(): InputHandler { return InputHandler.getInstance(); }

  private startBsRepeat(): void {
    this.h().handleBackspace();
    this.bsDelayTimer = setTimeout(() => {
      this.bsRepeatTimer = setInterval(() => {
        this.h().handleBackspace();
      }, 100);
    }, 500);
  }

  private stopBsRepeat(): void {
    clearTimeout(this.bsDelayTimer);
    clearInterval(this.bsRepeatTimer);
    this.bsDelayTimer = -1;
    this.bsRepeatTimer = -1;
  }

  // Hold-to-repeat for the ◄/► caret keys, like backspace, and accelerating
  // once held past ~1s so a long trip across the line doesn't take forever.
  private startCurRepeat(dir: string): void {
    const move = (): void => {
      if (dir === 'left') { this.h().handleCursorLeft(); }
      else { this.h().handleCursorRight(); }
    };
    move();
    this.curDelayTimer = setTimeout(() => {
      this.curRepeatTimer = setInterval(move, 110);
      this.curAccelTimer = setTimeout(() => {
        clearInterval(this.curRepeatTimer);
        this.curRepeatTimer = setInterval(move, 40);
      }, 600);
    }, 400);
  }

  private stopCurRepeat(): void {
    clearTimeout(this.curDelayTimer);
    clearInterval(this.curRepeatTimer);
    clearTimeout(this.curAccelTimer);
    this.curDelayTimer = -1;
    this.curRepeatTimer = -1;
    this.curAccelTimer = -1;
  }

  private toMode(kana: string): string {
    if (this.inputMode === InputMode.KATAKANA && /[ぁ-ん]/.test(kana)) {
      return toKatakana(kana);
    }
    return kana;
  }

  private rowH(): number { return this.isLandscape ? 50 : 64; }

  private dirFrom(dx: number, dy: number): FlickDir {
    if (Math.abs(dx) < this.THRESHOLD && Math.abs(dy) < this.THRESHOLD) { return 'center'; }
    if (Math.abs(dx) >= Math.abs(dy)) { return dx > 0 ? 'right' : 'left'; }
    return dy < 0 ? 'up' : 'down';
  }

  private isActive(row: number, col: number): boolean {
    return this.activeRow === row && this.activeCol === col;
  }

  private hintColor(row: number, col: number, dir: FlickDir): ResourceColor {
    if (this.isActive(row, col) && this.flickDir === dir) { return kbTheme(this.isDark).accentStrong; }
    return kbTheme(this.isDark).textSecondary;
  }

  private centerLabel(row: number, col: number, key: FlickKeyDef): string {
    if (key.special === 'dakuten') { return key.center; }
    if (key.special === 'punct') {
      const raw = this.isActive(row, col) ? getKanaByDir(key, this.flickDir) : key.center;
      return this.inputMode === InputMode.ALPHANUMERIC ? this.jpToAsciiPunct(raw) : raw;
    }
    if (this.isActive(row, col)) { return this.toMode(getKanaByDir(key, this.flickDir)); }
    return this.toMode(key.center);
  }

  private keyBg(row: number, col: number, key: FlickKeyDef): ResourceColor {
    if (key.special === 'dakuten') { return kbTheme(this.isDark).specialBg; }
    if (this.isActive(row, col)) { return kbTheme(this.isDark).accentSoft; }
    return this.keyChromeEnabled ? kbTheme(this.isDark).keyBg : 'transparent';
  }

  private keyShadow(row: number, col: number, key: FlickKeyDef): ShadowOptions {
    const filled = key.special === 'dakuten' || this.isActive(row, col) || this.keyChromeEnabled;
    return filled
      ? { radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 }
      : { radius: 0, color: 'transparent', offsetY: 0 };
  }

  private jpToAsciiPunct(s: string): string {
    const m: Record<string, string> = {
      '、': ',', '。': '.', '！': '!', '？': '?', '…': '...',
    };
    return m[s] ?? s;
  }

  private onCommit(key: FlickKeyDef, dir: FlickDir): void {
    if (key.special === 'dakuten') {
      this.h().handleVariantCycle();
      return;
    }
    if (key.special === 'punct') {
      const raw = getKanaByDir(key, dir);
      const punct = this.inputMode === InputMode.ALPHANUMERIC ? this.jpToAsciiPunct(raw) : raw;
      const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
      if (state === InputState.IDLE) {
        this.h().insertText(punct);
      } else {
        this.h().handleDirectKana(punct);
      }
      return;
    }
    const kana = this.toMode(getKanaByDir(key, dir));
    this.h().handleDirectKana(kana);
  }

  private handleTouch(e: TouchEvent, row: number, col: number, key: FlickKeyDef): void {
    if (e.type === TouchType.Down) {
      this.h().hapticTick();
      const t = e.touches[0];
      this.touchStartX = t.x;
      this.touchStartY = t.y;
      this.activeRow = row;
      this.activeCol = col;
      this.flickDir = 'center';
    } else if (e.type === TouchType.Move) {
      if (this.isActive(row, col) && e.touches.length > 0) {
        const t = e.touches[0];
        this.flickDir = this.dirFrom(t.x - this.touchStartX, t.y - this.touchStartY);
      }
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      if (this.isActive(row, col)) {
        const tc = e.changedTouches.length > 0 ? e.changedTouches[0] : e.touches[0];
        const dir = this.dirFrom(tc.x - this.touchStartX, tc.y - this.touchStartY);
        this.onCommit(key, dir);
      }
      this.activeRow = -1;
      this.activeCol = -1;
      this.flickDir = 'center';
    }
  }

  // Themed content for the one-handed hint popup so it reads as part of the
  // keyboard: theme surface (dark bg+white text in dark mode, light bg+dark
  // text in light mode) with the JP font, not the default system tooltip.
  @Builder OneHandHintPopup() {
    Text(this.oneHandHint === 'left' ? '左手モード' : '右手モード')
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(kbTheme(this.isDark).textPrimary)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
  }

  build() {
    Stack() {
      Column({ space: 4 }) {
        ForEach([0, 1, 2, 3], (rowIdx: number) => {
          Row({ space: 4 }) {
            this.LeftKey(rowIdx)
            ForEach([0, 1, 2], (colIdx: number) => {
              this.KeyCell(rowIdx, colIdx, FLICK_GRID[rowIdx][colIdx])
            }, (colIdx: number) => String(colIdx))
            this.RightKey(rowIdx)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
        }, (rowIdx: number) => String(rowIdx))
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: 8, top: 4 })

    }
    .width('100%')
    .height('100%')
  }

  // Left column keys per row
  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      // 数字パッドの入口は「あA」キー側のサイクルに一本化した(setNumericPadEnabled
      // 参照)。この枠は常に取消を表示する。押すたびに直近削除した文字を1つずつ
      // 戻す(消し過ぎた分を押した回数だけ復元する順次アンドゥ)。
      Text('取消')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          this.h().hapticTick();
          this.h().undoLastDeletion();
        })
    } else if (rowIdx === 1) {
      Text('◄')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.h().hapticTick();
            this.startCurRepeat('left');
          }
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.stopCurRepeat(); }
        })
    } else if (rowIdx === 2) {
      Text('記号')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        // Long-press to reveal the 左手モード hint, then flick up to switch.
        .bindPopup(this.oneHandHint === 'left', {
          builder: this.OneHandHintPopup,
          placement: Placement.Top,
          enableArrow: true,
          popupColor: kbTheme(this.isDark).specialBg,
          backgroundBlurStyle: BlurStyle.NONE,
          radius: 20,
          mask: false,
        })
        .gesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ duration: 300 })
              .onAction(() => {
                this.oneHandHint = 'left';
                this.ohHintTimer = setTimeout(() => { this.oneHandHint = ''; }, 1500);
              }),
            PanGesture({ direction: PanDirection.Up, distance: 20 })
              .onActionStart(() => {
                this.h().toggleOneHanded('left');
                clearTimeout(this.ohHintTimer);
                this.oneHandHint = '';
              })
          )
        )
        .onClick(() => {
          this.h().hapticTick();
          AppStorage.setOrCreate('keyboardSubMode', 'symbol');
        })
    } else {
      Text(this.numericPadEnabled
        ? (this.inputMode === InputMode.HIRAGANA ? 'あA1' : 'A1あ')
        : (this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ'))
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          this.h().hapticTick();
          this.h().commitTopCandidate();
          this.h().cycleInputMode();
        })
    }
  }

  // Right column keys per row
  @Builder RightKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('⌫')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.h().hapticTick();
            this.startBsRepeat();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.stopBsRepeat();
          }
        })
    } else if (rowIdx === 1) {
      Text('►')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.h().hapticTick();
            this.startCurRepeat('right');
          }
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.stopCurRepeat(); }
        })
    } else if (rowIdx === 2) {
      Text(this.inputState === 'COMPOSING' ? '文節' : '空白')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.inputState === 'COMPOSING' ? 13 : 12)
        .textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        // Long-press the space key to reveal the 右手モード hint, then flick up
        // while it shows to switch. Gating on the long-press stops a stray flick
        // from misfiring. A plain tap still inserts a space via onClick.
        .bindPopup(this.oneHandHint === 'right', {
          builder: this.OneHandHintPopup,
          placement: Placement.Top,
          enableArrow: true,
          popupColor: kbTheme(this.isDark).specialBg,
          backgroundBlurStyle: BlurStyle.NONE,
          radius: 20,
          mask: false,
        })
        .gesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ duration: 300 })
              .onAction(() => {
                this.oneHandHint = 'right';
                this.ohHintTimer = setTimeout(() => { this.oneHandHint = ''; }, 1500);
              }),
            PanGesture({ direction: PanDirection.Up, distance: 20 })
              .onActionStart(() => {
                this.h().toggleOneHanded('right');
                clearTimeout(this.ohHintTimer);
                this.oneHandHint = '';
              })
          )
        )
        .onClick(() => {
          this.h().hapticTick();
          const st = AppStorage.get<string>('inputState') ?? 'IDLE';
          if (st === 'COMPOSING') {
            this.h().handleBunsetsu();
          } else {
            this.h().handleSpaceKey();
          }
        })
    } else {
      Text('→')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).accent).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          this.h().hapticTick();
          const st = AppStorage.get<string>('inputState') ?? 'IDLE';
          if (st === 'BUNSETSU') {
            this.h().commitBunsetsu();
          } else if (st === 'SELECTING') {
            this.h().commitTopCandidate();
          } else if (st === 'COMPOSING') {
            this.h().commitRaw();
          } else {
            this.h().handleEnterKey();
          }
        })
    }
  }

  @Builder KeyCell(rowIdx: number, colIdx: number, key: FlickKeyDef) {
    if (this.isLandscape) {
      // Landscape rows are short on height; drop the flick-direction hints and
      // just show the center glyph. Flicking itself is unaffected — dirFrom()
      // reads the touch gesture, not this label.
      Text(this.centerLabel(rowIdx, colIdx, key))
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.isActive(rowIdx, colIdx) ? 17 : 14)
        .fontColor(key.special === 'dakuten' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp)
        .height('100%')
        .backgroundColor(this.keyBg(rowIdx, colIdx, key))
        .borderRadius(CELL_RADIUS)
        .shadow(this.keyShadow(rowIdx, colIdx, key))
        .onTouch((e: TouchEvent) => {
          this.handleTouch(e, rowIdx, colIdx, key);
        })
    } else {
      // 上・中・下の3帯。各帯は必ず中央揃えのコンテナで包む。
      // Text に height だけ与えると帯の中で上寄りに描かれ、中心文字との間隔が
      // 上下で食い違って「文字がずれている」ように見える。
      Column({ space: 0 }) {
        Row() {
          Text(key.up !== undefined ? this.toMode(key.up) : ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'up'))
            .textAlign(TextAlign.Center)
        }
        .width('100%').height('26%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Row({ space: 0 }) {
          Text(key.left !== undefined ? this.toMode(key.left) : ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'left'))
            .width('25%').textAlign(TextAlign.Center)

          Text(this.centerLabel(rowIdx, colIdx, key))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(this.isActive(rowIdx, colIdx) ? 22 : 18)
            .fontColor(key.special === 'dakuten' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
            .fontWeight(FontWeight.Medium)
            .width('50%').textAlign(TextAlign.Center)

          Text(key.right !== undefined ? this.toMode(key.right) : ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'right'))
            .width('25%').textAlign(TextAlign.Center)
        }
        .width('100%').height('44%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text(key.down !== undefined ? this.toMode(key.down) : ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'down'))
            .textAlign(TextAlign.Center)
        }
        .width('100%').height('30%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width(this.flickKeyWidthVp)
      .height('100%')
      .backgroundColor(this.keyBg(rowIdx, colIdx, key))
      .borderRadius(CELL_RADIUS)
      .shadow(this.keyShadow(rowIdx, colIdx, key))
      .onTouch((e: TouchEvent) => {
        this.handleTouch(e, rowIdx, colIdx, key);
      })
    }
  }
}
