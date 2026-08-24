import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';
import { promptAction } from '@kit.ArkUI';

// Chip height (design tokens: "fixed 34px height" pill chips). Landscape gets
// a much shorter bar since vertical space there is scarce.
const CHIP_H = 34;
const CHIP_H_LANDSCAPE = 22;

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop showExpand: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  // まだ LEARN_THRESHOLD 未満の未知語(準候補)。通常候補と見分けが付くよう
  // 点線の縁取りだけ足す (UnknownWordLearner.quasiCandidates 参照)。
  @StorageLink('quasiCandidateSurfaces') quasiCandidateSurfaces: string[] = [];
  // Which chip is showing its 削除 popup (-1 = none), and the text that chip
  // holds. Kept as state rather than passed into the popup builder because a
  // parameterised @Builder inside ForEach can capture a stale row -- the same
  // reason KeyboardView drives its one-handed hint popup from state.
  @State menuIndex: number = -1;
  @State menuCandidate: string = '';

  private closeMenu(): void {
    this.menuIndex = -1;
    this.menuCandidate = '';
  }

  @Builder DeleteMenu() {
    Row({ space: 6 }) {
      Text('🗑')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(14)
      Text(`「${this.menuCandidate}」を候補から削除`)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(kbTheme(this.isDark).textPrimary)
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .onClick(() => {
      const removed = InputHandler.getInstance().suppressCandidate(this.menuIndex);
      this.closeMenu();
      if (removed.length > 0) {
        promptAction.showToast({ message: `「${removed}」を候補から削除しました（アプリの「削除した候補」から元に戻せます）` });
      }
    })
  }

  build() {
    Row() {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.candidates, (candidate: string, index: number) => {
            Row() {
              Text(candidate)
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(this.isLandscape ? 12 : 16)
                .fontColor(index === this.selectedIndex ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .height(this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H)
            .padding({ left: this.isLandscape ? 10 : 18, right: this.isLandscape ? 10 : 18 })
            .borderRadius((this.isLandscape ? CHIP_H_LANDSCAPE : CHIP_H) / 2)
            .backgroundColor(index === this.selectedIndex ? kbTheme(this.isDark).accent : kbTheme(this.isDark).candidateBg)
            .border(this.quasiCandidateSurfaces.includes(candidate) ? {
              width: 1, color: kbTheme(this.isDark).textSecondary, style: BorderStyle.Dotted,
            } : { width: 0 })
            .bindPopup(this.menuIndex === index, {
              builder: this.DeleteMenu,
              placement: Placement.Top,
              enableArrow: true,
              popupColor: kbTheme(this.isDark).cardBg,
              backgroundBlurStyle: BlurStyle.NONE,
              radius: 12,
              // Masked: deleting is destructive enough to deserve a deliberate
              // second tap, and tapping the mask dismisses without deleting.
              mask: true,
              onStateChange: (e: PopupStateChangeParam) => {
                if (!e.isVisible && this.menuIndex === index) { this.closeMenu(); }
              },
            })
            // Long-press to offer deletion; a plain tap still commits via
            // onClick below, the same tap/hold split the space and shift keys use.
            .gesture(
              LongPressGesture({ duration: 400 })
                .onAction(() => {
                  this.menuCandidate = candidate;
                  this.menuIndex = index;
                })
            )
            .onClick(() => {
              InputHandler.getInstance().commitCandidate(index);
            })
          }, (candidate: string, index: number) => `${index}-${candidate}`)
        }
        .padding({ left: 4, right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height(this.isLandscape ? 22 : 48)

      if (this.showExpand && this.candidates.length > 0) {
        Text('▼')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(this.isLandscape ? 10 : 14)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width(this.isLandscape ? 24 : 36)
          .height(this.isLandscape ? 22 : 48)
          .textAlign(TextAlign.Center)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .onClick(() => {
            AppStorage.setOrCreate('candidateExpanded', true);
          })
      }
    }
    .width('100%')
    .height(this.isLandscape ? 22 : 48)
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
