import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

const CARD_RADIUS = 16;

// 取消 panel: reached from the flick keyboard's left-column key when the
// numeric pad is disabled in settings (see FlickKeyboardView.ets's LeftKey
// and SettingsBar's 数字パッド toggle). Lists every individually deleted
// character InputHandler.recordDeletedChar has logged (up to 100, newest
// first -- see KeyboardController.ets), as a tap-to-restore chip grid rather
// than one-row-per-character list rows, since a single glyph doesn't need a
// full-width row the way a clipboard-history line of real text does.
@Component
export struct DeleteHistoryView {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('deletedCharHistory') deletedCharHistory: string[] = [];

  private h(): InputHandler { return InputHandler.getInstance(); }

  build() {
    Column({ space: 0 }) {
      // ── Top row: back to kana / title / clear-all ──
      Row({ space: 4 }) {
        Text('←')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .width(48).height(40)
          .fontColor(kbTheme(this.isDark).onAccent)
          .backgroundColor(kbTheme(this.isDark).specialBg)
          .borderRadius(20)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        Text('取消（削除した文字）')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text('全削除')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width(48).height(40)
          .textAlign(TextAlign.Center)
          .opacity(this.deletedCharHistory.length > 0 ? 1 : 0.3)
          .onClick(() => {
            if (this.deletedCharHistory.length > 0) { this.h().clearDeletedCharHistory(); }
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      // ── Body ──
      if (this.deletedCharHistory.length === 0) {
        Text('削除した文字の履歴はありません')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Column() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.deletedCharHistory, (ch: string, index: number) => {
                Text(ch)
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(18)
                  .textAlign(TextAlign.Center)
                  .width(42).height(42)
                  .fontColor(kbTheme(this.isDark).textPrimary)
                  .backgroundColor(kbTheme(this.isDark).keyBg)
                  .borderRadius(10)
                  .margin({ right: 6, bottom: 6 })
                  .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
                  .onClick(() => { this.h().restoreDeletedChar(index); })
              }, (ch: string, index: number) => `${index}-${ch}`)
            }
            .width('100%')
          }
          .backgroundColor(kbTheme(this.isDark).cardBg)
          .borderRadius(CARD_RADIUS)
          .padding(12)
          .margin(12)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
