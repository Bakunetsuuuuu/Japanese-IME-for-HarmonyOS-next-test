import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

// Chip height (design tokens: "fixed 34px height" pill chips). Landscape gets
// a much shorter bar since vertical space there is scarce.
const CHIP_H = 34;
const CHIP_H_LANDSCAPE = 22;

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.candidates, (candidate: string, index: number) => {
          Row() {
            Text(candidate)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(this.isLandscape ? 12 : 16)
              .fontColor(index === this.selectedIndex ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .height(this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H)
          .padding({ left: this.isLandscape ? 10 : 18, right: this.isLandscape ? 10 : 18 })
          .borderRadius((this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H) / 2)
          .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
          .onClick(() => {
            InputHandler.getInstance().commitCandidate(index);
          })
        }, (candidate: string, index: number) => `${index}-${candidate}`)
      }
      .padding({ left: 4, right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(this.isLandscape ? 22 : 48)
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
