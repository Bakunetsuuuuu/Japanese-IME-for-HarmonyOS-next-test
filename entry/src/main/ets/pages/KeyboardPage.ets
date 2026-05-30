import inputMethodEngine from '@ohos.inputMethodEngine';
import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
import { CandidateBar } from '../components/CandidateBar';
import { KeyboardView } from '../components/KeyboardView';
import { FlickKeyboardView } from '../components/FlickKeyboardView';

// Prevent duplicate registration if aboutToAppear fires more than once
let _inputStartRegistered = false;

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

  aboutToAppear(): void {
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
      // Fixed-height preview row — always 48vp.
      Row() {
        // Preview content
        Row() {
          if (this.inputState === InputState.SELECTING && this.candidates.length > 0) {
            CandidateBar({
              candidates: this.candidates,
              selectedIndex: this.selectedIndex
            })
          } else {
            Text(this.composingText + this.pendingRomaji)
              .fontSize(16)
              .fontColor('#222222')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 10, right: 4 })
          }
        }
        .width('82%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        // Layout toggle: 'フ' switches to flick, 'Q' switches to QWERTY
        Text(this.keyboardLayout === 'FLICK' ? 'Q' : 'フ')
          .fontSize(14)
          .fontColor('#444444')
          .textAlign(TextAlign.Center)
          .width(50)
          .height(40)
          .backgroundColor('#C0C5CC')
          .borderRadius(6)
          .onClick(() => {
            const next = this.keyboardLayout === 'FLICK' ? 'QWERTY' : 'FLICK';
            AppStorage.setOrCreate('keyboardLayout', next);
          })
      }
      .width('100%')
      .height(48)
      .backgroundColor(
        this.inputState === InputState.SELECTING ? '#E0E3E8' : '#F0F2F5'
      )
      .borderWidth({ bottom: 1 })
      .borderColor('#CCCCCC')
      .alignItems(VerticalAlign.Center)
      .padding({ right: 4 })

      // Switch between flick and QWERTY (flick not used in alphanumeric mode)
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
    .width('100%')
    .height('100%')
    .backgroundColor('#D1D5DB')
  }
}
