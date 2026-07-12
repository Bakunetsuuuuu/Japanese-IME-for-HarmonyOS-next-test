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
import { SettingsBar } from '../components/SettingsBar';
import { SettingsStore, KeyboardSettings } from '../ime/SettingsStore';
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
  @StorageLink('clipboardHistory') clipboardHistory: string[] = [];
  @StorageLink('oneHandedMode') oneHandedMode: boolean = false;
  @StorageLink('oneHandedSide') oneHandedSide: string = 'right';
  @State showSettingsBar: boolean = false;

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

    // aboutToAppear runs every time this panel's content is (re)constructed —
    // a more reliable reload point than onPageShow, which per ArkUI docs is a
    // Navigation/Router page-lifecycle hook and may never fire for content
    // hosted in an InputMethodExtensionAbility's Panel (a window, not a routed
    // page). Kept unguarded (unlike the inputStart listener below) since
    // rereading a small preferences store is cheap.
    this.reloadSettingsIntoStorage();

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

  // onInputStart only fires for a genuinely new input session — switching to
  // the main app to change the keyboard layout and back doesn't necessarily
  // trigger one if the panel itself just gets hidden/reshown. Kept alongside
  // aboutToAppear's call in case this panel *is* managed as a routed page on
  // some devices/OS versions after all.
  onPageShow(): void {
    console.info('shuntiIME KeyboardPage.onPageShow fired');
    this.reloadSettingsIntoStorage();
  }

  private reloadSettingsIntoStorage(): void {
    SettingsStore.load(getContext(this), true).then((s: KeyboardSettings) => {
      console.info('shuntiIME KeyboardPage settings reload applied', JSON.stringify(s));
      AppStorage.setOrCreate('keyboardLayout', s.keyboardLayout);
      AppStorage.setOrCreate('oneHandedMode', s.oneHandedMode);
      AppStorage.setOrCreate('oneHandedSide', s.oneHandedSide);
    });
  }

  build() {
    Stack() {
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
              .height(this.isLandscape ? 22 : 84)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)

              // Settings bar: clipboard history, app shortcut, one-handed mode,
              // AppGallery review. The flick/QWERTY toggle that used to live here
              // moved into the main app's settings screen (SettingsStore-backed).
              Text('⚙')
                .fontSize(this.isLandscape ? 12 : 16)
                .fontColor(kbTheme(this.isDark).subText)
                .textAlign(TextAlign.Center)
                .width(this.isLandscape ? 32 : 50)
                .height(this.isLandscape ? 20 : 40)
                .backgroundColor(kbTheme(this.isDark).funcKeyBg)
                .borderRadius(6)
                .onClick(() => {
                  this.showSettingsBar = !this.showSettingsBar;
                })
            }
            .width('100%')
            .height(this.isLandscape ? 22 : 84)
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

        // Keyboard — fills all height remaining after the preview bar.
        // One-handed mode shrinks+docks this via a scale transform anchored to
        // an edge, rather than touching the pixel-tuned computeKeyWidths /
        // applyKeyboardWidthsForVp system: each inner view still measures and
        // lays out its keys at full intended size, then this wrapper visually
        // (and for hit-testing) scales the whole thing down toward one side.
        Column() {
          if (this.keyboardSubMode === 'numeric') {
            NumericPadView()
          } else if (this.keyboardLayout === 'FLICK' && this.inputMode !== InputMode.ALPHANUMERIC) {
            FlickKeyboardView({
              inputMode: this.inputMode,
              isLandscape: this.isLandscape
            })
          } else {
            KeyboardView({
              inputMode: this.inputMode,
              isLandscape: this.isLandscape
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scale(this.oneHandedMode ?
          { x: 0.78, y: 0.78, centerX: this.oneHandedSide === 'left' ? '0%' : '100%', centerY: '100%' } :
          { x: 1, y: 1 })
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

    if (this.showSettingsBar) {
      SettingsBar({ visible: this.showSettingsBar })
    }
    }
    .width('100%')
    .height('100%')
  }
}
