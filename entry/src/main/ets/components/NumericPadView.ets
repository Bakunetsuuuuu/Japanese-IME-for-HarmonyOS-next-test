import { InputHandler, InputState } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

// Gboard-style numeric pad, reached via the "123" key on the flick keyboard.
// Same 5-column (side keys + 3 digit columns) grid as FlickKeyboardView so it
// reuses flickKeyWidthVp and never fights that keyboard's width sizing.
const NUM_GRID: string[][] = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['-', '0', '.'],
];

@Component
export struct NumericPadView {
  @StorageLink('flickKeyWidthVp') flickKeyWidthVp: number = 72;
  @StorageLink('inputState') inputState: string = 'IDLE';
  @StorageLink('isDark') isDark: boolean = false;

  private h(): InputHandler { return InputHandler.getInstance(); }

  private bsDelayTimer: number = -1;
  private bsRepeatTimer: number = -1;

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

  private insert(ch: string): void {
    const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
    if (state === InputState.IDLE) {
      this.h().insertText(ch);
    } else {
      this.h().handleDirectKana(ch);
    }
  }

  build() {
    Column({ space: 2 }) {
      ForEach([0, 1, 2, 3], (rowIdx: number) => {
        Row({ space: 3 }) {
          this.LeftKey(rowIdx)
          ForEach(NUM_GRID[rowIdx], (digit: string) => {
            this.DigitKey(digit)
          }, (digit: string) => digit)
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

  @Builder DigitKey(digit: string) {
    Text(digit)
      .fontSize(20)
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .width(this.flickKeyWidthVp).height('100%')
      .backgroundColor(kbTheme(this.isDark).keyBg).fontColor(kbTheme(this.isDark).keyText)
      .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
      .onClick(() => { this.insert(digit); })
  }

  @Builder LeftKey(rowIdx: number) {
    if (rowIdx === 0) {
      Text('あ')
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'kana'); })
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
        .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'symbol'); })
    } else {
      Text('+')
        .fontSize(20).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).keyBg).fontColor(kbTheme(this.isDark).keyText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { this.insert('+'); })
    }
  }

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
      Text('space')
        .fontSize(12).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).specialKeyBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleSpaceKey(); })
    } else {
      Text('⏎')
        .fontSize(16).textAlign(TextAlign.Center)
        .width(this.flickKeyWidthVp).height('100%')
        .backgroundColor(kbTheme(this.isDark).accentBg).fontColor(kbTheme(this.isDark).onAccentText)
        .borderRadius(8).shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
        .onClick(() => { this.h().handleEnterKey(); })
    }
  }
}
