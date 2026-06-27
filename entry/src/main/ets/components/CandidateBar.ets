import { InputHandler } from '../ime/KeyboardController';
import { KbTheme, kbTheme } from './Theme';

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;

  private get t(): KbTheme {
    return kbTheme(this.isDark);
  }

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(this.candidates, (candidate: string, index: number) => {
          Text(candidate)
            .fontSize(16)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(4)
            .backgroundColor(index === this.selectedIndex ? this.t.accentBg : this.t.candidateBg)
            .fontColor(index === this.selectedIndex ? this.t.onAccentText : this.t.keyText)
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
    .height(48)
    .backgroundColor(this.t.selectingBarBg)
  }
}
