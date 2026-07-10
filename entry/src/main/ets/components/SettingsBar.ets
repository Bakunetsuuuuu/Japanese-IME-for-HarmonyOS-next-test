import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { promptAction } from '@kit.ArkUI';

// Popup panel opened from the ⚙ button that replaced the old in-keyboard
// flick/QWERTY toggle (that setting moved into the main app). Floats above
// the keyboard rather than pushing it down, since the IME panel's height is
// fixed by the system.
@Component
export struct SettingsBar {
  @Link visible: boolean;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  @StorageLink('clipboardHistory') clipboardHistory: string[] = [];
  @StorageLink('oneHandedMode') oneHandedMode: boolean = false;
  @StorageLink('oneHandedSide') oneHandedSide: string = 'right';
  @State showHistory: boolean = false;

  private close(): void {
    this.visible = false;
    this.showHistory = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // Scrim: tap outside the card closes the panel.
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#00000040')
        .onClick(() => { this.close(); })

      Column() {
        if (this.showHistory) {
          this.HistoryView()
        } else {
          this.MenuView()
        }
      }
      .width(this.isLandscape ? 200 : 230)
      .backgroundColor(kbTheme(this.isDark).candidateBg)
      .borderRadius(10)
      .shadow({ radius: 8, color: kbTheme(this.isDark).shadowColor, offsetY: 2 })
      .margin({ top: this.isLandscape ? 40 : 80, right: 4 })
      .padding(6)
    }
    .width('100%')
    .height('100%')
  }

  @Builder MenuView() {
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
  }

  @Builder HistoryView() {
    Row() {
      Text('← 戻る')
        .fontSize(13)
        .fontColor(kbTheme(this.isDark).accentBg)
        .onClick(() => { this.showHistory = false; })
        .layoutWeight(1)
      Text('履歴を削除')
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).subText)
        .onClick(() => {
          InputHandler.getInstance().clearClipboardHistory();
        })
    }
    .width('100%')
    .padding(10)

    Divider().color(kbTheme(this.isDark).borderColor)

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
