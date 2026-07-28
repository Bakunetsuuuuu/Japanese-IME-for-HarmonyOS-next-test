import { SuppressedCandidates } from '../ime/SuppressedCandidates';
import { router, promptAction } from '@kit.ArkUI';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';

const CARD_RADIUS = 16;

interface SuppressedRow {
  yomi: string;
  word: string;
}

// 削除した候補 list screen. Reached from Index.ets's footer link.
//
// Deleting a candidate (long-press on the candidate bar) is otherwise an
// invisible action: the surface simply stops appearing, with nothing on screen
// left to point at. This is the only surface that makes those deletions
// inspectable and individually reversible.
//
// Reads and rewrites the shared 'shunti_suppressed' store directly rather than
// going through the InputHandler singleton -- the main app is a separate
// process from the IME extension, so the extension's in-memory copy is not
// reachable here. It re-reads this store on its next onInputStart
// (KeyboardController.reloadSuppressed), which is what makes a restore take
// effect on the keyboard.
@Entry
@Component
struct SuppressedList {
  @StorageLink('isDark') isDark: boolean = false;
  @State rows: SuppressedRow[] = [];
  @State searchQuery: string = '';
  // Restoring everything at once throws away deletions the user may have built
  // up deliberately, so the header action asks a second time before doing it.
  @State confirmRestoreAll: boolean = false;
  private map: Record<string, string[]> = {};

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    SuppressedCandidates.load(getContext(this), true)
      .then((map: Record<string, string[]>) => {
        this.map = map;
        this.rebuildRows();
      })
      .catch((err: Error) => {
        console.error('shuntiIME SuppressedList.reload failed', JSON.stringify(err));
        this.map = {};
        this.rebuildRows();
      });
  }

  private rebuildRows(): void {
    const list: SuppressedRow[] = [];
    const keys = Object.keys(this.map).sort();
    for (const yomi of keys) {
      for (const word of this.map[yomi]) {
        list.push({ yomi: yomi, word: word });
      }
    }
    this.rows = list;
  }

  private visibleRows(): SuppressedRow[] {
    const q = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) { return this.rows; }
    return this.rows.filter((r: SuppressedRow) =>
      r.word.toLowerCase().includes(q) || r.yomi.toLowerCase().includes(q));
  }

  private restoreRow(row: SuppressedRow): void {
    // Re-read before writing: the keyboard may have deleted another candidate
    // while this screen was open, and a blind write of the stale in-memory map
    // would silently undo it.
    SuppressedCandidates.load(getContext(this), true).then((fresh: Record<string, string[]>) => {
      const next = SuppressedCandidates.restore(fresh, row.yomi, row.word);
      SuppressedCandidates.save(getContext(this), next).then(() => {
        this.map = next;
        this.rebuildRows();
        promptAction.showToast({ message: `「${row.word}」を元に戻しました` });
      });
    });
  }

  private restoreAll(): void {
    SuppressedCandidates.save(getContext(this), {}).then(() => {
      this.map = {};
      this.rebuildRows();
      this.confirmRestoreAll = false;
      promptAction.showToast({ message: '削除した候補をすべて元に戻しました' });
    });
  }

  build() {
    Column() {
      // ── Header: symmetric gutters so the title stays centered ──
      Row() {
        Row() {
          Text('‹ 戻る')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(kbTheme(this.isDark).accent)
            .onClick(() => { router.back(); })
        }
        .width(96)
        .justifyContent(FlexAlign.Start)

        Text('削除した候補')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row() {
          if (this.rows.length > 0) {
            Text(this.confirmRestoreAll ? '本当に戻す？' : 'すべて戻す')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(kbTheme(this.isDark).accent)
              .onClick(() => {
                if (this.confirmRestoreAll) {
                  this.restoreAll();
                } else {
                  this.confirmRestoreAll = true;
                }
              })
          }
        }
        .width(96)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

      // ── Search ────────────────────────────────────────────────
      TextInput({ placeholder: '候補・読みで検索', text: $$this.searchQuery })
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(14)
        .height(38)
        .backgroundColor(kbTheme(this.isDark).funcBg)
        .fontColor(kbTheme(this.isDark).textPrimary)
        .placeholderColor(kbTheme(this.isDark).textSecondary)
        .borderRadius(11)
        .margin({ left: 16, right: 16, top: 10, bottom: 10 })

      if (this.visibleRows().length === 0) {
        Column() {
          Text(this.rows.length === 0
            ? '削除した候補はありません\n変換候補を長押しすると削除できます'
            : '一致する候補が見つかりません')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 64 })
      } else {
        // An always-visible 戻す button rather than the dictionary list's
        // swipe-to-reveal: restoring is the only thing this screen is for, so
        // hiding its one action behind a gesture would be perverse.
        List() {
          ForEach(this.visibleRows(), (row: SuppressedRow) => {
            ListItem() {
              Row() {
                Column({ space: 2 }) {
                  Text(row.word)
                    .fontFamily(JP_FONT_FAMILY)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(kbTheme(this.isDark).textPrimary)
                  Text(row.yomi)
                    .fontFamily(JP_FONT_FAMILY)
                    .fontSize(12)
                    .fontColor(kbTheme(this.isDark).textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('戻す')
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(kbTheme(this.isDark).accent)
                  .backgroundColor(kbTheme(this.isDark).funcBg)
                  .borderRadius(14)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .onClick(() => { this.restoreRow(row); })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 11, bottom: 11 })
              .backgroundColor(kbTheme(this.isDark).cardBg)
              .alignItems(VerticalAlign.Center)
            }
          }, (row: SuppressedRow) => row.yomi + '' + row.word)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(kbTheme(this.isDark).cardBg)
        .borderRadius(CARD_RADIUS)
        .clip(true)
        .margin({ left: 16, right: 16 })
        .divider({ strokeWidth: 1, color: kbTheme(this.isDark).divider })
      }

      Text('元に戻すとキーボードで再び候補に出るようになります（キーボードを開き直すと反映されます）')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(11)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
