import { InputHandler, InputMode, InputState } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

const ROWS: string[][] = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  // '-' always inserts ー (the long-vowel mark) via ROMAJI_TABLE — romaji kana
  // input has no other reachable key for it, since it isn't part of any
  // romaji consonant sequence. Tacked onto the middle row rather than the
  // number row so it still shares the same 10-key width as row 0. Only used
  // for kana input (see ROW1_ALPHANUMERIC below for the plain-alphabet row,
  // where a trailing '-' has no such purpose and is just clutter).
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '-'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
];

// Same middle row as ROWS[1] but without the kana-only ー shortcut key, used
// when inputMode is ALPHANUMERIC (direct alphabet input, not romaji-to-kana).
const ROW1_ALPHANUMERIC: string[] = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];

const NUMBER_ROW: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

// Key corner radius (design tokens: "regular keys 14px").
const KEY_RADIUS = 14;

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
      // Number row — dropped in landscape to give the letter rows more height;
      // vertical space is tight there and this row is the least-used one.
      if (!this.isLandscape) {
        Row({ space: 5 }) {
          ForEach(NUMBER_ROW, (key: string) => {
            this.RegularKey(key, this.keyWidthVp)
          }, (key: string) => key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      }

      // QWERTY rows 0 and 1. Row 1 drops the kana-only ー-shortcut '-' key in
      // ALPHANUMERIC mode, where it serves no purpose.
      ForEach([0, 1], (rowIdx: number) => {
        Row({ space: 5 }) {
          ForEach(rowIdx === 1 && this.inputMode === InputMode.ALPHANUMERIC ? ROW1_ALPHANUMERIC : ROWS[rowIdx], (key: string) => {
            this.RegularKey(key, this.keyWidthVp)
          }, (key: string) => key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      }, (rowIdx: number) => String(rowIdx))

      // Bottom letter row (z-m) with shift and backspace
      Row({ space: 5 }) {
        this.ShiftKey()
        ForEach(ROWS[2], (key: string) => {
          this.RegularKey(key, this.keyWidthVp)
        }, (key: string) => key)
        this.BackspaceKey()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)

      // Function row. 文節 (per-segment conversion — lets you fix up
      // individual bunsetsu of a converted sentence instead of only ever
      // choosing among whole-sentence candidates; FlickKeyboardView already
      // exposes this via its own dedicated key) sits right after the space
      // key, which is sized shorter to make room for it.
      Row({ space: 5 }) {
        this.ModeKey()
        this.FuncKey(this.inputMode === InputMode.ALPHANUMERIC ? ',' : '、', () => {
          const ch = this.inputMode === InputMode.ALPHANUMERIC ? ',' : '、';
          const state = AppStorage.get<string>('inputState') ?? InputState.IDLE;
          if (state === InputState.IDLE) { this.getHandler().insertText(ch); }
          else { this.getHandler().handleDirectKana(ch); }
        })
        this.SpaceKey()
        this.BunsetsuKey()
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
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: 8, top: 4, left: 2, right: 2 })
  }

  @Builder RegularKey(value: string, width: number) {
    // Read isShift/isCapsLock directly here (not via a by-value Builder param)
    // so the label re-renders when the shift state changes.
    Text((this.isShift || this.isCapsLock) ? value.toUpperCase() : value)
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(17)
      .fontWeight(FontWeight.Medium)
      .fontColor(kbTheme(this.isDark).textPrimary)
      .textAlign(TextAlign.Center)
      .width(width)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).keyBg)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
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
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height('100%')
      .backgroundColor(this.isShift || this.isCapsLock ? kbTheme(this.isDark).accent : kbTheme(this.isDark).specialBg)
      .fontColor(kbTheme(this.isDark).onAccent)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
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
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).specialBg)
      .fontColor(kbTheme(this.isDark).onAccent)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.startBsRepeat();
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.stopBsRepeat();
        }
      })
  }

  @Builder BunsetsuKey() {
    Text('文節')
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(13)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).specialBg)
      .fontColor(kbTheme(this.isDark).onAccent)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onClick(() => {
        this.getHandler().handleBunsetsu();
      })
  }

  @Builder SpaceKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'かな' : 'space')
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(15)
      .fontColor(kbTheme(this.isDark).textPrimary)
      .textAlign(TextAlign.Center)
      .width(this.spaceKeyWidthVp)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).keyBg)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onClick(() => {
        this.getHandler().handleSpaceKey();
      })
  }

  @Builder ModeKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'あA' : 'Aあ')
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(13)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).specialBg)
      .fontColor(kbTheme(this.isDark).onAccent)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onClick(() => {
        this.getHandler().commitRaw();
        const current = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
        const next = current === InputMode.HIRAGANA ? InputMode.ALPHANUMERIC : InputMode.HIRAGANA;
        AppStorage.setOrCreate('inputMode', next);
      })
  }

  @Builder FuncKey(label: string, action: () => void) {
    Text(label)
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(17)
      .fontWeight(FontWeight.Medium)
      .fontColor(kbTheme(this.isDark).textPrimary)
      .textAlign(TextAlign.Center)
      .width(this.keyWidthVp)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).keyBg)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onClick(action)
  }

  @Builder EnterKey() {
    Text('⏎')
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(this.specialKeyWidthVp)
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).accent)
      .fontColor(kbTheme(this.isDark).onAccent)
      .borderRadius(KEY_RADIUS)
      .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
      .onClick(() => {
        this.getHandler().handleEnterKey();
      })
  }
}
