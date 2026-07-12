import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  build() {
    // Portrait wraps onto a second line instead of only ever scrolling
    // horizontally — most candidates are visible up front without a swipe.
    // Landscape keeps the single scrolling row: there's no vertical room to
    // spare there (see KeyboardPage's composing-strip comment).
    Scroll() {
      Flex({
        direction: FlexDirection.Row,
        wrap: this.isLandscape ? FlexWrap.NoWrap : FlexWrap.Wrap
      }) {
        ForEach(this.candidates, (candidate: string, index: number) => {
          Text(candidate)
            .fontSize(this.isLandscape ? 12 : 16)
            .margin({ right: 4, bottom: this.isLandscape ? 0 : 4 })
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
      .width('100%')
    }
    .scrollable(this.isLandscape ? ScrollDirection.Horizontal : ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(this.isLandscape ? 22 : 84)
    .backgroundColor(kbTheme(this.isDark).selectingBarBg)
  }
}
