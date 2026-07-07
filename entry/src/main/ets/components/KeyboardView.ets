import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

const ROWS: string[][] = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ー'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
];
const NUMBER_ROW: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

@Component
export struct KeyboardView {
  @Prop inputMode: string = InputMode.HIRAGANA;
  @Prop isLandscape: boolean = false;
  @State isShift: boolean = false;
  @State isCapsLock: boolean = false;
  @State pressedKey: string = '';
  @State showLayoutPopup: boolean = false;
  @State hoveredOption: string = '';
  @State showSettingsPopup: boolean = false;
  @State hoveredSetting: string = '';
  @State showSettingsPanel: boolean = false;
  @State showThemePicker: boolean = false;
  @State oneHandMode: boolean = false;
  @State oneHandSide: boolean = false;
  @StorageLink('keyWidthVp') keyWidthVp: number = 36;
  @StorageLink('specialKeyWidthVp') specialKeyWidthVp: number = 44;
  @StorageLink('spaceKeyWidthVp') spaceKeyWidthVp: number = 160;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';
  @StorageLink('displayWidth') displayWidth: number = 360;

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;
  private layoutMenuTimer: number = -1;
  private touchDownX: number = 0;
  private touchDownY: number = 0;
  private spaceMenuTimer: number = -1;
  private spaceTouchDownX: number = 0;
  private spaceTouchDownY: number = 0;

  private getHandler(): InputHandler { return InputHandler.getInstance(); }

  private startBsRepeat(): void {
    this.getHandler().handleBackspace();
    this.bsDelayTimer = setTimeout(() => {
      this.bsRepeatTimer = setInterval(() => { this.getHandler().handleBackspace(); }, 100);
    }, 500);
  }
  private stopBsRepeat(): void {
    clearTimeout(this.bsDelayTimer); clearInterval(this.bsRepeatTimer);
    this.bsDelayTimer = -1; this.bsRepeatTimer = -1;
  }

  private scaleW(w: number): number {
    if (!this.oneHandMode) return w;
    return Math.floor(w * (this.displayWidth - 56) / this.displayWidth);
  }
  build() {
    Stack() {
            if (this.oneHandMode) {
        Row() {
          if (!this.oneHandSide) {
            this.OneHandPanel()
          }
          Column({ space: 3 }) {
        Row({ space: 3 }) {
          ForEach(NUMBER_ROW, (key: string) => { this.RegularKey(key) }, (key: string) => key)
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)

        ForEach([0, 1], (rowIdx: number) => {
          Row({ space: 3 }) {
            ForEach(ROWS[rowIdx], (key: string) => { this.RegularKey(key) }, (key: string) => key)
          }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)
        }, (rowIdx: number) => String(rowIdx))

        Row({ space: 3 }) {
          this.ShiftKey()
          ForEach(ROWS[2], (key: string) => { this.RegularKey(key) }, (key: string) => key)
          this.BackspaceKey()
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)

        Row({ space: 3 }) {
          this.ModeKey()
          this.FuncKey(this.inputMode === InputMode.ALPHANUMERIC ? ',' : '、', () => {
            const ch = this.inputMode === InputMode.ALPHANUMERIC ? ',' : '、';
            const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
            if (state === InputState.IDLE) { this.getHandler().insertText(ch); }
            else { this.getHandler().handleDirectKana(ch); }
          })
          this.SymbolKey()
          this.SpaceKey()
          this.FuncKey(this.inputMode === InputMode.ALPHANUMERIC ? '.' : '。', () => {
            const ch = this.inputMode === InputMode.ALPHANUMERIC ? '.' : '。';
            const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
            if (state === InputState.IDLE) { this.getHandler().insertText(ch); }
            else { this.getHandler().handleDirectKana(ch); }
          })
          this.EnterKey()
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)
      }
      .width('100%').height('100%')
      .padding({ bottom: 8, top: 4, left: 2, right: 2 })
          .layoutWeight(1)
          if (this.oneHandSide) {
            this.OneHandPanel()
          }
        }
        .width('100%').height('100%')
      } else Column({ space: 3 }) {
        Row({ space: 3 }) {
          ForEach(NUMBER_ROW, (key: string) => { this.RegularKey(key) }, (key: string) => key)
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)

        ForEach([0, 1], (rowIdx: number) => {
          Row({ space: 3 }) {
            ForEach(ROWS[rowIdx], (key: string) => { this.RegularKey(key) }, (key: string) => key)
          }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)
        }, (rowIdx: number) => String(rowIdx))

        Row({ space: 3 }) {
          this.ShiftKey()
          ForEach(ROWS[2], (key: string) => { this.RegularKey(key) }, (key: string) => key)
          this.BackspaceKey()
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)

        Row({ space: 3 }) {
          this.ModeKey()
          this.FuncKey(this.inputMode === InputMode.ALPHANUMERIC ? ',' : '、', () => {
            const ch = this.inputMode === InputMode.ALPHANUMERIC ? ',' : '、';
            const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
            if (state === InputState.IDLE) { this.getHandler().insertText(ch); }
            else { this.getHandler().handleDirectKana(ch); }
          })
          this.SymbolKey()
          this.SpaceKey()
          this.FuncKey(this.inputMode === InputMode.ALPHANUMERIC ? '.' : '。', () => {
            const ch = this.inputMode === InputMode.ALPHANUMERIC ? '.' : '。';
            const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
            if (state === InputState.IDLE) { this.getHandler().insertText(ch); }
            else { this.getHandler().handleDirectKana(ch); }
          })
          this.EnterKey()
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)
      }
      .width('100%').height('100%')
      .padding({ bottom: 8, top: 4, left: 2, right: 2 })

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
        Column() {
          this.settingsPanel()
        }
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

  @Builder RegularKey(value: string) {
    Text((this.isShift || this.isCapsLock) ? value.toUpperCase() : value)
      .fontSize(17).fontColor(kbTheme(this.isDark, this.themeVariant).keyText)
      .fontWeight(this.pressedKey === value ? FontWeight.Bold : FontWeight.Normal)
      .textAlign(TextAlign.Center).width(this.scaleW(this.keyWidthVp)).height('100%')
      .backgroundColor(this.pressedKey === value ? '#D0D0D2' : kbTheme(this.isDark, this.themeVariant).keyBg)
      .borderRadius(12)
      .shadow({ radius: this.pressedKey === value ? 0 : 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: this.pressedKey === value ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = value; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedKey === value) {
            if (value === 'ー') {
              const mode = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
              const ch = mode === InputMode.ALPHANUMERIC ? '-' : 'ー';
              const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
              if (state === InputState.IDLE) { this.getHandler().insertText(ch); }
              else { this.getHandler().handleDirectKana(ch); }
            } else {
              const key = (this.isShift || this.isCapsLock) ? value.toUpperCase() : value;
              this.getHandler().handleKeyPress(key);
            }
          }
          this.pressedKey = '';
          if (this.isShift && !this.isCapsLock) { this.isShift = false; }
        }
      })
  }

  @Builder ShiftKey() {
    Text(this.isCapsLock ? '⇪' : '⇧')
      .fontSize(17).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.scaleW(this.specialKeyWidthVp)).height('100%')
      .backgroundColor(this.isShift || this.isCapsLock ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
      .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(12)
      .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
      .animation({ duration: 100 })
      .onClick(() => {
        if (this.isCapsLock) { this.isCapsLock = false; this.isShift = false; }
        else if (this.isShift) { this.isCapsLock = true; }
        else { this.isShift = true; }
      })
  }

  @Builder BackspaceKey() {
    Text('⌫').fontSize(17).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.scaleW(this.specialKeyWidthVp)).height('100%')
      .backgroundColor(this.pressedKey === '⌫' ? kbTheme(this.isDark, this.themeVariant).keyBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
      .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(12)
      .shadow({ radius: this.pressedKey === '⌫' ? 0 : 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: this.pressedKey === '⌫' ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = '⌫'; this.startBsRepeat(); }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressedKey = ''; this.stopBsRepeat(); }
      })
  }

  @Builder SpaceKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'かな' : 'space')
      .fontSize(14).fontColor(kbTheme(this.isDark, this.themeVariant).keyText).textAlign(TextAlign.Center)
      .width(this.scaleW(this.spaceKeyWidthVp) - this.scaleW(this.keyWidthVp) - 15).height('100%')
      .backgroundColor(this.pressedKey === 'space' ? '#D0D0D2' : kbTheme(this.isDark, this.themeVariant).keyBg)
      .borderRadius(12)
      .shadow({ radius: this.pressedKey === 'space' ? 0 : 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: this.pressedKey === 'space' ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedKey = 'space';
          this.spaceTouchDownX = event.touches[0].x;
          this.spaceTouchDownY = event.touches[0].y;
          this.spaceMenuTimer = setTimeout(() => {
            this.showSettingsPopup = true;
            this.pressedKey = '';
            this.spaceMenuTimer = -1;
          }, 400);
        } else if (event.type === TouchType.Move) {
          const dx = Math.abs(event.touches[0].x - this.spaceTouchDownX);
          if (dx > 15) { clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1; }
          if (this.showSettingsPopup) {
            const hdy = event.touches[0].y - this.spaceTouchDownY;
            if (hdy < -180) { this.hoveredSetting = 'settings'; }
            else if (hdy < -120) { this.hoveredSetting = 'onehand'; }
            else { this.hoveredSetting = ''; }
          }
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1;
          if (this.showSettingsPopup) {
            if (this.hoveredSetting === 'settings') {
              this.showSettingsPopup = false;
              this.showSettingsPanel = true;
            } else if (this.hoveredSetting === 'onehand') {
              this.oneHandMode = !this.oneHandMode;
              this.showSettingsPopup = false;
            }
            this.showSettingsPopup = false; this.hoveredSetting = '';
            this.pressedKey = ''; return;
          }
          if (this.pressedKey === 'space') { this.getHandler().handleSpaceKey(); }
          this.pressedKey = '';
        }
      })
  }

  @Builder ModeKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ')
      .fontSize(12).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.scaleW(this.specialKeyWidthVp)).height('100%')
      .backgroundColor(this.pressedKey === 'mode' ? kbTheme(this.isDark, this.themeVariant).funcKeyBg : kbTheme(this.isDark, this.themeVariant).specialKeyBg)
      .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(12)
      .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedKey = 'mode';
          this.touchDownX = event.touches[0].x; this.touchDownY = event.touches[0].y;
          this.layoutMenuTimer = setTimeout(() => {
            this.showLayoutPopup = true; this.pressedKey = ''; this.layoutMenuTimer = -1;
          }, 400);
        } else if (event.type === TouchType.Move) {
          const dx = Math.abs(event.touches[0].x - this.touchDownX);
          if (dx > 15) { clearTimeout(this.layoutMenuTimer); this.layoutMenuTimer = -1; }
          if (this.showLayoutPopup) {
            const hdy = event.touches[0].y - this.touchDownY;
            if (hdy < -180) { this.hoveredOption = 'QWERTY'; }
            else if (hdy < -120) { this.hoveredOption = 'FLICK'; }
            else { this.hoveredOption = ''; }
          }
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          clearTimeout(this.layoutMenuTimer); this.layoutMenuTimer = -1;
          if (this.showLayoutPopup) {
            if (this.hoveredOption) { AppStorage.setOrCreate('keyboardLayout', this.hoveredOption); }
            this.showLayoutPopup = false; this.hoveredOption = '';
            this.pressedKey = ''; return;
          }
          if (this.pressedKey === 'mode') {
            this.getHandler().commitRaw();
            const current = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
            const next = current === InputMode.HIRAGANA ? InputMode.ALPHANUMERIC : InputMode.HIRAGANA;
            AppStorage.setOrCreate('inputMode', next);
          }
          this.pressedKey = '';
        }
      })
  }

  @Builder FuncKey(label: string, action: () => void) {
    Text(label).fontSize(17).fontColor(kbTheme(this.isDark, this.themeVariant).keyText).textAlign(TextAlign.Center)
      .width(this.scaleW(this.keyWidthVp)).height('100%')
      .backgroundColor(this.pressedKey === label ? '#D0D0D2' : kbTheme(this.isDark, this.themeVariant).keyBg)
      .borderRadius(12)
      .shadow({ radius: this.pressedKey === label ? 0 : 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: this.pressedKey === label ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = label; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedKey === label) { action(); }
          this.pressedKey = '';
        }
      })
  }

  @Builder SymbolKey() {
    Text('記号').fontSize(13).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
      .width(this.scaleW(this.keyWidthVp)).height('100%')
      .backgroundColor(kbTheme(this.isDark, this.themeVariant).keyBg)
      .fontColor(kbTheme(this.isDark, this.themeVariant).keyText).borderRadius(12)
      .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
      .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'symbol'); })
  }

  @Builder EnterKey() {
    Text('⏎').fontSize(17).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.scaleW(this.specialKeyWidthVp)).height('100%')
      .backgroundColor(this.pressedKey === 'enter' ? kbTheme(this.isDark, this.themeVariant).accentStrongBg : kbTheme(this.isDark, this.themeVariant).accentBg)
      .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(12)
      .shadow({ radius: this.pressedKey === 'enter' ? 0 : 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: this.pressedKey === 'enter' ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = 'enter'; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedKey === 'enter') { this.getHandler().handleEnterKey(); }
          this.pressedKey = '';
        }
      })
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
      // Header
      Row() {
        Text('設定').fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark, this.themeVariant).previewText)
      }.width('100%').justifyContent(FlexAlign.Center).height(40)
      .backgroundColor(kbTheme(this.isDark, this.themeVariant).composingBarBg)

      // Settings grid
      Scroll() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.SettingItem('テーマ', '🎨')
          this.SettingItem('ユーザ辞書', '📕')
        }
        .padding(12)
      }
      .layoutWeight(1)

      // Close button
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

  @Builder OneHandPanel() {
    Column() {
      Text('⇄').fontSize(18).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(48).height('35%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(12)
        .margin({ bottom: 4 })
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .onClick(() => { this.oneHandSide = !this.oneHandSide; })
      Text('×').fontSize(18).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .width(48).height('35%')
        .backgroundColor(kbTheme(this.isDark, this.themeVariant).accentBg)
        .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText).borderRadius(12)
        .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 2 })
        .onClick(() => { this.oneHandMode = false; InputHandler.toggleOneHand(false); })
    }
    .width(56).height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

}