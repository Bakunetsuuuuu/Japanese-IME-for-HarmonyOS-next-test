import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

@Component
export struct ExpandedCandidateView {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;

  build() {
    Column() {
      Row() {
        Text('候補一覧').fontSize(14).fontColor(kbTheme(this.isDark).subText).layoutWeight(1)
        Text('閉じる').fontSize(14).fontColor(kbTheme(this.isDark).accentBg)
          .padding({ left: 12, right: 12, top: 4, bottom: 4 }).borderRadius(8)
          .backgroundColor(kbTheme(this.isDark).candidateBg)
          .onClick(() => { AppStorage.setOrCreate('candidateExpanded', false); })
      }
      .width('100%').height(36).padding({ left: 12, right: 8 }).alignItems(VerticalAlign.Center)
      .backgroundColor(kbTheme(this.isDark).composingBarBg)

      Scroll() {
        Grid() {
          ForEach(this.candidates, (candidate: string, index: number) => {
            GridItem() {
              Text(candidate).fontSize(17)
                .fontWeight(index === this.selectedIndex ? FontWeight.Bold : FontWeight.Normal)
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: 12, bottom: 12 }).borderRadius(10)
                .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).candidateBg)
                .fontColor(index === this.selectedIndex ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).keyText)
            }
            .onClick(() => {
              InputHandler.getInstance().commitCandidate(index);
              AppStorage.setOrCreate('candidateExpanded', false);
            })
          }, (candidate: string, index: number) => `${index}-${candidate}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr').rowsGap(6).columnsGap(6)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }
      .width('100%').layoutWeight(1).backgroundColor(kbTheme(this.isDark).selectingBarBg).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
