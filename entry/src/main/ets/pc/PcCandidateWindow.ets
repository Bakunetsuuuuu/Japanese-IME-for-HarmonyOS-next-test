// PCモードの候補ウィンドウ (Windows 11 の IME 風)。KeyboardPage が
// AppStorage('pcSoftContent') === 'candidate' のときにこれだけを描く。
// 窓の大きさ・置き場所は PcModeController が CandidateViewModel から決める。
//
//   ┌──────────────────┐
//   │ しゃしんをとった       │ ← 入力欄に下線付きで出せない欄のときだけ
//   │▌1  写真を撮った       │ ← 選んでいる行 (薄く塗って左端に縦線)
//   │ 2  写真を取った       │
//   │ 3  写真をとった       │
//   │              1/3 ◀ ▶ │ ← 1 ページに収まらないときだけ
//   └──────────────────┘
// 入力中 (まだ変換していない) は番号を出さず、選ばずに見せるだけ。
import { InputHandler, InputState } from '../ime/KeyboardController';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { PcModeController } from './PcModeController';
import { buildCandidateView, CandidateViewModel } from './CandidateViewModel';
import {
  pcTheme, CANDIDATE_PAGE_SIZE, CAND_MARGIN_VP, CAND_PAD_VP, CAND_ROW_H_VP, CAND_HEADER_H_VP,
  CAND_FOOTER_H_VP, CAND_NUMBER_W_VP, CAND_FONT_FP
} from './PcStyle';

// ホイール (マウスのホイールも PanGesture として届く) で 1 ページ送るのに要る量 (vp)
const WHEEL_PAGE_VP = 24;

@Component
export struct PcCandidateWindow {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('inputState') @Watch('refresh') inputState: string = InputState.IDLE;
  @StorageLink('candidates') @Watch('refresh') candidates: string[] = [];
  @StorageLink('selectedCandidateIndex') @Watch('refresh') selectedIndex: number = 0;
  @StorageLink('composingText') @Watch('refresh') composingText: string = '';
  @StorageLink('pendingRomaji') @Watch('refresh') pendingRomaji: string = '';
  @StorageLink('previewInField') @Watch('refresh') previewInField: boolean = false;
  @StorageLink('bunsetsuDisplay') @Watch('refresh') bunsetsuDisplay: string = '';
  @State vm: CandidateViewModel = {
    visible: false, header: '', rows: [], firstIndex: 0, selectedRow: -1, numbered: false,
    page: 0, pageCount: 0,
  };
  @State hoverRow: number = -1;

  aboutToAppear(): void {
    this.rebuild();
  }

  private refresh(): void {
    this.rebuild();
    PcModeController.getInstance().onImeStateChanged();
  }

  private rebuild(): void {
    this.vm = buildCandidateView(this.inputState, this.candidates, this.selectedIndex,
      this.previewInField, this.composingText + this.pendingRomaji, this.bunsetsuDisplay);
    this.hoverRow = -1;
  }

  private pick(row: number): void {
    InputHandler.getInstance().commitCandidate(this.vm.firstIndex + row);
    InputHandler.getInstance().refreshPreview();
    PcModeController.getInstance().onImeStateChanged();
  }

  private turnPage(delta: number): void {
    if (!this.vm.numbered || this.vm.pageCount <= 1) { return; }
    const page = Math.max(0, Math.min(this.vm.pageCount - 1, this.vm.page + delta));
    if (page === this.vm.page) { return; }
    InputHandler.getInstance().setCandidateSelection(page * CANDIDATE_PAGE_SIZE);
    PcModeController.getInstance().onImeStateChanged();
  }

  private rowBg(row: number): ResourceColor {
    if (row === this.vm.selectedRow) { return pcTheme(this.isDark).selectedBg; }
    return row === this.hoverRow ? pcTheme(this.isDark).hoverBg : Color.Transparent;
  }

  build() {
    Column() {
      // 出すものが無いときは何も描かない (窓が何かの拍子に出ても空白の板にならないように)
      if (this.vm.visible) {
        Column() {
          if (this.vm.header.length > 0) {
            Row() {
              Text(this.vm.header)
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(CAND_FONT_FP - 1)
                .fontColor(pcTheme(this.isDark).textPrimary)
                .decoration({ type: TextDecorationType.Underline, color: pcTheme(this.isDark).composingUnderline })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(CAND_HEADER_H_VP)
            .padding({ left: 12, right: 12 })
            .alignItems(VerticalAlign.Center)
          }

          ForEach(this.vm.rows, (cand: string, row: number) => {
            Row() {
              // 選んでいる行の左端の縦線
              Row()
                .width(3)
                .height(16)
                .borderRadius(1.5)
                .backgroundColor(row === this.vm.selectedRow ? pcTheme(this.isDark).accent : Color.Transparent)
              Text(this.vm.numbered ? `${row + 1}` : '')
                .fontSize(12)
                .fontColor(pcTheme(this.isDark).textSecondary)
                .width(CAND_NUMBER_W_VP - 3)
                .textAlign(TextAlign.Center)
              Text(cand)
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(CAND_FONT_FP)
                .fontColor(pcTheme(this.isDark).textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .height(CAND_ROW_H_VP)
            .padding({ right: 10 })
            .alignItems(VerticalAlign.Center)
            .borderRadius(4)
            .backgroundColor(this.rowBg(row))
            .onHover((isHover: boolean) => {
              if (isHover) {
                this.hoverRow = row;
              } else if (this.hoverRow === row) {
                this.hoverRow = -1;
              }
            })
            .onClick(() => { this.pick(row); })
          }, (cand: string, row: number) => `${this.vm.firstIndex + row}:${cand}`)

          if (this.vm.pageCount > 1) {
            Row({ space: 10 }) {
              Text(`${this.vm.page + 1}/${this.vm.pageCount}`)
                .fontSize(11)
                .fontColor(pcTheme(this.isDark).textSecondary)
              Text('◀')
                .fontSize(10)
                .fontColor(this.vm.page > 0 ? pcTheme(this.isDark).textPrimary : pcTheme(this.isDark).textSecondary)
                .onClick(() => { this.turnPage(-1); })
              Text('▶')
                .fontSize(10)
                .fontColor(this.vm.page + 1 < this.vm.pageCount
                  ? pcTheme(this.isDark).textPrimary : pcTheme(this.isDark).textSecondary)
                .onClick(() => { this.turnPage(1); })
            }
            .width('100%')
            .height(CAND_FOOTER_H_VP)
            .padding({ right: 10 })
            .justifyContent(FlexAlign.End)
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
        .padding(CAND_PAD_VP)
        .backgroundColor(pcTheme(this.isDark).windowBg)
        .borderRadius(8)
        .border({ width: 1, color: pcTheme(this.isDark).border })
        .shadow({ radius: CAND_MARGIN_VP, color: pcTheme(this.isDark).shadow, offsetX: 0, offsetY: 2 })
        .clip(false)
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 4 })
            .onActionEnd((e: GestureEvent) => {
              if (e.offsetY <= -WHEEL_PAGE_VP) {
                this.turnPage(1);
              } else if (e.offsetY >= WHEEL_PAGE_VP) {
                this.turnPage(-1);
              }
            })
        )
      }
    }
    .width('100%')
    .height('100%')
    .padding(CAND_MARGIN_VP)
  }
}
