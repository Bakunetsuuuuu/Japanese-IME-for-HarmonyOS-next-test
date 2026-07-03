import inputMethodEngine from '@ohos.inputMethodEngine';
import util from '@ohos.util';
import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
import { KanaKanjiConverter } from '../ime/KanaKanjiConverter';
import { CandidateBar } from '../components/CandidateBar';
import { KeyboardView } from '../components/KeyboardView';
import { FlickKeyboardView } from '../components/FlickKeyboardView';
import { AlphabetFlickKeyboardView } from '../components/AlphabetFlickKeyboardView';
import { SymbolView } from '../components/SymbolView';
import { EmojiView } from '../components/EmojiView';
import { BunsetsuBar } from '../components/BunsetsuBar';
import { ExpandedCandidateView } from '../components/ExpandedCandidateView';
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
  @StorageLink('convEnd') convEnd: number = 0;
  @StorageLink('candidateExpanded') candidateExpanded: boolean = false;
  @StorageLink('clipboardPreview') clipboardPreview: string = '';
  @StorageLink('clipboardIsImage') clipboardIsImage: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';

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
      if (this.keyboardSubMode === 'symbol') {
        SymbolView()
      } else if (this.keyboardSubMode === 'emoji') {
        EmojiView()
      } else {
        if (this.inputState === InputState.BUNSETSU) {
          Column() {
            BunsetsuBar({ segments: this.bunsetsuTexts, currentIndex: this.bunsetsuCurrent })
            CandidateBar({ candidates: this.candidates, selectedIndex: this.selectedIndex, showExpand: true })
          }
          .width('100%').backgroundColor(kbTheme(this.isDark, this.themeVariant).selectingBarBg)
          .borderWidth({ bottom: 1 }).borderColor(kbTheme(this.isDark, this.themeVariant).borderColor)
        } else {
          Column() {
            Row() {
              if (this.composingText.length > 0 || this.pendingRomaji.length > 0) {
                if (this.convEnd > 0 && this.convEnd < this.composingText.length) {
                  Text(this.composingText.slice(0, this.convEnd))
                    .fontSize(18).fontWeight(FontWeight.Medium)
                    .fontColor(kbTheme(this.isDark, this.themeVariant).previewText).maxLines(1).decoration({ type: TextDecorationType.Underline })
                  Text(this.composingText.slice(this.convEnd))
                    .fontSize(16).fontColor(kbTheme(this.isDark, this.themeVariant).subText).maxLines(1)
                } else {
                  Text(this.composingText).fontSize(18).fontWeight(FontWeight.Medium)
                    .fontColor(kbTheme(this.isDark, this.themeVariant).previewText).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(this.pendingRomaji).fontSize(16)
                  .fontColor(kbTheme(this.isDark, this.themeVariant).subText).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%').height(32).backgroundColor(kbTheme(this.isDark, this.themeVariant).composingBarBg)
            .borderRadius({ topLeft: 8, topRight: 8 }).padding({ left: 12, right: 8 }).alignItems(VerticalAlign.Center)

            Row() {
              Row() {
                if (this.candidates.length > 0) {
                  CandidateBar({ candidates: this.candidates, selectedIndex: this.selectedIndex, showExpand: true })
                } else if (this.composingText.length === 0 && this.pendingRomaji.length === 0 &&
                  this.clipboardPreview.length > 0) {
                  Text(this.clipboardPreview).fontSize(16).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(10)
                    .backgroundColor(kbTheme(this.isDark, this.themeVariant).candidateBg).fontColor(kbTheme(this.isDark, this.themeVariant).subText).margin({ left: 4 })
                    .onClick(() => { InputHandler.getInstance().pasteClipboard(); })
                }
              }
              .width('100%').height(48).alignItems(VerticalAlign.Center)
            }
            .width('100%').height(48)
            .backgroundColor(this.inputState === InputState.SELECTING ? kbTheme(this.isDark, this.themeVariant).selectingBarBg : kbTheme(this.isDark, this.themeVariant).previewBarBg)
            .borderWidth({ bottom: 1 }).borderColor(kbTheme(this.isDark, this.themeVariant).borderColor)
            .alignItems(VerticalAlign.Center).padding({ right: 4 })
          }
          .width('100%')
        }

        if (this.candidateExpanded && this.candidates.length > 0) {
          ExpandedCandidateView({ candidates: this.candidates, selectedIndex: this.selectedIndex }).layoutWeight(1)
        } else if (this.keyboardLayout === 'FLICK' && this.inputMode !== InputMode.ALPHANUMERIC) {
          FlickKeyboardView({ inputMode: this.inputMode, isLandscape: this.isLandscape }).layoutWeight(1)
        } else if (this.keyboardLayout === 'FLICK' && this.inputMode === InputMode.ALPHANUMERIC) {
          AlphabetFlickKeyboardView({ inputMode: this.inputMode, isLandscape: this.isLandscape }).layoutWeight(1)
        } else {
          KeyboardView({ inputMode: this.inputMode, isLandscape: this.isLandscape }).layoutWeight(1)
        }
      }
    }
    .width('100%').height('100%').backgroundColor(kbTheme(this.isDark, this.themeVariant).panelBg)
  }
}
