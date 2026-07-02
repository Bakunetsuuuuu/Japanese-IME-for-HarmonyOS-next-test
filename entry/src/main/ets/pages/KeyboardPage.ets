import inputMethodEngine from '@ohos.inputMethodEngine';
import util from '@ohos.util';
import { InputHandler, InputState, InputMode, applyKeyboardWidthsForVp } from '../ime/KeyboardController';
import { KanaKanjiConverter } from '../ime/KanaKanjiConverter';
import { CandidateBar } from '../components/CandidateBar';
import { KeyboardView } from '../components/KeyboardView';
import { FlickKeyboardView } from '../components/FlickKeyboardView';
import { SymbolView } from '../components/SymbolView';
import { EmojiView } from '../components/EmojiView';
import { NumericPadView } from '../components/NumericPadView';
import { BunsetsuBar } from '../components/BunsetsuBar';
import { kbTheme } from '../components/Theme';

let _inputStartRegistered = false;
let _dictLoaded = false;
const USE_DICT_JSON: boolean = true;

@Entry
@Component
struct KeyboardPage {
  @StorageLink('inputState') inputState: string = InputState.IDLE;
  @StorageLink('inputMode') inputMode: string = InputMode.HIRAGANA;
  @StorageLink('composingText') composingText: string = '';
  @StorageLink('pendingRomaji') pendingRomaji: string = '';
  @StorageLink('candidates') candidates: string[] = [];
  @StorageLink('selectedCandidateIndex') selectedIndex: number = 0;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  @StorageLink('keyboardLayout') keyboardLayout: string = 'QWERTY';
  @StorageLink('keyboardSubMode') keyboardSubMode: string = 'kana';
  @StorageLink('bunsetsuTexts') bunsetsuTexts: string[] = [];
  @StorageLink('bunsetsuRaw') bunsetsuRaw: string[] = [];
  @StorageLink('bunsetsuCurrent') bunsetsuCurrent: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('clipboardPreview') clipboardPreview: string = '';
  @StorageLink('clipboardIsImage') clipboardIsImage: boolean = false;
  // TEMP DIAGNOSTIC — see matching comment in KeyboardController.computeKeyWidths.
  @StorageLink('dbgPreCutout') dbgPreCutout: string = '';
  @State dbgMeasured: string = '';
  @StorageLink('keyWidthVp') dbgAppliedKw: number = 0;

  aboutToAppear(): void {
    if (!_dictLoaded && USE_DICT_JSON) {
      _dictLoaded = true;
      getContext(this).resourceManager.getRawFileContent('dict.json')
        .then((data: Uint8Array) => {
          const decoder = new util.TextDecoder('utf-8');
          const text = decoder.decode(data);
          KanaKanjiConverter.loadDictionary(JSON.parse(text) as Record<string, string[]>);
        })
        .catch((_e: Error) => {});
    }

    if (_inputStartRegistered) { return; }
    _inputStartRegistered = true;
    inputMethodEngine.getInputMethodAbility().on('inputStart', (
      kbCtrl: inputMethodEngine.KeyboardController,
      client: inputMethodEngine.InputClient
    ) => {
      InputHandler.getInstance().onInputStart(kbCtrl, client);
    });
  }

  onBackPress(): boolean {
    InputHandler.getInstance().hideKeyboard();
    return true;
  }

  build() {
    Column() {
      // TEMP DIAGNOSTIC STRIP — remove once the landscape width bug is confirmed
      // fixed. Shows the raw numbers behind key sizing so a screenshot tells us
      // exactly what's wrong instead of guessing again.
      if (this.isLandscape) {
        Text(`${this.dbgPreCutout} | measured${this.dbgMeasured} kw${this.dbgAppliedKw}`)
          .fontSize(9)
          .fontColor('#FF5555')
          .backgroundColor('#000000')
          .maxLines(2)
          .width('100%')
      }
      // Symbol/Emoji/Numeric views take the full panel (no preview bar)
      if (this.keyboardSubMode === 'symbol') {
        SymbolView()
      } else if (this.keyboardSubMode === 'emoji') {
        EmojiView()
      } else if (this.keyboardSubMode === 'numeric') {
        NumericPadView()
      } else {
        // Preview bar
        if (this.inputState === InputState.BUNSETSU) {
          // Two-row preview: segment chips on top, candidates below
          Column() {
            BunsetsuBar({
              segments: this.bunsetsuTexts,
              currentIndex: this.bunsetsuCurrent
            })
            CandidateBar({
              candidates: this.candidates,
              selectedIndex: this.selectedIndex
            })
          }
          .width('100%')
          .backgroundColor(kbTheme(this.isDark).selectingBarBg)
          .borderWidth({ bottom: 1 })
          .borderColor(kbTheme(this.isDark).borderColor)
        } else {
          Column() {
            // Composing kana strip — always visible to prevent layout shifts.
            // Landscape has much less vertical room to spare for the keys below,
            // so this strip and the candidate row underneath both run compact.
            Row() {
              Text(this.composingText + this.pendingRomaji)
                .fontSize(this.isLandscape ? 13 : 16)
                .fontColor(kbTheme(this.isDark).previewText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 12, right: 8 })
                .layoutWeight(1)
            }
            .width('100%')
            .height(this.isLandscape ? 18 : 28)
            .backgroundColor(kbTheme(this.isDark).composingBarBg)
            .borderWidth({ bottom: 1 })
            .borderColor(kbTheme(this.isDark).borderColor)
            .alignItems(VerticalAlign.Center)

            // Candidate bar row + layout toggle
            Row() {
              Row() {
                if (this.candidates.length > 0) {
                  CandidateBar({
                    candidates: this.candidates,
                    selectedIndex: this.selectedIndex
                  })
                } else if (this.composingText.length === 0 && this.pendingRomaji.length === 0 &&
                  this.clipboardPreview.length > 0) {
                  Text(this.clipboardPreview)
                    .fontSize(this.isLandscape ? 13 : 16)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding(this.isLandscape ?
                      { left: 10, right: 10, top: 3, bottom: 3 } :
                      { left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(4)
                    .backgroundColor(kbTheme(this.isDark).candidateBg)
                    .fontColor(kbTheme(this.isDark).subText)
                    .margin({ left: 4 })
                    .onClick(() => {
                      InputHandler.getInstance().pasteClipboard();
                    })
                }
              }
              .width('82%')
              .height(this.isLandscape ? 32 : 48)
              .alignItems(VerticalAlign.Center)

              // Layout toggle: フ = switch to flick, Q = switch to QWERTY
              Text(this.keyboardLayout === 'FLICK' ? 'Q' : 'フ')
                .fontSize(this.isLandscape ? 12 : 14)
                .fontColor(kbTheme(this.isDark).subText)
                .textAlign(TextAlign.Center)
                .width(this.isLandscape ? 38 : 50)
                .height(this.isLandscape ? 26 : 40)
                .backgroundColor(kbTheme(this.isDark).funcKeyBg)
                .borderRadius(6)
                .onClick(() => {
                  const next = this.keyboardLayout === 'FLICK' ? 'QWERTY' : 'FLICK';
                  AppStorage.setOrCreate('keyboardLayout', next);
                })
            }
            .width('100%')
            .height(this.isLandscape ? 32 : 48)
            .backgroundColor(
              this.inputState === InputState.SELECTING ? kbTheme(this.isDark).selectingBarBg : kbTheme(this.isDark).previewBarBg
            )
            .borderWidth({ bottom: 1 })
            .borderColor(kbTheme(this.isDark).borderColor)
            .alignItems(VerticalAlign.Center)
            .padding({ right: 4 })
          }
          .width('100%')
        }

        // Keyboard — fills all height remaining after the preview bar
        if (this.keyboardLayout === 'FLICK' && this.inputMode !== InputMode.ALPHANUMERIC) {
          FlickKeyboardView({
            inputMode: this.inputMode,
            isLandscape: this.isLandscape
          })
            .layoutWeight(1)
        } else {
          KeyboardView({
            inputMode: this.inputMode,
            isLandscape: this.isLandscape
          })
            .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // Confirmed via on-device diagnostics: this device's IME panel framework
      // silently shrinks the panel to a fraction of the width/height requested
      // via panel.resize() (observed ~76% width, ~48% height of the request,
      // with no corresponding cutout/waterfall reported) — a software policy,
      // not a hardware inset, so it isn't queryable up front. Key widths must
      // be driven by what this root view actually measures, not by display
      // metrics or the resize request.
      this.dbgMeasured = `${newArea.width}x${newArea.height}`;
      const measuredVp = Number(newArea.width);
      if (measuredVp > 0) {
        const isTabletClass = AppStorage.get<boolean>('isTabletClass') ?? false;
        applyKeyboardWidthsForVp(measuredVp, isTabletClass);
      }
    })
  }
}
