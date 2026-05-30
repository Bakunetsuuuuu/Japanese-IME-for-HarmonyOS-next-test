import { InputHandler, InputState, InputMode } from '../ime/KeyboardController';
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
      // Single fixed-height bar: shows candidates (SELECTING) or composing text (COMPOSING)
      // Always occupies the same 48vp → no layout shift when content changes
      if (this.inputState === InputState.SELECTING && this.candidates.length > 0) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.candidates, (candidate: string, index: number) => {
              Text(candidate)
                .fontSize(16)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(4)
                .backgroundColor(index === this.selectedIndex ? '#4A90E2' : '#FFFFFF')
                .fontColor(index === this.selectedIndex ? Color.White : Color.Black)
                .onClick(() => {
                  InputHandler.getInstance().commitCandidate(index);
                })
            }, (c: string, i: number) => `${i}-${c}`)
          }
          .padding({ left: 4, right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(48)
        .backgroundColor('#E0E3E8')
        .borderWidth({ bottom: 1 })
        .borderColor('#CCCCCC')
      } else {
        Row() {
          Text(this.composingText + this.pendingRomaji)
            .fontSize(16)
            .fontColor('#222222')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 10, right: 10 })
            .visibility(
              this.composingText.length > 0 || this.pendingRomaji.length > 0
                ? Visibility.Visible : Visibility.Hidden
            )
        }
        .width('100%')
        .height(48)
        .backgroundColor('#F0F2F5')
        .borderWidth({ bottom: 1 })
        .borderColor('#CCCCCC')
        .alignItems(VerticalAlign.Center)
      }

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
