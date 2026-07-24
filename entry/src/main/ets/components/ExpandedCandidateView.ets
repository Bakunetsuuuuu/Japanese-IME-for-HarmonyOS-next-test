import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

@Component
export struct ExpandedCandidateView {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('oneHandedMode') oneHandedMode: boolean = false;
  @StorageLink('oneHandedSide') oneHandedSide: string = 'right';

  build() {
    // One-handed mode docks the panel itself to that side (thumb-reachable),
    // the same intent as the keyboard leaning that way — but via actual width
    // (Blank() pushing it over) rather than a transform scale, so the grid
    // text renders at normal proportions instead of squished. Blank() on the
    // side the panel should NOT touch: right-handed -> panel hugs the right
    // edge, so Blank() goes on the left (and vice versa for left-handed).
    Row() {
      if (this.oneHandedMode && this.oneHandedSide === 'right') {
        Blank()
      }
      Column() {
        Row() {
          Text('候補一覧')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .layoutWeight(1)
          Text('✕')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(16)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .width(40).height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              AppStorage.setOrCreate('candidateExpanded', false);
            })
        }
        .width('100%').height(36).padding({ left: 12, right: 4 }).alignItems(VerticalAlign.Center)
        .backgroundColor(kbTheme(this.isDark).panelBg)

        Scroll() {
          Grid() {
            ForEach(this.candidates, (candidate: string, index: number) => {
              GridItem() {
                Text(candidate)
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(17)
                  .fontWeight(index === this.selectedIndex ? FontWeight.Bold : FontWeight.Normal)
                  .width('100%').textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 12 }).borderRadius(10)
                  .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
                  .fontColor(index === this.selectedIndex ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
              }
              .onClick(() => {
                InputHandler.getInstance().commitCandidate(index);
                AppStorage.setOrCreate('candidateExpanded', false);
              })
            }, (candidate: string, index: number) => `${index}-${candidate}`)
          }
          // Fewer columns when docked narrower so tap targets stay a
          // comfortable size instead of cramming 4 columns into ~78% width.
          .columnsTemplate(this.oneHandedMode ? '1fr 1fr 1fr' : '1fr 1fr 1fr 1fr')
          .rowsGap(6).columnsGap(6)
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        }
        .width('100%').layoutWeight(1).backgroundColor(kbTheme(this.isDark).panelBg).scrollBar(BarState.Off)
      }
      .width(this.oneHandedMode ? '78%' : '100%')
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).panelBg)

      if (this.oneHandedMode && this.oneHandedSide === 'left') {
        Blank()
      }
    }
    .width('100%').height('100%')
  }
}
