import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop showExpand: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('candidateExpanded') candidateExpanded: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';
  @State pressedIdx: number = -1;
  private startX: number = 0;
  private startY: number = 0;

  build() {
    Row() {
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.candidates, (candidate: string, index: number) => {
            Text(candidate)
              .fontSize(16).fontWeight(index === this.selectedIndex ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(12)
              .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark, this.themeVariant).accentBg :
                this.pressedIdx === index ? '#D0D0D2' : kbTheme(this.isDark, this.themeVariant).candidateBg)
              .fontColor(index === this.selectedIndex ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
              .animation({ duration: 80 })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.pressedIdx = index; const t = e.touches[0]; this.startX = t.x; this.startY = t.y;
                } else if (e.type === TouchType.Up) {
                  if (this.pressedIdx === index &&
                      Math.abs(e.changedTouches[0].x - this.startX) < 10 &&
                      Math.abs(e.changedTouches[0].y - this.startY) < 10) {
                    InputHandler.getInstance().commitCandidate(index);
                  }
                  this.pressedIdx = -1;
                } else if (e.type === TouchType.Cancel) { this.pressedIdx = -1; }
              })
          }, (candidate: string, index: number) => `${index}-${candidate}`)
        }.padding({ left: 4, right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1).height(48)

      if (this.showExpand && this.candidates.length > 1) {
        Text(this.candidateExpanded ? '▲' : '▼')
          .fontSize(14).fontWeight(FontWeight.Bold).fontColor(kbTheme(this.isDark, this.themeVariant).subText)
          .textAlign(TextAlign.Center).width(40).height(36)
          .margin({ right: 4 })
          .onClick(() => { AppStorage.setOrCreate('candidateExpanded', !this.candidateExpanded); })
      }
    }
    .width('100%').height(48).backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
  }
}
