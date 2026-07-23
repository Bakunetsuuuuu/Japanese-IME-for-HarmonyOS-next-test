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
  special?: string;
}

function getChar(key: FlickKeyDef, dir: FlickDir): string {
  if (dir === 'up' && key.up !== undefined) { return key.up; }
  if (dir === 'right' && key.right !== undefined) { return key.right; }
  if (dir === 'down' && key.down !== undefined) { return key.down; }
  if (dir === 'left' && key.left !== undefined) { return key.left; }
  return key.center;
}

const ALPHA_GRID: FlickKeyDef[][] = [
  [
    { center: '@', left: '-', up: '_', right: '/', down: '1', special: 'symbol' },
    { center: 'a', left: 'b', up: 'c', down: '2' },
    { center: 'd', left: 'e', up: 'f', down: '3' },
  ],
  [
    { center: 'g', left: 'h', up: 'i', down: '4' },
    { center: 'j', left: 'k', up: 'l', down: '5' },
    { center: 'm', left: 'n', up: 'o', down: '6' },
  ],
  [
    { center: 'p', left: 'q', up: 'r', right: 's', down: '7' },
    { center: 't', left: 'u', up: 'v', down: '8' },
    { center: 'w', left: 'x', up: 'y', right: 'z', down: '9' },
  ],
  [
    { center: 'a', special: 'case' },
    { center: "'", left: '"', up: ':', right: ';', down: '0' },
    { center: '.', left: ',', up: '?', down: '!' },
  ],
];

const CELL_RADIUS = 14;

@Component
export struct AlphabetFlickKeyboardView {
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
  @State showSpaceMenu: boolean = false;
  @State hoveredSpaceOption: string = '';
  @State showModeMenu: boolean = false;
  @State hoveredModeOption: string = '';

  private readonly THRESHOLD: number = 20;

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;
  private spaceMenuTimer: number = -1;
  private spaceTouchDownX: number = 0;
  private spaceTouchDownY: number = 0;

  @State lastChar: string = '';

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

  private keyBg(row: number, col: number, key: FlickKeyDef): ResourceColor {
    if (key.special === 'case') { return kbTheme(this.isDark).specialBg; }
    if (this.isActive(row, col)) { return kbTheme(this.isDark).accentSoft; }
    return kbTheme(this.isDark).keyBg;
  }

  private centerLabel(row: number, col: number, key: FlickKeyDef): string {
    if (key.special === 'case') { return this.caseLabel(); }
    if (this.isActive(row, col)) { return getChar(key, this.flickDir); }
    return key.center;
  }

  private caseLabel(): string { return 'a/A'; }

  private handleTouch(e: TouchEvent, row: number, col: number, key: FlickKeyDef): void {
    if (key.special === 'case') {
      if (e.type === TouchType.Up) {
        if (this.lastChar && /^[a-z]$/.test(this.lastChar)) {
          this.h().handleBackspace();
          this.h().insertText(this.lastChar.toUpperCase());
          this.lastChar = this.lastChar.toUpperCase();
        }
      }
      return;
    }
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

  private onCommit(key: FlickKeyDef, dir: FlickDir): void {
    if (key.special === 'case') { return; }
    let ch = getChar(key, dir);
    if (/^[a-zA-Z]$/.test(ch)) { ch = ch.toLowerCase(); }
    const st = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (st === InputState.IDLE) { this.h().insertText(ch); }
    else { this.h().handleKeyPress(ch); }
    this.lastChar = /^[a-z]$/.test(ch) ? ch : '';
  }

  build() {
    Stack() {
      Column({ space: 4 }) {
        ForEach([0, 1, 2, 3], (rowIdx: number) => {
          Row({ space: 4 }) {
            this.LeftKey(rowIdx)
            ForEach([0, 1, 2], (colIdx: number) => {
              this.KeyCell(rowIdx, colIdx, ALPHA_GRID[rowIdx][colIdx])
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

      if (this.showSpaceMenu) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#00000000')
            .onClick(() => { this.showSpaceMenu = false; this.hoveredSpaceOption = ''; })

          Column() {
            Row() {
              Text('設定')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15).textAlign(TextAlign.Center)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
                .backgroundColor(this.hoveredSpaceOption === 'settings' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
                .fontColor(this.hoveredSpaceOption === 'settings' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                .width('100%')
                .onHover((isHover: boolean) => {
                  this.hoveredSpaceOption = isHover ? 'settings' : '';
                })
                .onClick(() => {
                  AppStorage.setOrCreate('keyboardSubMode', 'settings');
                  this.showSpaceMenu = false;
                  this.hoveredSpaceOption = '';
                })
            }
            Row() {
              Text('片手キーボード')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15).textAlign(TextAlign.Center)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
                .backgroundColor(this.hoveredSpaceOption === 'onehand' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
                .fontColor(this.hoveredSpaceOption === 'onehand' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                .width('100%')
                .onHover((isHover: boolean) => {
                  this.hoveredSpaceOption = isHover ? 'onehand' : '';
                })
                .onClick(() => {
                  const cur = AppStorage.get<boolean>('oneHandedMode') ?? false;
                  AppStorage.setOrCreate('oneHandedMode', !cur);
                  this.showSpaceMenu = false;
                  this.hoveredSpaceOption = '';
                })
            }
          }
          .padding(6).width(180)
          .backgroundColor(kbTheme(this.isDark).panelBg)
          .borderRadius(22)
          .shadow({ radius: 6, color: kbTheme(this.isDark).shadowColor, offsetY: 4 })
          .alignSelf(ItemAlign.End)
          .margin({ right: 8, bottom: '22%' })
        }
        .width('100%')
        .height('100%')
      }

      if (this.showModeMenu) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#00000000')
            .onClick(() => { this.showModeMenu = false; this.hoveredModeOption = ''; })

          Column() {
            Row() {
              Text('QWERTY')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15).textAlign(TextAlign.Center)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
                .backgroundColor(this.hoveredModeOption === 'QWERTY' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
                .fontColor(this.hoveredModeOption === 'QWERTY' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                .width('100%')
                .onHover((isHover: boolean) => {
                  this.hoveredModeOption = isHover ? 'QWERTY' : '';
                })
                .onClick(() => {
                  AppStorage.setOrCreate('keyboardLayout', 'QWERTY');
                  this.showModeMenu = false;
                  this.hoveredModeOption = '';
                })
            }
            Row() {
              Text('フリック')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15).textAlign(TextAlign.Center)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
                .backgroundColor(this.hoveredModeOption === 'FLICK' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
                .fontColor(this.hoveredModeOption === 'FLICK' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                .width('100%')
                .onHover((isHover: boolean) => {
                  this.hoveredModeOption = isHover ? 'FLICK' : '';
                })
                .onClick(() => {
                  AppStorage.setOrCreate('keyboardLayout', 'FLICK');
                  this.showModeMenu = false;
                  this.hoveredModeOption = '';
                })
            }
          }
          .padding(6).width(180)
          .backgroundColor(kbTheme(this.isDark).panelBg)
          .borderRadius(22)
          .shadow({ radius: 6, color: kbTheme(this.isDark).shadowColor, offsetY: 4 })
          .alignSelf(ItemAlign.Start)
          .margin({ left: 8, bottom: '22%' })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('取消')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          this.h().undoLastDeletion();
          this.lastChar = '';
        })
    } else if (rowIdx === 1) {
      Text('◄')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => { this.h().handleCursorLeft(); this.lastChar = ''; })
    } else if (rowIdx === 2) {
      Text('記号')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => {
          AppStorage.setOrCreate('keyboardSubMode', 'symbol');
        })
    } else {
      Text('あA')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .gesture(
          LongPressGesture({ duration: 400 })
            .onAction(() => {
              this.showModeMenu = true;
            })
        )
        .onClick(() => {
          this.h().commitTopCandidate();
          this.h().cycleInputMode();
          this.lastChar = '';
        })
    }
  }

  @Builder RightKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('⌫')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.lastChar = '';
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
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onClick(() => { this.h().handleCursorRight(); this.lastChar = ''; })
    } else if (rowIdx === 2) {
      Text(this.inputState === 'COMPOSING' ? '文節' : '空白')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.inputState === 'COMPOSING' ? 13 : 12)
        .textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialBg).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .gesture(
          LongPressGesture({ duration: 400 })
            .onAction(() => {
              this.showSpaceMenu = true;
            })
        )
        .onClick(() => {
          const st = AppStorage.get<string>('inputState') ?? 'IDLE';
          if (st === 'COMPOSING') {
            this.h().handleBunsetsu();
          } else {
            this.h().handleSpaceKey();
          }
          this.lastChar = '';
        })
    } else {
      Text('→')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).accent).fontColor(kbTheme(this.isDark).onAccent)
        .borderRadius(CELL_RADIUS).shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
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
          this.lastChar = '';
        })
    }
  }

  @Builder KeyCell(rowIdx: number, colIdx: number, key: FlickKeyDef) {
    if (this.isLandscape) {
      Text(this.centerLabel(rowIdx, colIdx, key))
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.isActive(rowIdx, colIdx) ? 17 : 14)
        .fontColor(key.special === 'case' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp)
        .height('100%')
        .backgroundColor(this.keyBg(rowIdx, colIdx, key))
        .borderRadius(CELL_RADIUS)
        .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
        .onTouch((e: TouchEvent) => {
          this.handleTouch(e, rowIdx, colIdx, key);
        })
    } else {
      Column({ space: 0 }) {
        Text(key.up !== undefined ? key.up : ' ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'up'))
          .width('100%').height('28%')
          .textAlign(TextAlign.Center)

        Row({ space: 0 }) {
          Text(key.left !== undefined ? key.left : ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'left'))
            .width('25%').textAlign(TextAlign.Center)

          Text(this.centerLabel(rowIdx, colIdx, key))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(this.isActive(rowIdx, colIdx) ? 22 : 18)
            .fontColor(key.special === 'case' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
            .fontWeight(FontWeight.Medium)
            .width('50%').textAlign(TextAlign.Center)

          Text(key.right !== undefined ? key.right : ' ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.hintColor(rowIdx, colIdx, 'right'))
            .width('25%').textAlign(TextAlign.Center)
        }
        .width('100%').height('44%')

        Text(key.down !== undefined ? key.down : ' ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'down'))
          .width('100%').height('28%')
          .textAlign(TextAlign.Center)
      }
      .width(this.flickKeyWidthVp)
      .height('100%')
      .backgroundColor(this.keyBg(rowIdx, colIdx, key))
      .borderRadius(CELL_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onTouch((e: TouchEvent) => {
        this.handleTouch(e, rowIdx, colIdx, key);
      })
    }
  }
}
