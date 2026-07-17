import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(this.candidates, (candidate: string, index: number) => {
          Text(candidate)
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(this.isLandscape ? 12 : 16)
            .padding(this.isLandscape ?
              { left: 8, right: 8, top: 2, bottom: 2 } :
              { left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(4)
            .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).candidateBg)
            .fontColor(index === this.selectedIndex ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).keyText)
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
    .backgroundColor(kbTheme(this.isDark).selectingBarBg)
  }
}
