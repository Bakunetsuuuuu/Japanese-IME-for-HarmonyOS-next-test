import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { toKatakana } from '../ime/JapaneseConverter';
import { kbTheme } from './Theme';

type FlickDir = 'center' | 'up' | 'right' | 'down' | 'left';

interface FlickKeyDef {
  center: string; up?: string; right?: string; down?: string; left?: string; special?: string;
}

function getKanaByDir(key: FlickKeyDef, dir: FlickDir): string {
  if (dir === 'up' && key.up !== undefined) { return key.up; }
  if (dir === 'right' && key.right !== undefined) { return key.right; }
  if (dir === 'down' && key.down !== undefined) { return key.down; }
  if (dir === 'left' && key.left !== undefined) { return key.left; }
  return key.center;
}

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
  @StorageLink('themeVariant') themeVariant: string = 'original';
  @StorageLink('displayWidth') displayWidth: number = 360;
  @State showLayoutPopup: boolean = false;
  @State hoveredOption: string = '';
  @State showSettingsPopup: boolean = false;
  @State hoveredSetting: string = '';
  @State showSettingsPanel: boolean = false;
  @State showThemePicker: boolean = false;
  

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

  private toMode(kana: string): string {
    if (this.inputMode === InputMode.KATAKANA && /[ぁ-ん]/.test(kana)) { return toKatakana(kana); }
    return kana;
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

  private centerLabel(row: number, col: number, key: FlickKeyDef): string {
    if (key.special === 'dakuten') { return key.center; }
    if (key.special === 'punct') {
      const raw = this.isActive(row, col) ? getKanaByDir(key, this.flickDir) : key.center;
      return this.inputMode === InputMode.ALPHANUMERIC ? this.jpToAsciiPunct(raw) : raw;
    }
    if (this.isActive(row, col)) { return this.toMode(getKanaByDir(key, this.flickDir)); }
    return this.toMode(key.center);
  }

  private jpToAsciiPunct(s: string): string {
    const m: Record<string, string> = { '、': ',', '。': '.', '！': '!', '？': '?', '…': '...' };
    return m[s] ?? s;
  }

  private onCommit(key: FlickKeyDef, dir: FlickDir): void {
    if (key.special === 'dakuten') { this.h().handleVariantCycle(); return; }
    if (key.special === 'punct') {
      const raw = getKanaByDir(key, dir);
      const punct = this.inputMode === InputMode.ALPHANUMERIC ? this.jpToAsciiPunct(raw) : raw;
      const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
      if (state === InputState.IDLE) { this.h().insertText(punct); }
      else { this.h().handleDirectKana(punct); }
      return;
    }
    const kana = this.toMode(getKanaByDir(key, dir));
    this.h().handleDirectKana(kana);
  }

  private handleTouch(e: TouchEvent, row: number, col: number, key: FlickKeyDef): void {
    if (e.type === TouchType.Down) {
      const t = e.touches[0]; this.touchStartX = t.x; this.touchStartY = t.y;
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

  private scaleW(w: number): number {
    return Math.floor(w * (this.displayWidth - 56) / this.displayWidth);
  }
  build() {
    Stack() {
      Column({ space: 2 }) {
        ForEach([0, 1, 2, 3], (rowIdx: number) => {
          Row({ space: 3 }) {
            this.LeftKey(rowIdx)
            ForEach([0, 1, 2], (colIdx: number) => {
              this.KeyCell(rowIdx, colIdx, FLICK_GRID[rowIdx][colIdx])
            }, (colIdx: number) => String(colIdx))
            this.RightKey(rowIdx)
          }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)
        }, (rowIdx: number) => String(rowIdx))
      }
      .width('100%').height('100%').padding({ bottom: 8, top: 4, left: 2, right: 2 })

      if (this.showLayoutPopup) {
        Column().width('100%').height('100%')
          .onClick(() => { this.showLayoutPopup = false; })
        Column() { this.layoutPopup() }
          .width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 8, bottom: '22%' }).justifyContent(FlexAlign.End)
      }

      if (this.showSettingsPopup) {
        Column().width('100%').height('100%')
          .onClick(() => { this.showSettingsPopup = false; })
        Column() { this.settingsPopup() }
          .width('100%').alignItems(HorizontalAlign.End)
          .padding({ right: 8, bottom: '22%' }).justifyContent(FlexAlign.End)
      }

      if (this.showSettingsPanel) {
        Column() { this.settingsPanel() }
          .width('100%').height('100%')
          .backgroundColor(kbTheme(this.isDark, this.themeVariant).panelBg)
      }

      if (this.showThemePicker) {
        Column().width('100%').height('100%')
          .onClick(() => { this.showThemePicker = false; })
        Column() { this.themePicker() }
          .width('100%').alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
      }

    }
    .width('100%').height('100%')
  }

  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('取消').fontSize(13).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; }
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.activeRow === rowIdx) { this.h().handleUndo(); }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else if (rowIdx === 1) {
      Text('◄').fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; }
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.activeRow === rowIdx) { this.h().handleCursorLeft(); }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else if (rowIdx === 2) {
      Text('記号').fontSize(13).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; }
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.activeRow === rowIdx) { AppStorage.setOrCreate('keyboardSubMode', 'symbol'); }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else {
      Text(this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ')
        .fontSize(12).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.activeRow = rowIdx; this.activeCol = -1;
            this.touchDownX = e.touches[0].x; this.touchDownY = e.touches[0].y;
            this.layoutMenuTimer = setTimeout(() => {
              this.showLayoutPopup = true; this.activeRow = -1; this.activeCol = -1; this.layoutMenuTimer = -1;
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
              const cur = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
              const next = cur === InputMode.HIRAGANA ? InputMode.ALPHANUMERIC : InputMode.HIRAGANA;
              AppStorage.setOrCreate('inputMode', next);
            }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    }
  }

  @Builder RightKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('⌫').fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; this.startBsRepeat(); }
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.activeRow = -1; this.activeCol = -1; this.stopBsRepeat();
          }
        })
    } else if (rowIdx === 1) {
      Text('►').fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; }
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.activeRow === rowIdx) { this.h().handleCursorRight(); }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else if (rowIdx === 2) {
      Text(this.inputState === 'COMPOSING' ? '文節' : '空白')
        .fontSize(this.inputState === 'COMPOSING' ? 13 : 12).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
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
              if (hdy < -80) { this.hoveredSetting = 'settings'; }
              else if (hdy < -40) { this.hoveredSetting = 'onehand'; }
              else { this.hoveredSetting = ''; }
            }
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1;
            if (this.showSettingsPopup) {
              if (this.hoveredSetting === 'settings') {
                this.showSettingsPopup = false; this.showSettingsPanel = true;
              }
              }
              this.showSettingsPopup = false; this.hoveredSetting = '';
              this.activeRow = -1; this.activeCol = -1; return;
            }
            if (this.activeRow === rowIdx) {
              const st = AppStorage.get<string>('inputState') ?? 'IDLE';
              if (st === 'COMPOSING') { this.h().handleBunsetsu(); }
              else { this.h().handleSpaceKey(); }
            }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    } else {
      Text('→').fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).accentBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(14)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 }).animation({ duration: 80 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) { this.activeRow = rowIdx; this.activeCol = -1; }
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.activeRow === rowIdx) {
              const st = AppStorage.get<string>('inputState') ?? 'IDLE';
              if (st === 'BUNSETSU') { this.h().commitBunsetsu(); }
              else if (st === 'SELECTING') { this.h().commitTopCandidate(); }
              else if (st === 'COMPOSING') { this.h().commitRaw(); }
              else { this.h().handleEnterKey(); }
            }
            this.activeRow = -1; this.activeCol = -1;
          }
        })
    }
  }

  @Builder KeyCell(rowIdx: number, colIdx: number, key: FlickKeyDef) {
    Column({ space: 0 }) {
      Text(key.up !== undefined ? this.toMode(key.up) : ' ')
        .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'up'))
        .width('100%').height('28%').textAlign(TextAlign.Center)
      Row({ space: 0 }) {
        Text(key.left !== undefined ? this.toMode(key.left) : ' ')
          .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'left'))
          .width('25%').textAlign(TextAlign.Center)
        Text(this.centerLabel(rowIdx, colIdx, key))
          .fontSize(this.isActive(rowIdx, colIdx) ? 20 : 17)
          .fontColor(kbTheme(this.isDark, this.themeVariant).keyText)
          .fontWeight(FontWeight.Medium).width('50%').textAlign(TextAlign.Center)
        Text(key.right !== undefined ? this.toMode(key.right) : ' ')
          .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'right'))
          .width('25%').textAlign(TextAlign.Center)
      }.width('100%').height('44%')
      Text(key.down !== undefined ? this.toMode(key.down) : ' ')
        .fontSize(11).fontColor(this.hintColor(rowIdx, colIdx, 'down'))
        .width('100%').height('28%').textAlign(TextAlign.Center)
    }
    .width(this.scaleW(this.flickKeyWidthVp)).height('100%')
    .backgroundColor(this.keyBg(rowIdx, colIdx, key)).borderRadius(14)
    .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
    .onTouch((e: TouchEvent) => { this.handleTouch(e, rowIdx, colIdx, key); })
  }

  @Builder layoutPopup() {
    Column() {
      Row() {
        Text('QWERTY').fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
          .backgroundColor(this.hoveredOption === 'QWERTY' ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
          .fontColor(this.hoveredOption === 'QWERTY' ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
          .width('100%')
      }
      Row() {
        Text('フリック').fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
          .backgroundColor(this.hoveredOption === 'FLICK' ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
          .fontColor(this.hoveredOption === 'FLICK' ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
          .width('100%')
      }
    }
    .padding(6).width(200).backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
    .borderRadius(22).shadow({ radius: 6, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 4 })
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
          this.SettingItem('ユーザ辞書', '📕')
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
        this.showThemePicker = true;
      } else if (label === 'ユーザ辞書') {
        InputHandler.getInstance().openUserDict();
      }
      this.showSettingsPanel = false;
    })
  }

  @Builder themePicker() {
    Column() {
      Text('テーマ').fontSize(16).fontWeight(FontWeight.Bold)
        .fontColor(kbTheme(this.isDark, this.themeVariant).previewText)
        .padding({ bottom: 8 })
      Row() {
        Column() {
          Text('クラシック').fontSize(15).textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24, top: 12, bottom: 12 }).borderRadius(16)
            .backgroundColor(AppStorage.get<string>('themeVariant') === 'original' || AppStorage.get<string>('themeVariant') === undefined ?
              kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
            .fontColor(AppStorage.get<string>('themeVariant') === 'original' || AppStorage.get<string>('themeVariant') === undefined ?
              kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
        }
        .onClick(() => {
          AppStorage.setOrCreate('themeVariant', 'original');
          this.showThemePicker = false;
          this.showSettingsPanel = false;
        })
      }
      Row() {
        Column() {
          Text('モダン').fontSize(15).textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24, top: 12, bottom: 12 }).borderRadius(16)
            .backgroundColor(AppStorage.get<string>('themeVariant') === 'glass' ?
              kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
            .fontColor(AppStorage.get<string>('themeVariant') === 'glass' ?
              kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
        }
        .onClick(() => {
          AppStorage.setOrCreate('themeVariant', 'glass');
          this.showThemePicker = false;
          this.showSettingsPanel = false;
        })
      }
    }
    .padding(16).width(200)
    .backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
    .borderRadius(22).shadow({ radius: 6, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 4 })
  }
