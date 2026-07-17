import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { promptAction } from '@kit.ArkUI';
import { JP_FONT_FAMILY } from './JpFont';

// Segmented-control / card metrics (design tokens: settings cards 16px,
// segmented-control track 10-11px / inner pill 8px, selected option gets a
// slight elevation vs. the flat unselected one).
const CARD_RADIUS = 16;
const TRACK_RADIUS = 11;
const PILL_RADIUS = 8;
const SELECTED_SHADOW = { radius: 3, color: '#2E000000', offsetX: 0, offsetY: 1 };

// Dedicated settings sub-mode, entered via keyboardSubMode === 'settings'
// (the ⚙ button in KeyboardPage). Takes the full IME panel the same way
// SymbolView/EmojiView do (header row + Scroll content) rather than
// floating a narrow card over the keyboard -- the previous floating-card
// version was too cramped once enough menu items accumulated.
@Component
export struct SettingsBar {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  @StorageLink('clipboardHistory') clipboardHistory: string[] = [];
  @StorageLink('oneHandedMode') oneHandedMode: boolean = false;
  @StorageLink('oneHandedSide') oneHandedSide: string = 'right';
  @StorageLink('keyboardLayout') keyboardLayout: string = 'QWERTY';
  @StorageLink('conversionEngine') conversionEngine: string = 'custom';
  @StorageLink('themeMode') themeMode: string = 'system';
  @State showHistory: boolean = false;

  private close(): void {
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    this.showHistory = false;
  }

  build() {
    Column({ space: 0 }) {
      // ── Header: symmetric 56px gutters so the title stays centered
      // regardless of which side has a control (design tokens). ──
      Row() {
        Row() {
          if (this.showHistory) {
            Text('‹ 戻る')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(kbTheme(this.isDark).accent)
              .onClick(() => { this.showHistory = false; })
          }
        }
        .width(56)
        .justifyContent(FlexAlign.Start)

        Text(this.showHistory ? 'クリップボード履歴' : '設定')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row() {
          if (this.showHistory) {
            Text('削除')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(13)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .onClick(() => {
                InputHandler.getInstance().clearClipboardHistory();
              })
          } else {
            Text('✕')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(13)
              .width(28).height(28)
              .textAlign(TextAlign.Center)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .backgroundColor(kbTheme(this.isDark).funcBg)
              .borderRadius(14)
              .onClick(() => { this.close(); })
          }
        }
        .width(56)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

      Divider().color(kbTheme(this.isDark).divider)

      // ── Content (scrolls if it doesn't fit the panel height) ──
      Scroll() {
        Column() {
          if (this.showHistory) {
            this.HistoryView()
          } else {
            this.MenuView()
          }
        }
        .padding(16)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }

  @Builder SectionLabel(text: string) {
    Text(text)
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .letterSpacing(0.6)
      .fontColor(kbTheme(this.isDark).textSecondary)
      .padding({ left: 4, bottom: 8 })
      .width('100%')
  }

  // Two-option segmented control, e.g. QWERTY/フリック, ライト/ダーク.
  @Builder Segmented(leftLabel: string, rightLabel: string, leftActive: boolean, onLeft: () => void, onRight: () => void) {
    Row({ space: 2 }) {
      Text(leftLabel)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(PILL_RADIUS)
        .backgroundColor(leftActive ? kbTheme(this.isDark).accent : 'transparent')
        .fontColor(leftActive ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
        .shadow(leftActive ? SELECTED_SHADOW : { radius: 0, color: 'transparent' })
        .onClick(onLeft)

      Text(rightLabel)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(PILL_RADIUS)
        .backgroundColor(!leftActive ? kbTheme(this.isDark).accent : 'transparent')
        .fontColor(!leftActive ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
        .shadow(!leftActive ? SELECTED_SHADOW : { radius: 0, color: 'transparent' })
        .onClick(onRight)
    }
    .backgroundColor(kbTheme(this.isDark).funcBg)
    .borderRadius(TRACK_RADIUS)
    .padding(3)
  }

  @Builder ChevronRow(label: string, badge: string, action: () => void) {
    Row() {
      Text(label)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(14)
        .fontColor(kbTheme(this.isDark).textPrimary)
        .layoutWeight(1)
      Row({ space: 6 }) {
        if (badge !== '') {
          Text(badge)
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(15)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .onClick(action)
  }

  @Builder MenuView() {
    this.SectionLabel('入力')
    Column() {
      // Switches immediately (same process as the keyboard itself) — more
      // reliable than the main app's copy of this same toggle, which has to
      // round-trip through shared preferences for the extension to pick it up.
      Row() {
        Text('キーボードレイアウト')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        this.Segmented('QWERTY', 'フリック', this.keyboardLayout === 'QWERTY',
          () => { InputHandler.getInstance().setKeyboardLayout('QWERTY'); },
          () => { InputHandler.getInstance().setKeyboardLayout('FLICK'); })
      }
      .width('100%')
      .padding({ top: 13, bottom: 13 })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('片手モード')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.oneHandedMode })
          .width(44)
          .height(26)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((isOn: boolean) => {
            InputHandler.getInstance().setOneHandedMode(isOn, this.oneHandedSide);
          })
      }
      .width('100%')
      .padding({ top: 13, bottom: this.oneHandedMode ? 8 : 13 })

      if (this.oneHandedMode) {
        Row({ space: 8 }) {
          this.Segmented('左寄せ', '右寄せ', this.oneHandedSide === 'left',
            () => { InputHandler.getInstance().setOneHandedMode(true, 'left'); },
            () => { InputHandler.getInstance().setOneHandedMode(true, 'right'); })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: 14 })
      }

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('変換エンジン')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        this.Segmented('独自辞書', '統計データ', this.conversionEngine !== 'mozc',
          () => { InputHandler.getInstance().setConversionEngine('custom'); },
          () => { InputHandler.getInstance().setConversionEngine('mozc'); })
      }
      .width('100%')
      .padding({ top: 13, bottom: 4 })

      Text(this.conversionEngine === 'mozc'
        ? '高性能だが比較的鈍重（推奨）'
        : '軽量だが発展途上')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(11)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .padding({ bottom: 13 })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('外観')
    Column() {
      Row() {
        Text('テーマ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        this.Segmented('ライト', 'ダーク', this.themeMode !== 'dark',
          () => { InputHandler.getInstance().setThemeMode('light'); },
          () => { InputHandler.getInstance().setThemeMode('dark'); })
      }
      .width('100%')
      .padding({ top: 13, bottom: 13 })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('その他')
    Column() {
      this.ChevronRow('アプリを開く', '', () => {
        InputHandler.getInstance().openMainApp();
        this.close();
      })
      Divider().color(kbTheme(this.isDark).divider)
      this.ChevronRow('クリップボード履歴', String(this.clipboardHistory.length), () => {
        this.showHistory = true;
      })
      Divider().color(kbTheme(this.isDark).divider)
      this.ChevronRow('レビューを書く', '', () => {
        const opened = InputHandler.getInstance().openAppGalleryReview();
        if (!opened) {
          promptAction.showToast({ message: 'まだAppGalleryに公開されていません' });
        }
        this.close();
      })
      Divider().color(kbTheme(this.isDark).divider)
      this.ChevronRow('開発を支援 / ソースコード（GitHub）', '', () => {
        InputHandler.getInstance().openGithubRepo();
        this.close();
      })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
  }

  @Builder HistoryView() {
    if (this.clipboardHistory.length === 0) {
      Text('履歴がありません')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(13)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 48, bottom: 48 })
    } else {
      List() {
        ForEach(this.clipboardHistory, (item: string, index: number) => {
          ListItem() {
            Text(item)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(14)
              .fontColor(kbTheme(this.isDark).textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ top: 14, bottom: 14 })
              .onClick(() => {
                InputHandler.getInstance().pasteFromHistory(index);
                this.close();
              })
          }
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 14, right: 14 })
      .divider({ strokeWidth: 1, color: kbTheme(this.isDark).divider })
    }
  }
}
