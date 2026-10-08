// PCモードの言語バー (STATUS_BAR パネルの中身。PcModeController が作って出し入れする)。
//
//   [⋮⋮] [あ]                [⌨] [☺] [⚙]
//   つまみ  モード (クリックで あ⇄A)   仮想キー・絵文字・設定
//
// 候補ウィンドウの合わせ直しのきっかけもここで拾う: 裏の AI 変換が後から
// 届いて候補が変わったときなど、打鍵を通らない変更は AppStorage を見張る
// しかない。この画面は PCモードで入力欄にいる間ずっと出ているので、
// 見張り役に向いている (候補ウィンドウ側も同じことをしているが、隠れている
// 間に確実に動く保証が無いので両方に置く)。
import { InputMode, InputState } from '../ime/KeyboardController';
import { PcModeController, PC_SOFT_POPUP } from '../pc/PcModeController';
import { pcTheme, LANGBAR_BODY_W_VP, LANGBAR_BODY_H_VP } from '../pc/PcStyle';

const BUTTON_W = 32;
const BUTTON_H = 28;

@Entry
@Component
struct LangBarPage {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('inputMode') @Watch('onIme') inputMode: string = InputMode.HIRAGANA;
  @StorageLink('keyboardSubMode') @Watch('onSubMode') keyboardSubMode: string = 'kana';
  @StorageLink('pcSoftContent') pcSoftContent: string = 'keyboard';
  @StorageLink('pcVirtualKeyboard') pcVirtualKeyboard: boolean = false;
  @StorageLink('inputState') @Watch('onIme') inputState: string = InputState.IDLE;
  @StorageLink('candidates') @Watch('onIme') candidates: string[] = [];
  @StorageLink('selectedCandidateIndex') @Watch('onIme') selectedIndex: number = 0;
  @StorageLink('composingText') @Watch('onIme') composingText: string = '';
  @StorageLink('pendingRomaji') @Watch('onIme') pendingRomaji: string = '';
  @StorageLink('previewInField') @Watch('onIme') previewInField: boolean = false;
  @StorageLink('bunsetsuCurrent') @Watch('onIme') bunsetsuCurrent: number = 0;
  @StorageLink('dictEditMode') @Watch('onDictEdit') dictEditMode: boolean = false;
  @State hover: string = '';

  private onIme(): void {
    PcModeController.getInstance().onImeStateChanged();
  }

  private onDictEdit(): void {
    PcModeController.getInstance().onDictEditChanged(this.dictEditMode);
  }

  private onSubMode(): void {
    PcModeController.getInstance().onSubModeChanged(this.keyboardSubMode);
  }

  private modeLabel(): string {
    if (this.inputMode === InputMode.ALPHANUMERIC) { return 'A'; }
    if (this.inputMode === InputMode.KATAKANA) { return 'カ'; }
    return 'あ';
  }

  private popupOpen(subMode: string): boolean {
    return this.pcSoftContent === PC_SOFT_POPUP && this.keyboardSubMode === subMode;
  }

  private buttonBg(id: string, active: boolean): ResourceColor {
    if (active) { return pcTheme(this.isDark).selectedBg; }
    return this.hover === id ? pcTheme(this.isDark).hoverBg : Color.Transparent;
  }

  private setHover(id: string, isHover: boolean): void {
    if (isHover) {
      this.hover = id;
    } else if (this.hover === id) {
      this.hover = '';
    }
  }

  // 仮想キーの絵 (記号の資源に頼らず小さな四角で描く)
  @Builder KeyboardGlyph(color: ResourceColor) {
    Column({ space: 1.5 }) {
      Row({ space: 1.5 }) {
        ForEach([0, 1, 2, 3], (_i: number) => {
          Row().width(2.5).height(2.5).backgroundColor(color)
        }, (i: number) => `a${i}`)
      }
      Row({ space: 1.5 }) {
        ForEach([0, 1, 2, 3], (_i: number) => {
          Row().width(2.5).height(2.5).backgroundColor(color)
        }, (i: number) => `b${i}`)
      }
      Row().width(11).height(2).backgroundColor(color)
    }
    .padding({ left: 2.5, right: 2.5, top: 2.5, bottom: 2.5 })
    .border({ width: 1.2, color: color, radius: 2.5 })
  }

  build() {
    Stack() {
      Row() {
        // つまみ (ドラッグで動かす)
        Column({ space: 2 }) {
          ForEach([0, 1, 2], (_i: number) => {
            Row({ space: 2 }) {
              Row().width(2).height(2).borderRadius(1).backgroundColor(pcTheme(this.isDark).textSecondary)
              Row().width(2).height(2).borderRadius(1).backgroundColor(pcTheme(this.isDark).textSecondary)
            }
          }, (i: number) => `g${i}`)
        }
        .width(14)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .gesture(
          PanGesture({ distance: 1 })
            .onActionStart(() => { PcModeController.getInstance().beginLangBarDrag(); })
            .onActionUpdate((e: GestureEvent) => {
              PcModeController.getInstance().moveLangBarLive(e.offsetX, e.offsetY);
            })
            .onActionEnd(() => { PcModeController.getInstance().endLangBarDrag(); })
            .onActionCancel(() => { PcModeController.getInstance().endLangBarDrag(); })
        )

        // モード (あ / A)。クリックで切り替え (半角/全角キー・Alt+` と同じ)
        Text(this.modeLabel())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(pcTheme(this.isDark).textPrimary)
          .textAlign(TextAlign.Center)
          .width(BUTTON_W + 4)
          .height(BUTTON_H)
          .borderRadius(4)
          .backgroundColor(this.buttonBg('mode', false))
          .onHover((isHover: boolean) => { this.setHover('mode', isHover); })
          .onClick(() => { PcModeController.getInstance().toggleImeOnOff(); })

        Blank()

        // 仮想キー
        Row() {
          this.KeyboardGlyph(pcTheme(this.isDark).textPrimary)
        }
        .width(BUTTON_W)
        .height(BUTTON_H)
        .justifyContent(FlexAlign.Center)
        .borderRadius(4)
        .backgroundColor(this.buttonBg('vk', this.pcVirtualKeyboard))
        .onHover((isHover: boolean) => { this.setHover('vk', isHover); })
        .onClick(() => { PcModeController.getInstance().toggleVirtualKeyboard(); })

        // 絵文字 (ソフトキーボードの記号一覧の絵文字ボタンと同じ字)
        Text('☺')
          .fontSize(17)
          .fontColor(pcTheme(this.isDark).textPrimary)
          .textAlign(TextAlign.Center)
          .width(BUTTON_W)
          .height(BUTTON_H)
          .borderRadius(4)
          .backgroundColor(this.buttonBg('emoji', this.popupOpen('emoji') || this.popupOpen('symbol')))
          .onHover((isHover: boolean) => { this.setHover('emoji', isHover); })
          .onClick(() => { PcModeController.getInstance().togglePopup('emoji'); })

        // 設定 (ソフトキーボードの候補バーの設定ボタンと同じ記号)
        Row() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(16)
            .fontColor([pcTheme(this.isDark).textPrimary])
        }
        .width(BUTTON_W)
        .height(BUTTON_H)
        .justifyContent(FlexAlign.Center)
        .borderRadius(4)
        .backgroundColor(this.buttonBg('settings', this.popupOpen('settings')))
        .onHover((isHover: boolean) => { this.setHover('settings', isHover); })
        .onClick(() => { PcModeController.getInstance().togglePopup('settings'); })
      }
      .width(LANGBAR_BODY_W_VP)
      .height(LANGBAR_BODY_H_VP)
      .padding({ left: 2, right: 4 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(pcTheme(this.isDark).windowBg)
      .borderRadius(8)
      .border({ width: 1, color: pcTheme(this.isDark).border })
      .shadow({ radius: 6, color: pcTheme(this.isDark).shadow, offsetX: 0, offsetY: 1 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
