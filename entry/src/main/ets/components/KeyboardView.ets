import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

const ROWS: string[][] = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
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
  @StorageLink('keyWidthVp') keyWidthVp: number = 36;
  @StorageLink('specialKeyWidthVp') specialKeyWidthVp: number = 44;
  @StorageLink('spaceKeyWidthVp') spaceKeyWidthVp: number = 160;
  @StorageLink('isDark') isDark: boolean = false;

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;
  private layoutMenuTimer: number = -1;
  private touchDownX: number = 0;
  private touchDownY: number = 0;

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

  build() {
    Stack() {
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
    }
    .width('100%').height('100%')
  }

  @Builder RegularKey(value: string) {
    Text((this.isShift || this.isCapsLock) ? value.toUpperCase() : value)
      .fontSize(17).fontColor(kbTheme(this.isDark).keyText)
      .fontWeight(this.pressedKey === value ? FontWeight.Bold : FontWeight.Normal)
      .textAlign(TextAlign.Center).width(this.keyWidthVp).height('100%')
      .backgroundColor(this.pressedKey === value ? '#D0D0D2' : kbTheme(this.isDark).keyBg)
      .borderRadius(12)
      .shadow({ radius: this.pressedKey === value ? 0 : 1, color: kbTheme(this.isDark).shadowColor, offsetY: this.pressedKey === value ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = value; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          const key = (this.isShift || this.isCapsLock) ? value.toUpperCase() : value;
          if (this.pressedKey === value) { this.getHandler().handleKeyPress(key); }
          this.pressedKey = '';
          if (this.isShift && !this.isCapsLock) { this.isShift = false; }
        }
      })
  }

  @Builder ShiftKey() {
    Text(this.isCapsLock ? '⇪' : '⇧')
      .fontSize(17).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp).height('100%')
      .backgroundColor(this.isShift || this.isCapsLock ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).specialKeyBg)
      .fontColor(kbTheme(this.isDark).onAccentText).borderRadius(12)
      .shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
      .animation({ duration: 100 })
      .onClick(() => {
        if (this.isCapsLock) { this.isCapsLock = false; this.isShift = false; }
        else if (this.isShift) { this.isCapsLock = true; }
        else { this.isShift = true; }
      })
  }

  @Builder BackspaceKey() {
    Text('⌫').fontSize(17).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp).height('100%')
      .backgroundColor(this.pressedKey === '⌫' ? kbTheme(this.isDark).keyBg : kbTheme(this.isDark).specialKeyBg)
      .fontColor(kbTheme(this.isDark).onAccentText).borderRadius(12)
      .shadow({ radius: this.pressedKey === '⌫' ? 0 : 1, color: kbTheme(this.isDark).shadowColor, offsetY: this.pressedKey === '⌫' ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = '⌫'; this.startBsRepeat(); }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressedKey = ''; this.stopBsRepeat(); }
      })
  }

  @Builder SpaceKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'かな' : 'space')
      .fontSize(14).fontColor(kbTheme(this.isDark).keyText).textAlign(TextAlign.Center)
      .width(this.spaceKeyWidthVp).height('100%')
      .backgroundColor(this.pressedKey === 'space' ? '#D0D0D2' : kbTheme(this.isDark).keyBg)
      .borderRadius(12)
      .shadow({ radius: this.pressedKey === 'space' ? 0 : 1, color: kbTheme(this.isDark).shadowColor, offsetY: this.pressedKey === 'space' ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = 'space'; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedKey === 'space') { this.getHandler().handleSpaceKey(); }
          this.pressedKey = '';
        }
      })
  }

  @Builder ModeKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ')
      .fontSize(12).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp).height('100%')
      .backgroundColor(this.pressedKey === 'mode' ? kbTheme(this.isDark).funcKeyBg : kbTheme(this.isDark).specialKeyBg)
      .fontColor(kbTheme(this.isDark).onAccentText).borderRadius(12)
      .shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
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
    Text(label).fontSize(17).fontColor(kbTheme(this.isDark).keyText).textAlign(TextAlign.Center)
      .width(this.keyWidthVp).height('100%')
      .backgroundColor(this.pressedKey === label ? '#D0D0D2' : kbTheme(this.isDark).keyBg)
      .borderRadius(12)
      .shadow({ radius: this.pressedKey === label ? 0 : 1, color: kbTheme(this.isDark).shadowColor, offsetY: this.pressedKey === label ? 0 : 2 })
      .animation({ duration: 80 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedKey = label; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedKey === label) { action(); }
          this.pressedKey = '';
        }
      })
  }

  @Builder EnterKey() {
    Text('⏎').fontSize(17).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp).height('100%')
      .backgroundColor(this.pressedKey === 'enter' ? kbTheme(this.isDark).accentStrongBg : kbTheme(this.isDark).accentBg)
      .fontColor(kbTheme(this.isDark).onAccentText).borderRadius(12)
      .shadow({ radius: this.pressedKey === 'enter' ? 0 : 1, color: kbTheme(this.isDark).shadowColor, offsetY: this.pressedKey === 'enter' ? 0 : 2 })
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
          .backgroundColor(this.hoveredOption === 'QWERTY' ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).candidateBg)
          .fontColor(this.hoveredOption === 'QWERTY' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).keyText)
          .width('100%')
      }
      Row() {
        Text('フリック').fontSize(15).textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
          .backgroundColor(this.hoveredOption === 'FLICK' ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).candidateBg)
          .fontColor(this.hoveredOption === 'FLICK' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).keyText)
          .width('100%')
      }
    }
    .padding(6).width(200).backgroundColor(kbTheme(this.isDark).selectingBarBg)
    .borderRadius(22).shadow({ radius: 6, color: kbTheme(this.isDark).shadowColor, offsetY: 4 })
  }
}
