import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';
import { promptAction } from '@kit.ArkUI';

@Component
export struct CandidateBar {
  @Prop candidates: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop showExpand: boolean = false;
  // 呼び出し側 (KeyboardPage) が比率計算した実際のバー高さ (vp)。以前は
  // ここが isLandscape の2択固定 (34/22) だったため、外側のバーが比率で
  // 縮んだときにチップだけ元の固定サイズのままはみ出て潰れて見えた。
  // チップ・フォント・矢印ボタンをすべてこの値から逆算する。
  @Prop barHeightVp: number = 48;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  // まだ LEARN_THRESHOLD 未満の未知語(準候補)。通常候補と見分けが付くよう
  // 点線の縁取りだけ足す (UnknownWordLearner.quasiCandidates 参照)。
  @StorageLink('quasiCandidateSurfaces') quasiCandidateSurfaces: string[] = [];
  // 提案 (打ち間違いの直し・日付・住所・絵文字…)。入力中の文字の帯 (ひらがなの帯) が無いとき (入力欄にプレビューを出す端末。
  // HarmonyOS 7 から) は、候補の帯の 1 位のすぐ後ろに、色と ✦ の印で見分けられるようにして並べる (ユーザー 2026-10-13)
  @StorageLink('suggestList') suggestList: string[] = [];
  @StorageLink('suggestKinds') suggestKinds: number[] = [];
  @StorageLink('suggestFrom') suggestFrom: string = '';
  @StorageLink('showComposingPanel') showComposingPanel: boolean = true;
  // Which chip is showing its 削除 popup (-1 = none), and the text that chip
  // holds. Kept as state rather than passed into the popup builder because a
  // parameterised @Builder inside ForEach can capture a stale row -- the same
  // reason KeyboardView drives its one-handed hint popup from state.
  @State menuIndex: number = -1;
  @State menuCandidate: string = '';
  // 横スクロールの位置を入力ログに残すため (タップした候補がスクロールしないと
  // 見えない位置だったかの手がかり)。
  private scroller: Scroller = new Scroller();

  private closeMenu(): void {
    this.menuIndex = -1;
    this.menuCandidate = '';
  }

  private chipHeightVp(): number {
    return Math.max(18, this.barHeightVp - 6);
  }

  private chipFontSize(): number {
    return Math.max(10, Math.min(16, this.chipHeightVp() * 0.42));
  }

  @Builder DeleteMenu() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(14)
        .fontColor([kbTheme(this.isDark).textPrimary])
      Text(`「${this.menuCandidate}」を候補から削除`)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(14)
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

  private suggestInBar(): boolean {
    return !this.showComposingPanel && this.suggestList.length > 0 && this.candidates.length > 0;
  }

  private suggestLabel(t: string, i: number): string {
    const k = i < this.suggestKinds.length ? this.suggestKinds[i] : 0;
    if (k === 1) { return `${this.suggestFrom}→${t}`; }
    if (k === 6 && t.startsWith(this.suggestFrom)) { return t.slice(this.suggestFrom.length); }
    return t;
  }

  build() {
    Row() {
      Scroll(this.scroller) {
        Row({ space: 6 }) {
          ForEach(this.candidates, (candidate: string, index: number) => {
            if (index === 1 && this.suggestInBar()) {
              // 提案: 1 位の後ろに。縁と字を強調色にして ✦ を付ける。押すとその提案で確定 (学習はしない)
              ForEach(this.suggestList, (t: string, si: number) => {
                Row({ space: 3 }) {
                  Text('✦')
                    .fontSize(this.chipFontSize() * 0.75)
                    .fontColor(kbTheme(this.isDark).accent)
                  Text(this.suggestLabel(t, si))
                    .fontFamily(JP_FONT_FAMILY)
                    .fontSize(this.chipFontSize())
                    .fontColor(kbTheme(this.isDark).accent)
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .height(this.chipHeightVp())
                .padding({ left: this.isLandscape ? 8 : 14, right: this.isLandscape ? 10 : 18 })
                .borderRadius(this.chipHeightVp() / 2)
                .border({ width: 1, color: kbTheme(this.isDark).accent })
                .onClick(() => { InputHandler.getInstance().commitSuggestion(si); })
              }, (t: string, si: number) => `s${si}-${t}`)
            }
            Row() {
              Text(candidate)
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(this.chipFontSize())
                .fontColor(index === this.selectedIndex ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .height(this.chipHeightVp())
            .padding({ left: this.isLandscape ? 10 : 18, right: this.isLandscape ? 10 : 18 })
            .borderRadius(this.chipHeightVp() / 2)
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
              radius: 20,
              // Masked: deleting is destructive enough to deserve a deliberate
              // second tap, and tapping the mask dismisses without deleting.
              mask: true,
              onStateChange: (e: PopupStateChangeParam) => {
                if (!e.isVisible && this.menuIndex === index) {
                  // 削除を押した場合は先に closeMenu 済みで menuIndex が -1 になって
                  // いるので、ここに来るのは削除せずに閉じたときだけ。
                  InputHandler.getInstance().noteCandidateMenu('cancel', index);
                  this.closeMenu();
                }
              },
            })
            // Long-press to offer deletion; a plain tap still commits via
            // onClick below, the same tap/hold split the space and shift keys use.
            .gesture(
              LongPressGesture({ duration: 400 })
                .onAction(() => {
                  this.menuCandidate = candidate;
                  this.menuIndex = index;
                  InputHandler.getInstance().noteCandidateMenu('open', index);
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
      .onScrollStop(() => {
        InputHandler.getInstance().noteCandidateScroll(this.scroller.currentOffset().xOffset);
      })
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height(this.barHeightVp)

      if (this.showExpand && this.candidates.length > 0) {
        // 自前の「▼」ではなく HarmonyOS Symbol を使う (PR #58)。高さと
        // グリフサイズは固定値ではなく実際のバー高さから逆算する。
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(Math.max(9, Math.min(14, this.chipHeightVp() * 0.36)))
            .fontColor([kbTheme(this.isDark).textSecondary])
        }
        .width(this.isLandscape ? 24 : 36)
        .height(this.barHeightVp)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(kbTheme(this.isDark).funcBg)
          .onClick(() => {
            InputHandler.getInstance().noteCandidateListToggle(true);
            AppStorage.setOrCreate('candidateExpanded', true);
          })
      }
    }
    .width('100%')
    .height(this.barHeightVp)
    .backgroundColor(kbTheme(this.isDark).previewBg)
  }
}
