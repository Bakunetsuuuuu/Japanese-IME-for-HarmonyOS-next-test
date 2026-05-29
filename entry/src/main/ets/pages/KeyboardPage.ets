import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
import { CandidateBar } from '../components/CandidateBar';
import { KeyboardView } from '../components/KeyboardView';

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

  onBackPress(): boolean {
    InputHandler.getInstance().hideKeyboard();
    return true;
  }

  build() {
    Column() {
      // Composing text preview (visible while typing romaji / kana)
      if (this.composingText.length > 0 || this.pendingRomaji.length > 0) {
        Row() {
          Text(this.composingText + this.pendingRomaji)
            .fontSize(16)
            .fontColor('#222222')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 10, right: 10 })
        }
        .width('100%')
        .height(40)
        .backgroundColor('#F0F2F5')
        .borderWidth({ bottom: 1 })
        .borderColor('#CCCCCC')
        .alignItems(VerticalAlign.Center)
      }

      // Candidate bar (visible during kanji selection)
      if (this.inputState === InputState.SELECTING && this.candidates.length > 0) {
        CandidateBar({
          candidates: this.candidates,
          selectedIndex: this.selectedIndex
        })
      }

      // Main keyboard body
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
