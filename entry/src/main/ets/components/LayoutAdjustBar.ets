import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

// キーボード本体を見ながら調整できるよう、この帯だけをパネル上部に出し、
// 実物のキーボード(FlickKeyboardView/KeyboardView)はそのまま下に残す
// (KeyboardPage.ets の keyboardSubMode === 'layoutAdjust' 分岐参照)。
//
// 1行に収めてある (最初の実装は2〜3行あって、その分キーボード側が
// 圧迫されて破綻していた)。縦の長さは左端の掴み部分を上下にドラッグする
// ハンドル。フリック中央3列との幅比は、ここではなくキーボード側
// (FlickKeyboardView の adjustMode) -- 左右特殊キー列との境界線を
// 直接ドラッグする形にしてあり、この帯には出さない。
const MIN_SCALE = 0.7;
const MAX_SCALE = 1.3;
// このぶんドラッグすると 0.7〜1.3 の全域を動く。
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
    Row() {
      // 縦の長さの掴みハンドル。上へ引くと長く、下へ押すと短く。
      Row() {
        Row().width(3).height(16).borderRadius(1.5).backgroundColor(kbTheme(this.isDark).onAccent)
      }
      .width(34)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(kbTheme(this.isDark).accent)
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

      Text(`縦 ${Math.round(this.heightScale * 100)}%`)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(11)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .padding({ left: 8 })
        .layoutWeight(1)

      Text('リセット')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .padding({ left: 8, right: 8 })
        .onClick(() => { this.h().resetLayoutAdjust(); })

      Text('完了')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(kbTheme(this.isDark).accent)
        .padding({ left: 8, right: 10 })
        .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'settings'); })
    }
    .width('100%')
    .height(28)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })
  }
}
