// PCモードで言語バーから開く絵文字・設定。KeyboardPage が
// AppStorage('pcSoftContent') === 'popup' のときにこれだけを描く。
// 中身はソフトキーボードのものをそのまま使う (EmojiView・SymbolView・SettingsBar)。
// どれも「戻る」で keyboardSubMode を 'kana' にするので、それを
// PcModeController.onSubModeChanged が見て窓を閉じる。
import { EmojiView } from '../components/EmojiView';
import { SymbolView } from '../components/SymbolView';
import { SettingsBar } from '../components/SettingsBar';
import { kbTheme } from '../components/Theme';
import { pcTheme } from './PcStyle';

@Component
export struct PcPopupView {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('keyboardSubMode') keyboardSubMode: string = 'kana';

  build() {
    Column() {
      if (this.keyboardSubMode === 'emoji') {
        EmojiView()
      } else if (this.keyboardSubMode === 'symbol') {
        SymbolView()
      } else if (this.keyboardSubMode === 'settings') {
        SettingsBar()
      }
    }
    .width('100%')
    .height('100%')
    // 中の部品はソフトキーボードの面の色の上に置く前提で色を決めてある
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .borderRadius(8)
    .border({ width: 1, color: pcTheme(this.isDark).border })
    .clip(true)
  }
}
