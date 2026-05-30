import inputMethodEngine from '@ohos.inputMethodEngine';
import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
import { CandidateBar } from '../components/CandidateBar';
import { KeyboardView } from '../components/KeyboardView';

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

  // Register inputStart in the panel UI engine so this engine's InputHandler
  // also receives inputClient — without this, deleteBackward/insertText are no-ops.
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
      // Fixed-height preview row — always 48vp so the keyboard never shifts.
      // Shows candidates when selecting, composing kana otherwise (empty when idle).
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
            .padding({ left: 10, right: 10 })
        }
      }
      .width('100%')
      .height(48)
      .backgroundColor(
        this.inputState === InputState.SELECTING ? '#E0E3E8' : '#F0F2F5'
      )
      .borderWidth({ bottom: 1 })
      .borderColor('#CCCCCC')
      .alignItems(VerticalAlign.Center)

      // Main keyboard
      KeyboardView({
        inputMode: this.inputMode,
        isLandscape: this.isLandscape
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#D1D5DB')
  }
}
