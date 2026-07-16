import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { promptAction } from '@kit.ArkUI';

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
  @State showHistory: boolean = false;

  private close(): void {
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    this.showHistory = false;
  }

  build() {
    Column({ space: 0 }) {
      // ── Header ───────────────────────────────────────────────
      Row() {
        Text('←')
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .width(48).height(40)
          .fontColor(kbTheme(this.isDark).onAccentText)
          .backgroundColor(kbTheme(this.isDark).specialKeyBg)
          .borderRadius(20)
          .onClick(() => {
            if (this.showHistory) {
              this.showHistory = false;
            } else {
              this.close();
            }
          })

        Text(this.showHistory ? 'クリップボード履歴' : '設定')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).previewText)
          .layoutWeight(1)
          .padding({ left: 12 })

        if (this.showHistory) {
          Text('削除')
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).subText)
            .padding({ right: 12 })
            .onClick(() => {
              InputHandler.getInstance().clearClipboardHistory();
            })
        }
      }
      .width('100%')
      .height(48)
      .padding({ left: 4 })
      .alignItems(VerticalAlign.Center)

      Divider().color(kbTheme(this.isDark).borderColor)

      // ── Content (scrolls if it doesn't fit the panel height) ──
      Scroll() {
        Column() {
          if (this.showHistory) {
            this.HistoryView()
          } else {
            this.MenuView()
          }
        }
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

  @Builder MenuView() {
    // Switches immediately (same process as the keyboard itself) — more
    // reliable than the main app's copy of this same toggle, which has to
    // round-trip through shared preferences for the extension to pick it up.
    Row() {
      Text('キーボード')
        .fontSize(14)
        .fontColor(kbTheme(this.isDark).previewText)
        .layoutWeight(1)

      Row() {
        Text('QWERTY')
          .fontSize(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.keyboardLayout === 'QWERTY' ? kbTheme(this.isDark).accentBg : 'transparent')
          .fontColor(this.keyboardLayout === 'QWERTY' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .onClick(() => { InputHandler.getInstance().setKeyboardLayout('QWERTY'); })

        Text('フリック')
          .fontSize(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.keyboardLayout === 'FLICK' ? kbTheme(this.isDark).accentBg : 'transparent')
          .fontColor(this.keyboardLayout === 'FLICK' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .onClick(() => { InputHandler.getInstance().setKeyboardLayout('FLICK'); })
      }
      .backgroundColor(kbTheme(this.isDark).funcKeyBg)
      .borderRadius(8)
      .padding(2)
    }
    .width('100%')
    .padding(10)

    Divider().color(kbTheme(this.isDark).borderColor)

    Text('アプリを開く')
      .fontSize(14)
      .fontColor(kbTheme(this.isDark).previewText)
      .width('100%')
      .padding(10)
      .onClick(() => {
        InputHandler.getInstance().openMainApp();
        this.close();
      })

    Divider().color(kbTheme(this.isDark).borderColor)

    Row() {
      Text('片手モード')
        .fontSize(14)
        .fontColor(kbTheme(this.isDark).previewText)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.oneHandedMode })
        .selectedColor(kbTheme(this.isDark).accentBg)
        .onChange((isOn: boolean) => {
          InputHandler.getInstance().setOneHandedMode(isOn, this.oneHandedSide);
        })
    }
    .width('100%')
    .padding(10)

    if (this.oneHandedMode) {
      Row({ space: 8 }) {
        Text('左寄せ')
          .fontSize(13)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.oneHandedSide === 'left' ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).funcKeyBg)
          .fontColor(this.oneHandedSide === 'left' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .onClick(() => { InputHandler.getInstance().setOneHandedMode(true, 'left'); })
        Text('右寄せ')
          .fontSize(13)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.oneHandedSide === 'right' ? kbTheme(this.isDark).accentBg : kbTheme(this.isDark).funcKeyBg)
          .fontColor(this.oneHandedSide === 'right' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .onClick(() => { InputHandler.getInstance().setOneHandedMode(true, 'right'); })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 8 })
    }

    Divider().color(kbTheme(this.isDark).borderColor)

    Row() {
      Text('変換エンジン')
        .fontSize(14)
        .fontColor(kbTheme(this.isDark).previewText)
        .layoutWeight(1)

      Row() {
        Text('独自辞書')
          .fontSize(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.conversionEngine !== 'mozc' ? kbTheme(this.isDark).accentBg : 'transparent')
          .fontColor(this.conversionEngine !== 'mozc' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .onClick(() => { InputHandler.getInstance().setConversionEngine('custom'); })

        Text('統計データ')
          .fontSize(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.conversionEngine === 'mozc' ? kbTheme(this.isDark).accentBg : 'transparent')
          .fontColor(this.conversionEngine === 'mozc' ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .onClick(() => { InputHandler.getInstance().setConversionEngine('mozc'); })
      }
      .backgroundColor(kbTheme(this.isDark).funcKeyBg)
      .borderRadius(8)
      .padding(2)
    }
    .width('100%')
    .padding(10)

    Text(this.conversionEngine === 'mozc'
      ? '高性能だが比較的鈍重（推奨）'
      : '軽量だが発展途上')
      .fontSize(11)
      .fontColor(kbTheme(this.isDark).subText)
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 10 })

    Divider().color(kbTheme(this.isDark).borderColor)

    Text(`クリップボード履歴（${this.clipboardHistory.length}）`)
      .fontSize(14)
      .fontColor(kbTheme(this.isDark).previewText)
      .width('100%')
      .padding(10)
      .onClick(() => { this.showHistory = true; })

    Divider().color(kbTheme(this.isDark).borderColor)

    Text('レビューを書く')
      .fontSize(14)
      .fontColor(kbTheme(this.isDark).previewText)
      .width('100%')
      .padding(10)
      .onClick(() => {
        const opened = InputHandler.getInstance().openAppGalleryReview();
        if (!opened) {
          promptAction.showToast({ message: 'まだAppGalleryに公開されていません' });
        }
        this.close();
      })

    Divider().color(kbTheme(this.isDark).borderColor)

    Text('開発を支援 / ソースコード（GitHub）')
      .fontSize(14)
      .fontColor(kbTheme(this.isDark).previewText)
      .width('100%')
      .padding(10)
      .onClick(() => {
        InputHandler.getInstance().openGithubRepo();
        this.close();
      })
  }

  @Builder HistoryView() {
    if (this.clipboardHistory.length === 0) {
      Text('履歴がありません')
        .fontSize(13)
        .fontColor(kbTheme(this.isDark).subText)
        .padding(16)
    } else {
      List() {
        ForEach(this.clipboardHistory, (item: string, index: number) => {
          ListItem() {
            Text(item)
              .fontSize(13)
              .fontColor(kbTheme(this.isDark).previewText)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding(10)
              .onClick(() => {
                InputHandler.getInstance().pasteFromHistory(index);
                this.close();
              })
          }
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: 220 })
      .divider({ strokeWidth: 1, color: kbTheme(this.isDark).borderColor })
    }
  }
}
