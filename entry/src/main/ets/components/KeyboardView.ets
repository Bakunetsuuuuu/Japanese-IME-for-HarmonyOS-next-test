import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';

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

  private get handler(): InputHandler {
    return InputHandler.getInstance();
  }

  private displayKey(key: string): string {
    return (this.isShift || this.isCapsLock) ? key.toUpperCase() : key;
  }

  private keyWidth(): number {
    return this.isLandscape ? 48 : 36;
  }

  private specialKeyWidth(): number {
    return this.isLandscape ? 56 : 44;
  }

  build() {
    Column({ space: 5 }) {
      // Number row
      Row({ space: 4 }) {
        ForEach(NUMBER_ROW, (key: string) => {
          this.RegularKey(key, key)
        }, (key: string) => key)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // QWERTY rows 0 and 1
      ForEach([0, 1], (rowIdx: number) => {
        Row({ space: 4 }) {
          ForEach(ROWS[rowIdx], (key: string) => {
            this.RegularKey(this.displayKey(key), key)
          }, (key: string) => key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }, (rowIdx: number) => String(rowIdx))

      // Bottom letter row (z-m) with shift and backspace
      Row({ space: 4 }) {
        this.ShiftKey()
        ForEach(ROWS[2], (key: string) => {
          this.RegularKey(this.displayKey(key), key)
        }, (key: string) => key)
        this.BackspaceKey()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // Function row
      Row({ space: 4 }) {
        this.ModeKey()
        this.FuncKey('、', () => {
          this.handler.commitTopCandidate();
          this.handler.insertText('、');
        })
        this.SpaceKey()
        this.FuncKey('。', () => {
          this.handler.commitTopCandidate();
          this.handler.insertText('。');
        })
        this.EnterKey()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ bottom: 8, top: 4, left: 2, right: 2 })
  }

  @Builder RegularKey(label: string, value: string) {
    Text(label)
      .fontSize(17)
      .fontColor(Color.Black)
      .textAlign(TextAlign.Center)
      .width(this.keyWidth())
      .height(44)
      .backgroundColor('#FFFFFF')
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        const key = (this.isShift || this.isCapsLock) ? value.toUpperCase() : value;
        this.handler.handleKeyPress(key);
        if (this.isShift && !this.isCapsLock) {
          this.isShift = false;
        }
      })
  }

  @Builder ShiftKey() {
    Text(this.isCapsLock ? '⇪' : '⇧')
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidth())
      .height(44)
      .backgroundColor(this.isShift || this.isCapsLock ? '#4A90E2' : '#ADB5BD')
      .fontColor(Color.White)
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
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
      .width(this.specialKeyWidth())
      .height(44)
      .backgroundColor('#ADB5BD')
      .fontColor(Color.White)
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.handler.handleBackspace();
      })
  }

  @Builder SpaceKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'かな'
      : this.inputMode === InputMode.KATAKANA ? 'カナ'
      : 'space')
      .fontSize(14)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(44)
      .backgroundColor('#FFFFFF')
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.handler.handleSpaceKey();
      })
  }

  @Builder ModeKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'あ'
      : this.inputMode === InputMode.KATAKANA ? 'ア'
      : 'A')
      .fontSize(15)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidth())
      .height(44)
      .backgroundColor('#ADB5BD')
      .fontColor(Color.White)
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.handler.commitTopCandidate();
        const current = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
        const next = current === InputMode.HIRAGANA ? InputMode.KATAKANA
          : current === InputMode.KATAKANA ? InputMode.ALPHANUMERIC
          : InputMode.HIRAGANA;
        AppStorage.setOrCreate('inputMode', next);
      })
  }

  @Builder FuncKey(label: string, action: () => void) {
    Text(label)
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.keyWidth())
      .height(44)
      .backgroundColor('#FFFFFF')
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(action)
  }

  @Builder EnterKey() {
    Text('⏎')
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidth())
      .height(44)
      .backgroundColor('#4A90E2')
      .fontColor(Color.White)
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.handler.handleEnterKey();
      })
  }
}
