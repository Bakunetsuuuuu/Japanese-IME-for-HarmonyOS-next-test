import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

@Component
export struct BunsetsuBar {
  @Prop segments: string[] = [];
  @Prop currentIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;

  build() {
    Scroll() {
      Row({ space: 2 }) {
        ForEach(this.segments, (seg: string, idx: number) => {
          Text(seg)
            .fontSize(this.isLandscape ? 12 : 16)
            .padding(this.isLandscape ?
              { left: 6, right: 6, top: 1, bottom: 1 } :
              { left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor(idx === this.currentIndex ? kbTheme(this.isDark).accentStrongBg : kbTheme(this.isDark).candidateBg)
            .fontColor(idx === this.currentIndex ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).keyText)
            .border({ width: 1, color: idx === this.currentIndex ? kbTheme(this.isDark).accentStrongBg : kbTheme(this.isDark).borderColor })
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
    .backgroundColor(kbTheme(this.isDark).selectingBarBg)
  }
}
