import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

@Component
export struct ExpandedCandidateView {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';

  build() {
    Column() {
      Row() {
        Text('候補一覧').fontSize(14).fontColor(kbTheme(this.isDark, this.themeVariant).subText).layoutWeight(1)
      }
      .width('100%').height(36).padding({ left: 12, right: 8 }).alignItems(VerticalAlign.Center)
      .backgroundColor(kbTheme(this.isDark, this.themeVariant).composingBarBg)

      Scroll() {
        Grid() {
          ForEach(this.candidates, (candidate: string, index: number) => {
            GridItem() {
              Text(candidate).fontSize(17)
                .fontWeight(index === this.selectedIndex ? FontWeight.Bold : FontWeight.Normal)
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: 12, bottom: 12 }).borderRadius(10)
                .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark, this.themeVariant).accentBg : kbTheme(this.isDark, this.themeVariant).candidateBg)
                .fontColor(index === this.selectedIndex ? kbTheme(this.isDark, this.themeVariant).onAccentText : kbTheme(this.isDark, this.themeVariant).keyText)
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
      .width('100%').layoutWeight(1).backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(kbTheme(this.isDark, this.themeVariant).panelBg)
  }
}
