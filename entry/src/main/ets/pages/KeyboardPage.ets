import inputMethodEngine from '@ohos.inputMethodEngine';
import util from '@ohos.util';
import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
import { KanaKanjiConverter } from '../ime/KanaKanjiConverter';
import { CandidateBar } from '../components/CandidateBar';
import { KeyboardView } from '../components/KeyboardView';
import { FlickKeyboardView } from '../components/FlickKeyboardView';
import { SymbolView } from '../components/SymbolView';
import { EmojiView } from '../components/EmojiView';
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
      // Symbol/Emoji views take the full panel (no preview bar)
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
            // Composing kana strip — always visible to prevent layout shifts
            Row() {
              Text(this.composingText + this.pendingRomaji)
                .fontSize(16)
                .fontColor(kbTheme(this.isDark).previewText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 12, right: 8 })
                .layoutWeight(1)
            }
            .width('100%')
            .height(28)
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
                }
              }
              .width('82%')
              .height(48)
              .alignItems(VerticalAlign.Center)

              // Layout toggle: フ = switch to flick, Q = switch to QWERTY
              Text(this.keyboardLayout === 'FLICK' ? 'Q' : 'フ')
                .fontSize(14)
                .fontColor(kbTheme(this.isDark).subText)
                .textAlign(TextAlign.Center)
                .width(50)
                .height(40)
                .backgroundColor(kbTheme(this.isDark).funcKeyBg)
                .borderRadius(6)
                .onClick(() => {
                  const next = this.keyboardLayout === 'FLICK' ? 'QWERTY' : 'FLICK';
                  AppStorage.setOrCreate('keyboardLayout', next);
                })
            }
            .width('100%')
            .height(48)
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

        // Keyboard
        if (this.keyboardLayout === 'FLICK' && this.inputMode !== InputMode.ALPHANUMERIC) {
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
