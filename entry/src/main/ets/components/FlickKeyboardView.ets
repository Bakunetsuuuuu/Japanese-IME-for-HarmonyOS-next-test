import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { toKatakana } from '../ime/JapaneseConverter';
import { kbTheme } from './Theme';

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
    { center: 'や', up: 'ゆ', down: 'よ' },
    { center: 'ら', up: 'る', right: 'れ', down: 'ろ', left: 'り' },
  ],
  [
    { center: '゛', up: '゜', down: '小', special: 'dakuten' },
    { center: 'わ', up: 'ん', right: 'ー', down: '～', left: 'を' },
    { center: '、', up: '？', right: '！', down: '…', left: '。', special: 'punct' },
  ],
];

@Component
export struct FlickKeyboardView {
  @Prop inputMode: string = InputMode.HIRAGANA;
  @Prop isLandscape: boolean = false;
  @StorageLink('flickKeyWidthVp') flickKeyWidthVp: number = 72;
  @StorageLink('inputState') inputState: string = 'IDLE';
  @StorageLink('isDark') isDark: boolean = false;

  @State activeRow: number = -1;
  @State activeCol: number = -1;
  @State touchStartX: number = 0;
  @State touchStartY: number = 0;
  @State flickDir: FlickDir = 'center';

  private readonly THRESHOLD: number = 20;

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;

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
    if (this.isActive(row, col) && this.flickDir === dir) { return kbTheme(this.isDark).accentStrongBg; }
    return this.isDark ? '#888888' : '#999999';
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
    if (key.special === 'dakuten') { return kbTheme(this.isDark).specialKeyBg; }
    if (this.isActive(row, col)) { return this.isDark ? '#3A6FB0' : '#B8D4F0'; }
    return kbTheme(this.isDark).keyBg;
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

  build() {
    Column({ space: 2 }) {
      // 4 rows × 5 columns (Gboard layout)
      ForEach([0, 1, 2, 3], (rowIdx: number) => {
        Row({ space: 3 }) {
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

  // Left column keys per row
  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('取消')
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleUndo(); })
    } else if (rowIdx === 1) {
      Text('◄')
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleCursorLeft(); })
    } else if (rowIdx === 2) {
      Text('記号')
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => {
          AppStorage.setOrCreate('keyboardSubMode', 'symbol');
        })
    } else {
      Text(this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ')
        .fontSize(12).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => {
          this.h().commitTopCandidate();
          const cur = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
          const next = cur === InputMode.HIRAGANA ? InputMode.ALPHANUMERIC : InputMode.HIRAGANA;
          AppStorage.setOrCreate('inputMode', next);
        })
    }
  }

  // Right column keys per row
  @Builder RightKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('⌫')
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.startBsRepeat();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.stopBsRepeat();
          }
        })
    } else if (rowIdx === 1) {
      Text('►')
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleCursorRight(); })
    } else if (rowIdx === 2) {
      Text(this.inputState === 'COMPOSING' ? '文節' : '空白')
        .fontSize(this.inputState === 'COMPOSING' ? 13 : 12)
        .textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => {
          const st = AppStorage.get<string>('inputState') ?? 'IDLE';
          if (st === 'COMPOSING') {
            this.h().handleBunsetsu();
          } else {
            this.h().handleSpaceKey();
          }
        })
    } else {
      Text('→')
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).accentBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => {
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
    // Landscape rows are shorter (rowH ~50vp vs ~64vp portrait); the portrait font
    // sizes don't leave enough line-height within the 28%/44%/28% split, so the
    // up/down hint labels visually collide with the center glyph. Shrink both in
    // landscape to keep them cleanly separated.
    Column({ space: 0 }) {
      Text(key.up !== undefined ? this.toMode(key.up) : ' ')
        .fontSize(this.isLandscape ? 9 : 11)
        .fontColor(this.hintColor(rowIdx, colIdx, 'up'))
        .width('100%').height('28%')
        .textAlign(TextAlign.Center)

      Row({ space: 0 }) {
        Text(key.left !== undefined ? this.toMode(key.left) : ' ')
          .fontSize(this.isLandscape ? 9 : 11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'left'))
          .width('25%').textAlign(TextAlign.Center)

        Text(this.centerLabel(rowIdx, colIdx, key))
          .fontSize(this.isActive(rowIdx, colIdx) ? (this.isLandscape ? 17 : 20) : (this.isLandscape ? 14 : 17))
          .fontColor(key.special === 'dakuten' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).keyText)
          .fontWeight(FontWeight.Medium)
          .width('50%').textAlign(TextAlign.Center)

        Text(key.right !== undefined ? this.toMode(key.right) : ' ')
          .fontSize(this.isLandscape ? 9 : 11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'right'))
          .width('25%').textAlign(TextAlign.Center)
      }
      .width('100%').height('44%')

      Text(key.down !== undefined ? this.toMode(key.down) : ' ')
        .fontSize(this.isLandscape ? 9 : 11)
        .fontColor(this.hintColor(rowIdx, colIdx, 'down'))
        .width('100%').height('28%')
        .textAlign(TextAlign.Center)
    }
    .width(this.flickKeyWidthVp)
    .height('100%')
    .backgroundColor(this.keyBg(rowIdx, colIdx, key))
    .borderRadius(8)
    .shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
    .onTouch((e: TouchEvent) => {
      this.handleTouch(e, rowIdx, colIdx, key);
    })
  }
}
