import { InputHandler } from '../ime/KeyboardController';

@Component
export struct BunsetsuBar {
  @Prop segments: string[] = [];
  @Prop currentIndex: number = 0;

  build() {
    Scroll() {
      Row({ space: 2 }) {
        ForEach(this.segments, (seg: string, idx: number) => {
          Text(seg)
            .fontSize(16)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor(idx === this.currentIndex ? '#1565C0' : '#FFFFFF')
            .fontColor(idx === this.currentIndex ? Color.White : Color.Black)
            .border({ width: 1, color: idx === this.currentIndex ? '#1565C0' : '#AAAAAA' })
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
    .backgroundColor('#E0E3E8')
  }
}
