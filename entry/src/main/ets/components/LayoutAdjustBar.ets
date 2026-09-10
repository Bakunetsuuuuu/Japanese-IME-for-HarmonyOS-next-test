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
// KeyboardController.computeKeyHeight と同じ値を使うこと。横向きは
// maxFrac/contentPx が縦向きより大きく既定の背が高くなりがちなので、
// 縮める側の下限をもっと下げてある(実際の指摘: 「横向き時、70%より
// 小さくできた方が良い」)。
const MIN_SCALE_PORTRAIT = 0.7;
const MIN_SCALE_LANDSCAPE = 0.4;
const MAX_SCALE = 1.3;
// このぶんドラッグすると下限〜1.3 の全域を動く。
const HEIGHT_DRAG_RANGE_VP = 220;

@Component
export struct LayoutAdjustBar {
  @Prop isLandscape: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  // 縦横で別の値を持つ (StorageLink はキー名を静的にしか束縛できないため、
  // 両方を保持して isLandscape で読み書き先を切り替える)。
  @StorageLink('keyboardHeightScalePortrait') heightScalePortrait: number = 1.0;
  @StorageLink('keyboardHeightScaleLandscape') heightScaleLandscape: number = 1.0;

  // get アクセサではなくメソッドにしてある -- ArkTS の @Component 内では
  // @StorageLink を組み合わせた get プロパティが実行時に正しく評価されず
  // (undefined を返す)、ドラッグ量の計算が NaN に化けて「サイズ調整が
  // 効かなくなる」不具合の原因になった。通常のメソッド呼び出しなら
  // この状態管理の仕組みと衝突しない。
  private heightScale(): number {
    return this.isLandscape ? this.heightScaleLandscape : this.heightScalePortrait;
  }

  // ドラッグ開始時点の値。onActionUpdate の offsetY はジェスチャ開始からの
  // 累積オフセットなので、開始時の値に対して足し引きする。
  private dragStartScale: number = 1.0;

  private h(): InputHandler { return InputHandler.getInstance(); }

  build() {
    Row() {
      // 縦の長さの掴みハンドル。上へ引くと長く、下へ押すと短く。ドラッグ用の
      // 当たり判定なので、他社IMEの「掴む」系ハンドルに合わせて指1本分
      // (44vp前後) は確保する -- 最初の圧縮で28vpまで縮めたら今度は
      // 小さすぎて掴みにくいという指摘を受けての調整。
      Row() {
        Row().width(4).height(this.isLandscape ? 14 : 22).borderRadius(2)
          .backgroundColor(kbTheme(this.isDark).onAccent)
      }
      .width(44)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(kbTheme(this.isDark).accent)
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionStart(() => {
            this.dragStartScale = this.heightScale();
          })
          .onActionUpdate((event: GestureEvent) => {
            const minScale = this.isLandscape ? MIN_SCALE_LANDSCAPE : MIN_SCALE_PORTRAIT;
            const delta = -event.offsetY / HEIGHT_DRAG_RANGE_VP * (MAX_SCALE - minScale);
            const next = Math.min(MAX_SCALE, Math.max(minScale, this.dragStartScale + delta));
            this.h().applyKeyboardHeightScaleLive(next, this.isLandscape);
          })
          .onActionEnd(() => {
            this.h().saveKeyboardHeightScale(this.heightScale(), this.isLandscape);
          })
      )

      Text(`縦 ${Math.round(this.heightScale() * 100)}%`)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.isLandscape ? 11 : 13)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .padding({ left: 10 })
        .layoutWeight(1)

      Text('リセット')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.isLandscape ? 11 : 13)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .onClick(() => { this.h().resetLayoutAdjust(); })

      Text('完了')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(this.isLandscape ? 11 : 13)
        .fontWeight(FontWeight.Medium)
        .fontColor(kbTheme(this.isDark).accent)
        .padding({ left: 10, right: 12, top: 8, bottom: 8 })
        .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'settings'); })
    }
    .width('100%')
    // かな行(28vp/14vp)より一回り大きく、候補行(48vp/22vp)よりは低く --
    // ここは表示専用の行ではなくドラッグハンドルなので、既存のどの行にも
    // 単純には揃えず、掴みやすさを優先した専用の高さにしてある。
    .height(this.isLandscape ? 30 : 44)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })
  }
}
