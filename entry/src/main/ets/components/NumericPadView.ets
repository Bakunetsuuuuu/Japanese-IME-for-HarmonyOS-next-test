import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

type FlickDir = 'center' | 'up' | 'right' | 'down' | 'left';

interface FlickKeyDef {
  center: string;
  up?: string;
  right?: string;
  down?: string;
  left?: string;
}

function getCharByDir(key: FlickKeyDef, dir: FlickDir): string {
  if (dir === 'up' && key.up !== undefined) { return key.up; }
  if (dir === 'right' && key.right !== undefined) { return key.right; }
  if (dir === 'down' && key.down !== undefined) { return key.down; }
  if (dir === 'left' && key.left !== undefined) { return key.left; }
  return key.center;
}

// Gboard-style numeric pad, reached via the あA/Aあ key's 日本語→アルファベット→
// 数字 cycle (see InputHandler.cycleInputMode) when 数字パッド is enabled in
// settings. Same 5-column (side keys + 3 digit columns) grid as FlickKeyboardView so it
// reuses flickKeyWidthVp and never fights that keyboard's width sizing.
// Symbol input from the digit-only pad was poor (記号 panel is a whole extra
// trip) -- each digit now flicks to a symbol, the same gesture
// FlickKeyboardView already teaches users for kana, so there's no new
// interaction to learn. Digits 1-9/0 match Gboard's own number pad exactly
// (confirmed against a real device screenshot: LEFT/UP/RIGHT only, no down
// direction used anywhere on Gboard's pad). -/. aren't part of that
// reference screenshot (Gboard replaces them with its own tap-cycle bracket/
// punctuation keys, a different interaction this file doesn't have yet), so
// they keep the same 3-direction shape with a reasonable symbol pick instead.
const NUM_FLICK_GRID: FlickKeyDef[][] = [
  [
    { center: '1', left: '☆', up: '♪', right: '→' },
    { center: '2', left: '¥', up: '$', right: '€' },
    { center: '3', left: '%', up: '°', right: '#' },
  ],
  [
    { center: '4', left: '○', up: '*', right: '・' },
    { center: '5', left: '+', up: '×', right: '÷' },
    { center: '6', left: '<', up: '=', right: '>' },
  ],
  [
    { center: '7', left: '「', up: '」', right: ':' },
    { center: '8', left: '〒', up: '々', right: '〆' },
    { center: '9', left: '^', up: '|', right: '\\' },
  ],
  [
    { center: '-', left: '(', up: ')', right: '_' },
    { center: '0', left: '~', up: '…', right: '@' },
    { center: '.', left: ',', up: ';', right: '/' },
  ],
];

@Component
export struct NumericPadView {
  @StorageLink('flickKeyWidthVp') flickKeyWidthVp: number = 72;
  @StorageLink('inputState') inputState: string = 'IDLE';
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  @State activeRow: number = -1;
  @State activeCol: number = -1;
  @State touchStartX: number = 0;
  @State touchStartY: number = 0;
  @State flickDir: FlickDir = 'center';

  private readonly THRESHOLD: number = 20;

  private h(): InputHandler { return InputHandler.getInstance(); }

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;
  private curDelayTimer: number = -1;
  private curRepeatTimer: number = -1;
  private curAccelTimer: number = -1;

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

  // Hold-to-repeat for the ◄/► caret keys, accelerating once held past ~1s.
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

  private insert(ch: string): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.IDLE) {
      this.h().insertText(ch);
    } else {
      this.h().handleDirectKana(ch);
    }
  }

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
    if (this.isActive(row, col)) { return getCharByDir(key, this.flickDir); }
    return key.center;
  }

  private keyBg(row: number, col: number): ResourceColor {
    if (this.isActive(row, col)) { return kbTheme(this.isDark).accentSoft; }
    return kbTheme(this.isDark).keyBg;
  }

  private handleTouch(e: TouchEvent, row: number, col: number, key: FlickKeyDef): void {
    if (e.type === TouchType.Down) {
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
        this.insert(getCharByDir(key, dir));
      }
      this.activeRow = -1;
      this.activeCol = -1;
      this.flickDir = 'center';
    }
  }

  build() {
    Column({ space: 4 }) {
      ForEach([0, 1, 2, 3], (rowIdx: number) => {
        Row({ space: 4 }) {
          this.LeftKey(rowIdx)
          ForEach([0, 1, 2], (colIdx: number) => {
            this.KeyCell(rowIdx, colIdx, NUM_FLICK_GRID[rowIdx][colIdx])
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

  @Builder KeyCell(rowIdx: number, colIdx: number, key: FlickKeyDef) {
    if (this.isLandscape) {
      // Landscape rows are short on height; drop the flick-direction hints and
      // just show the center glyph, same simplification FlickKeyboardView
      // uses. Flicking itself still works -- dirFrom() reads the touch
      // gesture, not this label.
      Text(this.centerLabel(rowIdx, colIdx, key))
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.isActive(rowIdx, colIdx) ? 17 : 18)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .fontColor(kbTheme(this.isDark).textPrimary)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(this.keyBg(rowIdx, colIdx))
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((e: TouchEvent) => { this.handleTouch(e, rowIdx, colIdx, key); })
    } else {
      Column({ space: 0 }) {
        Text(key.up ?? ' ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'up'))
          .width('100%').height('28%')
          .textAlign(TextAlign.Center)

        Row({ space: 0 }) {
          Text(key.left ?? ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'left'))
            .width('25%').textAlign(TextAlign.Center)

          Text(this.centerLabel(rowIdx, colIdx, key))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(this.isActive(rowIdx, colIdx) ? 22 : 20)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .fontWeight(FontWeight.Medium)
            .width('50%').textAlign(TextAlign.Center)

          Text(key.right ?? ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'right'))
            .width('25%').textAlign(TextAlign.Center)
        }
        .width('100%').height('44%')

        Text(key.down ?? ' ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'down'))
          .width('100%').height('28%')
          .textAlign(TextAlign.Center)
      }
      .width(this.flickKeyWidthVp)
      .height('100%')
      .backgroundColor(this.keyBg(rowIdx, colIdx))
      .borderRadius(14)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onTouch((e: TouchEvent) => { this.handleTouch(e, rowIdx, colIdx, key); })
    }
  }

  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      // フリックキーボードの左上枠と統一 -- 取消は押すたびに直近削除した文字を
      // 1つずつ戻す(消し過ぎた分を押した回数だけ復元する順次アンドゥ)。
      Text('取消')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          this.h().undoLastDeletion();
        })
    } else if (rowIdx === 1) {
      Text('◄')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.startCurRepeat('left'); }
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.stopCurRepeat(); }
        })
    } else if (rowIdx === 2) {
      Text('記号')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'symbol'); })
    } else {
      // '+' は5キーの左フリックで既に入力できるため、この枠は日本語入力に戻る
      // 「あA」キーに差し替える(数字パッドへは「あA」キーのサイクルからのみ入る
      // ため、抜けるときは常に日本語(ひらがな)へ戻す -- 入る前のinputModeが何で
      // あってもループが一貫した状態に着地するようにする)。
      Text('あA')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
          AppStorage.setOrCreate('keyboardSubMode', 'kana');
        })
    }
  }

  @Builder RightKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('⌫')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
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
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.startCurRepeat('right'); }
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.stopCurRepeat(); }
        })
    } else if (rowIdx === 2) {
      Text('space')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).textPrimary)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => { this.h().handleSpaceKey(); })
    } else {
      Text('⏎')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).accent).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(14).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => { this.h().handleEnterKey(); })
    }
  }
}
