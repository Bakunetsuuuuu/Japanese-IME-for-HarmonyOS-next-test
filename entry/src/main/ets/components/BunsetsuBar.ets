import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

const CHIP_H = 34;
const CHIP_H_LANDSCAPE = 22;

@Component
export struct BunsetsuBar {
  @Prop segments: string[] = [];
  @Prop currentIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.segments, (seg: string, idx: number) => {
          Row() {
            Text(seg)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(this.isLandscape ? 12 : 16)
              .fontColor(idx === this.currentIndex ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .height(this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H)
          .padding({ left: this.isLandscape ? 8 : 16, right: this.isLandscape ? 8 : 16 })
          .borderRadius((this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H) / 2)
          .backgroundColor(idx === this.currentIndex ? kbTheme(this.isDark).accentStrong : kbTheme(this.isDark).candidateBg)
          .border({ width: 1, color: idx === this.currentIndex ? kbTheme(this.isDark).accentStrong : kbTheme(this.isDark).divider })
          .onClick(() => {
            InputHandler.getInstance().selectBunsetsuSegment(idx);
          })
        }, (seg: string, idx: number) => `${idx}-${seg}`)
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
