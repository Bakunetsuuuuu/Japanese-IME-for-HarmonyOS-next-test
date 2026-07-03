import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
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

function getChar(key: FlickKeyDef, dir: FlickDir): string {
  if (dir === 'up' && key.up !== undefined) { return key.up; }
  if (dir === 'right' && key.right !== undefined) { return key.right; }
  if (dir === 'down' && key.down !== undefined) { return key.down; }
  if (dir === 'left' && key.left !== undefined) { return key.left; }
  return key.center;
}

// Flick rules: 1st=center, then left→up→right→down (5 chars), left→up→down (4 chars), numbers always at down
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

@Component
export struct AlphabetFlickKeyboardView {
  @Prop inputMode: string = InputMode.HIRAGANA;
  @Prop isLandscape: boolean = false;
  @StorageLink('flickKeyWidthVp') flickKeyWidthVp: number = 72;
  @StorageLink('inputState') inputState: string = 'IDLE';
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';
  @State showLayoutPopup: boolean = false;
  @State hoveredOption: string = '';
  @State showSettingsPopup: boolean = false;
  @State hoveredSetting: string = '';
  @State showSettingsPanel: boolean = false;
  @State oneHandMode: boolean = false;

  @State activeRow: number = -1;
  @State activeCol: number = -1;
  @State touchStartX: number = 0;
  @State touchStartY: number = 0;
  @State flickDir: FlickDir = 'center';

  private readonly THRESHOLD: number = 20;
  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;
  private layoutMenuTimer: number = -1;
  private touchDownX: number = 0;
  private touchDownY: number = 0;
  private spaceMenuTimer: number = -1;
  private spaceTouchDownX: number = 0;
  private spaceTouchDownY: number = 0;

  private h(): InputHandler { return InputHandler.getInstance(); }

  private startBsRepeat(): void {
    this.h().handleBackspace();
    this.bsDelayTimer = setTimeout(() => {
      this.bsRepeatTimer = setInterval(() => { this.h().handleBackspace(); }, 100);
    }, 500);
  }
  private stopBsRepeat(): void {
    clearTimeout(this.bsDelayTimer); clearInterval(this.bsRepeatTimer);
    this.bsDelayTimer = -1; this.bsRepeatTimer = -1;
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
    if (this.isActive(row, col) && this.flickDir === dir) { return kbTheme(this.isDark, this.themeVariant).accentStrongBg; }
    return this.isDark ? '#888888' : '#999999';
  }

  private keyBg(row: number, col: number, key: FlickKeyDef): ResourceColor {
    if (this.isActive(row, col)) { return this.isDark ? '#3A6FB0' : '#B8D4F0'; }
    return kbTheme(this.isDark, this.themeVariant).keyBg;
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
      this.touchStartX = t.x; this.touchStartY = t.y;
      this.activeRow = row; this.activeCol = col; this.flickDir = 'center';
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
      this.activeRow = -1; this.activeCol = -1; this.flickDir = 'center';
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

  @State lastChar: string = '';

  build() {
    Stack() {
      Column({ space: 2 }) {
        ForEach([0, 1, 2, 3], (rowIdx: number) => {
          Row({ space: 3 }) {
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
      .padding({ bottom: 8, top: 4, left: 2, right: 2 })

      if (this.showLayoutPopup) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => { this.showLayoutPopup = false; })

        Column() {
          this.layoutPopup()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 8, bottom: '22%' })
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('取消')
        .fontSize(13).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleUndo(); this.lastChar = ''; })
    } else if (rowIdx === 1) {
      Text('◄')
        .fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleCursorLeft(); this.lastChar = ''; })
    } else if (rowIdx === 2) {
      Text('記号')
        .fontSize(13).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'symbol'); })
    } else {
      Text('あA')
        .fontSize(12).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(this.activeRow === rowIdx && this.activeCol === -1 ? kbTheme(this.isDark, this.themeVariant).funcKeyBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.activeRow = rowIdx; this.activeCol = -1;
            this.touchDownX = e.touches[0].x; this.touchDownY = e.touches[0].y;
            this.layoutMenuTimer = setTimeout(() => {
              this.showLayoutPopup = true;
              this.activeRow = -1; this.activeCol = -1;
              this.layoutMenuTimer = -1;
            }, 400);
          } else if (e.type === TouchType.Move) {
            const dx = Math.abs(e.touches[0].x - this.touchDownX);
            if (dx > 15) { clearTimeout(this.layoutMenuTimer); this.layoutMenuTimer = -1; }
            if (this.showLayoutPopup) {
              const hdy = e.touches[0].y - this.touchDownY;
              if (hdy < -180) { this.hoveredOption = 'QWERTY'; }
              else if (hdy < -120) { this.hoveredOption = 'FLICK'; }
              else { this.hoveredOption = ''; }
            }
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            clearTimeout(this.layoutMenuTimer); this.layoutMenuTimer = -1;
            if (this.showLayoutPopup) {
              if (this.hoveredOption) { AppStorage.setOrCreate('keyboardLayout', this.hoveredOption); }
              this.showLayoutPopup = false; this.hoveredOption = '';
              this.activeRow = -1; this.activeCol = -1; return;
            }
            if (this.activeRow === rowIdx) {
              this.h().commitTopCandidate();
              AppStorage.setOrCreate('inputMode', InputMode.HIRAGANA);
            }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    }
  }

  @Builder RightKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('⌫')
        .fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(this.activeRow === rowIdx && this.activeCol === -1 ? kbTheme(this.isDark, this.themeVariant).funcKeyBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .animation({ duration: 80 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.activeRow = rowIdx; this.activeCol = -1; this.lastChar = '';
            this.startBsRepeat();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.activeRow = -1; this.activeCol = -1; this.stopBsRepeat();
          }
        })
    } else if (rowIdx === 1) {
      Text('►')
        .fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(this.activeRow === rowIdx && this.activeCol === -1 ? kbTheme(this.isDark, this.themeVariant).funcKeyBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; }
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.activeRow === rowIdx) { this.h().handleCursorRight(); this.lastChar = ''; }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else if (rowIdx === 2) {
      Text(this.inputState === 'COMPOSING' ? '文節' : '空白')
        .fontSize(this.inputState === 'COMPOSING' ? 13 : 12)
        .fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(this.activeRow === rowIdx && this.activeCol === -1 ? kbTheme(this.isDark, this.themeVariant).funcKeyBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.activeRow = rowIdx; this.activeCol = -1;
            this.spaceTouchDownX = e.touches[0].x; this.spaceTouchDownY = e.touches[0].y;
            this.spaceMenuTimer = setTimeout(() => {
              this.showSettingsPopup = true;
              this.activeRow = -1; this.activeCol = -1;
              this.spaceMenuTimer = -1;
            }, 400);
          } else if (e.type === TouchType.Move) {
            const dx = Math.abs(e.touches[0].x - this.spaceTouchDownX);
            if (dx > 15) { clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1; }
            if (this.showSettingsPopup) {
              const hdy = e.touches[0].y - this.spaceTouchDownY;
              if (hdy < -180) { this.hoveredSetting = 'onehand'; }
              else if (hdy < -120) { this.hoveredSetting = 'settings'; }
              else { this.hoveredSetting = ''; }
            }
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1;
            if (this.showSettingsPopup) {
              if (this.hoveredSetting === 'settings') {
                this.showSettingsPopup = false; this.showSettingsPanel = true;
              } else if (this.hoveredSetting === 'onehand') {
                this.oneHandMode = !this.oneHandMode; this.showSettingsPopup = false;
              }
              this.showSettingsPopup = false; this.hoveredSetting = '';
              this.activeRow = -1; this.activeCol = -1; return;
            }
            if (this.activeRow === rowIdx) {
              const st = AppStorage.get<string>('inputState') ?? 'IDLE';
              if (st === 'COMPOSING') { this.h().handleBunsetsu(); }
              else { this.h().handleSpaceKey(); }
              this.lastChar = '';
            }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else {
      Text('→')
        .fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(this.activeRow === rowIdx && this.activeCol === -1 ? kbTheme(this.isDark, this.themeVariant).accentStrongBg : kbTheme(this.isDark, this.themeVariant).accentBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
        .borderRadius(14).shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .animation({ duration: 80 })
        .onClick(() => {
          const st = AppStorage.get<string>('inputState') ?? 'IDLE';
          if (st === 'BUNSETSU') { this.h().commitBunsetsu(); }
          else if (st === 'SELECTING') { this.h().commitTopCandidate(); }
          else if (st === 'COMPOSING') { this.h().commitRaw(); }
          else { this.h().handleEnterKey(); }
          this.lastChar = '';
        })
    }
  }

  @Builder KeyCell(rowIdx: number, colIdx: number, key: FlickKeyDef) {
    Column({ space: 0 }) {
      Text(key.up !== undefined ? key.up : ' ')
        .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'up'))
        .width('100%').height('28%').textAlign(TextAlign.Center)

      Row({ space: 0 }) {
        Text(key.left !== undefined ? key.left : ' ')
          .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'left'))
          .width('25%').textAlign(TextAlign.Center)

        Text(this.isActive(rowIdx, colIdx) ? (key.special === 'case' ? this.caseLabel() : getChar(key, this.flickDir)) :
          key.special === 'case' ? this.caseLabel() : key.center)
          .fontSize(this.isActive(rowIdx, colIdx) ? 20 : 17)
          .fontColor(kbTheme(this.isDark, this.themeVariant).keyText)
          .fontWeight(FontWeight.Medium)
          .width('50%').textAlign(TextAlign.Center)

        Text(key.right !== undefined ? key.right : ' ')
          .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'right'))
          .width('25%').textAlign(TextAlign.Center)
      }
      .width('100%').height('44%')

      Text(key.down !== undefined ? key.down : ' ')
        .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'down'))
        .width('100%').height('28%').textAlign(TextAlign.Center)
    }
    .width(this.flickKeyWidthVp).height('100%')
    .backgroundColor(this.keyBg(rowIdx, colIdx, key))
    .borderRadius(14)
    .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
    .onTouch((e: TouchEvent) => { this.handleTouch(e, rowIdx, colIdx, key); })
  }

  @Builder layoutPopup() {
    Column() {
      Row() {
        Text('QWERTY')
          .fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .borderRadius(16)
          .backgroundColor(this.hoveredOption === 'QWERTY' ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
          .fontColor(this.hoveredOption === 'QWERTY' ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
          .width('100%')
      }
      Row() {
        Text('フリック')
          .fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .borderRadius(16)
          .backgroundColor(this.hoveredOption === 'FLICK' ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
          .fontColor(this.hoveredOption === 'FLICK' ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
          .width('100%')
      }
    }
    .padding(6)
    .width(200)
    .backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
    .borderRadius(22)
    .shadow({ radius: 6, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 4 })
  }

  @Builder settingsPopup() {
    Column() {
      Row() {
        Text('設定').fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
          .backgroundColor(this.hoveredSetting === 'settings' ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
          .fontColor(this.hoveredSetting === 'settings' ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
          .width('100%')
      }
      Row() {
        Text('片手キーボード').fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
          .backgroundColor(this.hoveredSetting === 'onehand' ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
          .fontColor(this.hoveredSetting === 'onehand' ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
          .width('100%')
      }
    }
    .padding(6).width(180).backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
    .borderRadius(22).shadow({ radius: 6, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 4 })
  }

  @Builder settingsPanel() {
    Column() {
      Row() {
        Text('設定').fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark, this.themeVariant).previewText)
      }.width('100%').justifyContent(FlexAlign.Center).height(40)
      .backgroundColor(kbTheme(this.isDark, this.themeVariant).composingBarBg)

      Scroll() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.SettingItem('テーマ', '🎨')
          this.SettingItem('デフォルトレイアウト', '⌨')
          this.SettingItem('ユーザ辞書', '📕')
          this.SettingItem('サウンド', '🔈')
          this.SettingItem('入力設定', '⚙')
        }
        .padding(12)
      }
      .layoutWeight(1)

      Row() {
        Text('閉じる').fontSize(14).fontColor(kbTheme(this.isDark, this.themeVariant).accentBg)
      }.width('100%').justifyContent(FlexAlign.Center).height(44)
      .backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
      .onClick(() => { this.showSettingsPanel = false; })
    }
    .width('100%').height('100%')
  }

  @Builder SettingItem(label: string, icon: string) {
    Column() {
      Text(icon).fontSize(28).margin({ bottom: 4 })
      Text(label).fontSize(13).fontColor(kbTheme(this.isDark, this.themeVariant).keyText)
    }
    .width(100).height(90).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .borderRadius(14).backgroundColor(kbTheme(this.isDark, this.themeVariant).keyBg)
    .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 1 })
    .margin(6)
    .onClick(() => {
      if (label === 'テーマ') {
        const next = AppStorage.get<string>('themeVariant') === 'glass' ? 'original' : 'glass';
        AppStorage.setOrCreate('themeVariant', next);
      }
      this.showSettingsPanel = false;
    })
  }

}