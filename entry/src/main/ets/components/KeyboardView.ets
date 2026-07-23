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
  @State showSpaceMenu: boolean = false;
  @State hoveredSpaceOption: string = '';
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
  private spaceMenuTimer: number = -1;
  private spaceTouchDownX: number = 0;
  private spaceTouchDownY: number = 0;

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
    Stack() {
      Column({ space: 5 }) {
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

      if (this.showSpaceMenu) {
        Column()
          .width('100%')
          .height('100%')
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
          }
          Row() {
            Text('片手キーボード')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(15).textAlign(TextAlign.Center)
              .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(16)
              .backgroundColor(this.hoveredSpaceOption === 'onehand' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
              .fontColor(this.hoveredSpaceOption === 'onehand' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
              .width('100%')
          }
        }
        .padding(6).width(180)
        .backgroundColor(kbTheme(this.isDark).panelBg)
        .borderRadius(22)
        .shadow({ radius: 6, color: kbTheme(this.isDark).shadowColor, offsetY: 4 })
        .alignItems(HorizontalAlign.End)
        .padding({ right: 8, bottom: '22%' })
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .height('100%')
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
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.spaceTouchDownX = e.touches[0].x;
          this.spaceTouchDownY = e.touches[0].y;
          this.spaceMenuTimer = setTimeout(() => {
            this.showSpaceMenu = true;
            this.spaceMenuTimer = -1;
          }, 400);
        } else if (e.type === TouchType.Move) {
          const dx = Math.abs(e.touches[0].x - this.spaceTouchDownX);
          if (dx > 15) { clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1; }
          if (this.showSpaceMenu) {
            const hdy = e.touches[0].y - this.spaceTouchDownY;
            if (hdy < -120) { this.hoveredSpaceOption = 'settings'; }
            else if (hdy < -60) { this.hoveredSpaceOption = 'onehand'; }
            else { this.hoveredSpaceOption = ''; }
          }
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          clearTimeout(this.spaceMenuTimer); this.spaceMenuTimer = -1;
          if (this.showSpaceMenu) {
            if (this.hoveredSpaceOption === 'settings') {
              AppStorage.setOrCreate('keyboardSubMode', 'settings');
            } else if (this.hoveredSpaceOption === 'onehand') {
              const cur = AppStorage.get<boolean>('oneHandedMode') ?? false;
              AppStorage.setOrCreate('oneHandedMode', !cur);
            }
            this.showSpaceMenu = false; this.hoveredSpaceOption = '';
            return;
          }
          this.getHandler().handleSpaceKey();
        }
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
        this.getHandler().cycleInputMode();
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
