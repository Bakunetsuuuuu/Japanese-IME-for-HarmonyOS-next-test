import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

// キーボード本体を見ながら調整できるよう、この帯だけをパネル上部に出し、
// 実物のキーボード(FlickKeyboardView/KeyboardView)はそのまま下に残す
// (KeyboardPage.ets の keyboardSubMode === 'layoutAdjust' 分岐参照)。
//
// 縦の長さはスライダーではなく、この帯自体を上下にドラッグするハンドルに
// してある(「キーボード自体を手で動かす」操作感にしたいという要望)。
// フリック中央3列との幅比は、ここではなくキーボード側 (FlickKeyboardView
// の adjustMode) -- 左右特殊キー列との境界線を直接ドラッグする形にした。
const MIN_SCALE = 0.7;
const MAX_SCALE = 1.3;
// このぶんドラッグすると 0.7〜1.3 の全域を動く。指の可動域として無理のない
// 距離 (指を大きく動かさないと変わらない=誤操作しにくい/細かく調整できる
// の両立を狙った値)。
const HEIGHT_DRAG_RANGE_VP = 220;

@Component
export struct LayoutAdjustBar {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('keyboardHeightScale') heightScale: number = 1.0;

  // ドラッグ開始時点の値。onActionUpdate の offsetY はジェスチャ開始からの
  // 累積オフセットなので、開始時の値に対して足し引きする。
  private dragStartScale: number = 1.0;

  private h(): InputHandler { return InputHandler.getInstance(); }

  build() {
    Column({ space: 0 }) {
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
      .padding({ left: 14, right: 14, top: 6, bottom: 2 })
      .alignItems(VerticalAlign.Center)

      // 縦の長さの調整ハンドル。掴んで上下にドラッグするとキーボード
      // 全体がその場で伸び縮みする。上へ引く=長く、下へ押す=短く
      // (ハンドルの端を実際に動かす感覚に合わせた向き)。
      Column({ space: 3 }) {
        Row()
          .width(40)
          .height(4)
          .borderRadius(2)
          .backgroundColor(kbTheme(this.isDark).textSecondary)
        Text(`縦の長さ ${Math.round(this.heightScale * 100)}%`)
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(10)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .height(36)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(kbTheme(this.isDark).funcBg)
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionStart(() => {
            this.dragStartScale = this.heightScale;
          })
          .onActionUpdate((event: GestureEvent) => {
            const delta = -event.offsetY / HEIGHT_DRAG_RANGE_VP * (MAX_SCALE - MIN_SCALE);
            const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.dragStartScale + delta));
            this.h().applyKeyboardHeightScaleLive(next);
          })
          .onActionEnd(() => {
            this.h().saveKeyboardHeightScale(this.heightScale);
          })
      )

      Text('フリック入力は、キーボード側の左右端の境界線をドラッグすると中央3列との幅比が変わります')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(10)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 3, bottom: 4, left: 10, right: 10 })
    }
    .width('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })
  }
}
