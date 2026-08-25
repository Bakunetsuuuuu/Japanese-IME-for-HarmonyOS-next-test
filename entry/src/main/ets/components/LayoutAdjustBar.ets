import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

// キーボード本体を見ながら調整できるよう、この帯だけをパネル上部に出し、
// 実物のキーボード(FlickKeyboardView/KeyboardView)はそのまま下に残す
// (KeyboardPage.ets の keyboardSubMode === 'layoutAdjust' 分岐参照)。
// SettingsBar の中の他の設定画面 (語彙パック等) はキーボード全体を占有する
// フル画面だが、これは見た目に関わる調整なので同じ作りにはしていない。
@Component
export struct LayoutAdjustBar {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('keyboardHeightScale') heightScale: number = 1.0;
  @StorageLink('flickSideColumnRatio') sideRatio: number = 1.0;

  private h(): InputHandler { return InputHandler.getInstance(); }

  build() {
    Column({ space: 2 }) {
      Row() {
        Text('レイアウト調整')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Text('リセット')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => { this.h().resetLayoutAdjust(); })
        Text('完了')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(kbTheme(this.isDark).accent)
          .padding({ left: 10, right: 2, top: 4, bottom: 4 })
          .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'settings'); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('縦の長さ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width(76)
        Slider({ value: this.heightScale * 100, min: 70, max: 130, step: 5 })
          .layoutWeight(1)
          .blockColor(kbTheme(this.isDark).accent)
          .trackColor(kbTheme(this.isDark).divider)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((value: number, mode: SliderChangeMode) => {
            // 縦の長さはパネル自体の実サイズ変更 (panel.resize) を伴う重い
            // 操作なので、ドラッグ中は数字の表示だけ追従させ、指を離した
            // ときに1回だけ実際にリサイズする。中央3列比 (下のスライダー)
            // は AppStorage の書き換えだけで済む軽い処理なので、そちらは
            // ドラッグ中も毎回適用してよい。
            const scale = value / 100;
            this.heightScale = scale;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.h().saveKeyboardHeightScale(scale);
            }
          })
        Text(`${Math.round(this.heightScale * 100)}%`)
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('フリック中央比')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width(76)
        Slider({ value: this.sideRatio * 100, min: 40, max: 200, step: 5 })
          .layoutWeight(1)
          .blockColor(kbTheme(this.isDark).accent)
          .trackColor(kbTheme(this.isDark).divider)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((value: number, mode: SliderChangeMode) => {
            const ratio = value / 100;
            this.sideRatio = ratio;
            this.h().applyFlickSideRatioLive(ratio);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.h().saveFlickSideRatio(ratio);
            }
          })
        Text(this.sideRatio.toFixed(2))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('フリック入力のみ、左右の特殊キー列と中央3列(あ・か・さ…)の幅比を変えます')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(10)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })
  }
}
