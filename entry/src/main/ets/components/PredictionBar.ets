import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

// Next-word prediction strip (次単語予測). Shown in the IDLE state right after a
// word is committed, in the same row a conversion CandidateBar would occupy.
// Visually distinguished from conversion candidates (no highlighted [0]) so it
// reads as a suggestion strip, not an active-conversion candidate list. Tapping
// a chip inserts that word and chains to the next prediction — see
// InputHandler.commitPrediction.
@Component
export struct PredictionBar {
  @Prop predictions: string[] = [];
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  // 呼び出し側 (KeyboardPage) が比率計算した実際のバー高さ (vp)。
  // CandidateBar.barHeightVp と同じ理由・同じ値を渡す -- ここだけ固定の
  // ままだと、同じ行を occupies する CandidateBar 側だけ縮んで
  // PredictionBar 側は縮まないというズレが起きる。
  @Prop barHeightVp: number = 48;

  private chipHeightVp(): number {
    return Math.max(18, this.barHeightVp - 6);
  }

  private chipFontSize(): number {
    return Math.max(10, Math.min(16, this.chipHeightVp() * 0.42));
  }

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.predictions, (word: string, index: number) => {
          Row() {
            Text(word)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(this.chipFontSize())
              .fontColor(kbTheme(this.isDark).textPrimary)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .height(this.chipHeightVp())
          .padding({ left: this.isLandscape ? 10 : 18, right: this.isLandscape ? 10 : 18 })
          .borderRadius(this.chipHeightVp() / 2)
          .backgroundColor(kbTheme(this.isDark).candidateBg)
          .onClick(() => {
            InputHandler.getInstance().commitPrediction(index);
          })
        }, (word: string, index: number) => `p${index}-${word}`)
      }
      .padding({ left: 4, right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(this.barHeightVp)
    .backgroundColor(kbTheme(this.isDark).previewBg)
  }
}
