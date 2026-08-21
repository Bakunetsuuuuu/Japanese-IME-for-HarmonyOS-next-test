import { router } from '@kit.ArkUI';
import { JP_FONT_FAMILY } from './JpFont';
import { kbTheme } from './Theme';

// Shared chrome for PrivacyPolicy / License. Header matches Index
// (52vp bar, 16vp padding, divider, panelBg). Body is a single plain
// text block like the old in-keyboard license view, not cards.
@Component
export struct LegalDocView {
  @Prop pageTitle: string = '';
  @Prop bodyText: string = '';
  @StorageLink('isDark') isDark: boolean = false;

  build() {
    Column() {
      Row() {
        Row() {
          Text('‹ 戻る')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(kbTheme(this.isDark).accent)
            .onClick(() => { router.back(); })
        }
        .width(56)
        .justifyContent(FlexAlign.Start)

        Text(this.pageTitle)
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row()
          .width(56)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

      Scroll() {
        Text(this.bodyText)
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .lineHeight(20)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
