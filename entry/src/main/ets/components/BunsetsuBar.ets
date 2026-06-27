import { InputHandler } from '../ime/KeyboardController';
import { KbTheme, kbTheme } from './Theme';

@Component
export struct BunsetsuBar {
  @Prop segments: string[] = [];
  @Prop currentIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;

  private get t(): KbTheme {
    return kbTheme(this.isDark);
  }

  build() {
    Scroll() {
      Row({ space: 2 }) {
        ForEach(this.segments, (seg: string, idx: number) => {
          Text(seg)
            .fontSize(16)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor(idx === this.currentIndex ? this.t.accentStrongBg : this.t.candidateBg)
            .fontColor(idx === this.currentIndex ? this.t.onAccentText : this.t.keyText)
            .border({ width: 1, color: idx === this.currentIndex ? this.t.accentStrongBg : this.t.borderColor })
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
    .height(48)
    .backgroundColor(this.t.selectingBarBg)
  }
}
