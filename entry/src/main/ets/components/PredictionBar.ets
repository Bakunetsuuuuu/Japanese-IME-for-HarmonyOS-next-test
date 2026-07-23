import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

// Next-word prediction strip (次単語予測). Shown in the IDLE state right after a
// word is committed, in the same row a conversion CandidateBar would occupy.
// Visually distinguished from conversion candidates (no highlighted [0]) so it
// reads as a suggestion strip, not an active-conversion candidate list. Tapping
// a chip inserts that word and chains to the next prediction — see
// InputHandler.commitPrediction.
const CHIP_H = 34;
const CHIP_H_LANDSCAPE = 22;

@Component
export struct PredictionBar {
  @Prop predictions: string[] = [];
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.predictions, (word: string, index: number) => {
          Row() {
            Text(word)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(this.isLandscape ? 12 : 16)
              .fontColor(kbTheme(this.isDark).textPrimary)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .height(this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H)
          .padding({ left: this.isLandscape ? 10 : 18, right: this.isLandscape ? 10 : 18 })
          .borderRadius((this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H) / 2)
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
    .height(this.isLandscape ? 22 : 48)
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
