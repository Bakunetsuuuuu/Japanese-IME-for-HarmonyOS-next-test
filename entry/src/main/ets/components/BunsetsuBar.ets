import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

@Component
export struct BunsetsuBar {
  @Prop segments: string[] = [];
  @Prop currentIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';
  @State pressedIdx: number = -1;
  private startX: number = 0;
  private startY: number = 0;

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(this.segments, (seg: string, idx: number) => {
          Text(seg)
            .fontSize(16).fontWeight(idx === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 }).borderRadius(12)
            .backgroundColor(idx === this.currentIndex ? kbTheme(this.isDark, this.themeVariant).accentStrongBg :
              this.pressedIdx === idx ? '#D0D0D2' : kbTheme(this.isDark, this.themeVariant).candidateBg)
            .fontColor(idx === this.currentIndex ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
            .animation({ duration: 150 })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedIdx = idx; const t = e.touches[0]; this.startX = t.x; this.startY = t.y;
              } else if (e.type === TouchType.Up) {
                if (this.pressedIdx === idx &&
                    Math.abs(e.changedTouches[0].x - this.startX) < 10 &&
                    Math.abs(e.changedTouches[0].y - this.startY) < 10) {
                  InputHandler.getInstance().selectBunsetsuSegment(idx);
                }
                this.pressedIdx = -1;
              } else if (e.type === TouchType.Cancel) { this.pressedIdx = -1; }
            })
        }, (seg: string, idx: number) => `${idx}-${seg}`)
      }.padding({ left: 4, right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(48)
    .backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
  }
}
