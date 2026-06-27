import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { KbTheme, kbTheme } from './Theme';

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
  // Key widths pre-computed from screen density in KeyboardController
  @StorageLink('keyWidthVp') keyWidthVp: number = 36;
  @StorageLink('specialKeyWidthVp') specialKeyWidthVp: number = 44;
  @StorageLink('spaceKeyWidthVp') spaceKeyWidthVp: number = 160;
  @StorageLink('isDark') isDark: boolean = false;

  private get t(): KbTheme {
    return kbTheme(this.isDark);
  }

  private getHandler(): InputHandler {
    return InputHandler.getInstance();
  }

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;

  private startBsRepeat(): void {
    this.getHandler().handleBackspace();
    this.bsDelayTimer = setTimeout(() => {
      this.bsRepeatTimer = setInterval(() => {
        this.getHandler().handleBackspace();
      }, 100);
    }, 500);
  }

  private stopBsRepeat(): void {
    clearTimeout(this.bsDelayTimer);
    clearInterval(this.bsRepeatTimer);
    this.bsDelayTimer = -1;
    this.bsRepeatTimer = -1;
  }

  build() {
    Column({ space: 5 }) {
      // Number row
      Row({ space: 2 }) {
        ForEach(NUMBER_ROW, (key: string) => {
          this.RegularKey(key)
        }, (key: string) => key)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // QWERTY rows 0 and 1
      ForEach([0, 1], (rowIdx: number) => {
        Row({ space: 2 }) {
          ForEach(ROWS[rowIdx], (key: string) => {
            this.RegularKey(key)
          }, (key: string) => key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }, (rowIdx: number) => String(rowIdx))

      // Bottom letter row (z-m) with shift and backspace
      Row({ space: 2 }) {
        this.ShiftKey()
        ForEach(ROWS[2], (key: string) => {
          this.RegularKey(key)
        }, (key: string) => key)
        this.BackspaceKey()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // Function row
      Row({ space: 2 }) {
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
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ bottom: 8, top: 4, left: 2, right: 2 })
  }

  @Builder RegularKey(value: string) {
    // Read isShift/isCapsLock directly here (not via a by-value Builder param)
    // so the label re-renders when the shift state changes.
    Text((this.isShift || this.isCapsLock) ? value.toUpperCase() : value)
      .fontSize(17)
      .fontColor(this.t.keyText)
      .textAlign(TextAlign.Center)
      .width(this.keyWidthVp)
      .height(44)
      .backgroundColor(this.t.keyBg)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onClick(() => {
        const key = (this.isShift || this.isCapsLock) ? value.toUpperCase() : value;
        this.getHandler().handleKeyPress(key);
        if (this.isShift && !this.isCapsLock) {
          this.isShift = false;
        }
      })
  }

  @Builder ShiftKey() {
    Text(this.isCapsLock ? '⇪' : '⇧')
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height(44)
      .backgroundColor(this.isShift || this.isCapsLock ? this.t.accentBg : this.t.specialKeyBg)
      .fontColor(this.t.onAccentText)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onClick(() => {
        if (this.isCapsLock) {
          this.isCapsLock = false;
          this.isShift = false;
        } else if (this.isShift) {
          this.isCapsLock = true;
        } else {
          this.isShift = true;
        }
      })
  }

  @Builder BackspaceKey() {
    Text('⌫')
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height(44)
      .backgroundColor(this.t.specialKeyBg)
      .fontColor(this.t.onAccentText)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.startBsRepeat();
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.stopBsRepeat();
        }
      })
  }

  @Builder SpaceKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'かな' : 'space')
      .fontSize(14)
      .fontColor(this.t.keyText)
      .textAlign(TextAlign.Center)
      .width(this.spaceKeyWidthVp)
      .height(44)
      .backgroundColor(this.t.keyBg)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onClick(() => {
        this.getHandler().handleSpaceKey();
      })
  }

  @Builder ModeKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ')
      .fontSize(12)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height(44)
      .backgroundColor(this.t.specialKeyBg)
      .fontColor(this.t.onAccentText)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onClick(() => {
        this.getHandler().commitRaw();
        const current = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
        const next = current === InputMode.HIRAGANA ? InputMode.ALPHANUMERIC : InputMode.HIRAGANA;
        AppStorage.setOrCreate('inputMode', next);
      })
  }

  @Builder FuncKey(label: string, action: () => void) {
    Text(label)
      .fontSize(17)
      .fontColor(this.t.keyText)
      .textAlign(TextAlign.Center)
      .width(this.keyWidthVp)
      .height(44)
      .backgroundColor(this.t.keyBg)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onClick(action)
  }

  @Builder EnterKey() {
    Text('⏎')
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height(44)
      .backgroundColor(this.t.accentBg)
      .fontColor(this.t.onAccentText)
      .borderRadius(5)
      .shadow({ radius: 1, color: this.t.shadowColor, offsetY: 2 })
      .onClick(() => {
        this.getHandler().handleEnterKey();
      })
  }
}
