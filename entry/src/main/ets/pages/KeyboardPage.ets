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
      // Symbol/Emoji views take the full panel (no preview bar). Numeric keeps
      // the preview bar — without it the pad's rows stretch to fill the whole
      // panel height and end up uncomfortably tall.
      if (this.keyboardSubMode === 'symbol') {
        SymbolView()
      } else if (this.keyboardSubMode === 'emoji') {
        EmojiView()
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
                .fontSize(this.isLandscape ? 11 : 16)
                .fontColor(kbTheme(this.isDark).previewText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 12, right: 8 })
                .layoutWeight(1)
            }
            .width('100%')
            .height(this.isLandscape ? 14 : 28)
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
                  // Gboard-style: centered paste suggestion when nothing is composing,
                  // rather than left-aligned like an actual conversion candidate.
                  Text(this.clipboardPreview)
                    .fontSize(this.isLandscape ? 11 : 16)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // Cap how wide the chip can grow instead of letting it stretch to
                    // fill the row — short clips hug their text, long ones truncate
                    // with "…" at the cap instead of a background that runs on past
                    // where the (ellipsized) text actually ends.
                    .constraintSize({ maxWidth: '90%' })
                    .padding(this.isLandscape ?
                      { left: 8, right: 8, top: 2, bottom: 2 } :
                      { left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(4)
                    .backgroundColor(kbTheme(this.isDark).candidateBg)
                    .fontColor(kbTheme(this.isDark).subText)
                    .onClick(() => {
                      InputHandler.getInstance().pasteClipboard();
                    })
                }
              }
              .width('82%')
              .height(this.isLandscape ? 22 : 48)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)

              // Layout toggle: フ = switch to flick, Q = switch to QWERTY
              Text(this.keyboardLayout === 'FLICK' ? 'Q' : 'フ')
                .fontSize(this.isLandscape ? 10 : 14)
                .fontColor(kbTheme(this.isDark).subText)
                .textAlign(TextAlign.Center)
                .width(this.isLandscape ? 32 : 50)
                .height(this.isLandscape ? 20 : 40)
                .backgroundColor(kbTheme(this.isDark).funcKeyBg)
                .borderRadius(6)
                .onClick(() => {
                  const next = this.keyboardLayout === 'FLICK' ? 'QWERTY' : 'FLICK';
                  AppStorage.setOrCreate('keyboardLayout', next);
                })
            }
            .width('100%')
            .height(this.isLandscape ? 22 : 48)
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
        if (this.keyboardSubMode === 'numeric') {
          NumericPadView()
            .layoutWeight(1)
        } else if (this.keyboardLayout === 'FLICK' && this.inputMode !== InputMode.ALPHANUMERIC) {
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
      // silently shrinks the panel to a fraction of the width requested via
      // panel.resize() (~76% observed, with no corresponding cutout reported —
      // a software policy, not a hardware inset), so it isn't queryable up
      // front. Correct key widths from what this root view actually measures,
      // and also record the (measured / raw guess) ratio as a learned scale
      // factor — see KeyboardController.computeKeyWidths for why: this panel
      // is reused across show/hide, so a later resize may not be followed by
      // a fresh onAreaChange, and the learned scale lets that next guess
      // start out already corrected instead of reverting to the raw width.
      const measuredVp = Number(newArea.width);
      if (measuredVp > 0) {
        const isTabletClass = AppStorage.get<boolean>('isTabletClass') ?? false;
        applyKeyboardWidthsForVp(measuredVp, isTabletClass);
        if (!isTabletClass) {
          const rawFullVp = AppStorage.get<number>('lastRawFullVp') ?? 0;
          if (rawFullVp > 0) {
            const ratio = Math.min(1, Math.max(0.3, measuredVp / rawFullVp));
            const isLand = AppStorage.get<boolean>('lastRawFullVpIsLandscape') ?? this.isLandscape;
            AppStorage.setOrCreate(isLand ? 'widthScaleLandscape' : 'widthScalePortrait', ratio);
          }
        }
      }
    })
  }
}
