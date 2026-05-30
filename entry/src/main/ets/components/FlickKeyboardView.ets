import { InputHandler, InputMode } from '../ime/KeyboardController';
import { toKatakana } from '../ime/JapaneseConverter';

type FlickDir = 'center' | 'up' | 'right' | 'down' | 'left';

interface FlickKeyDef {
  center: string;
  up?: string;
  right?: string;
  down?: string;
  left?: string;
  special?: string;
}

function getKanaByDir(key: FlickKeyDef, dir: FlickDir): string {
  if (dir === 'up' && key.up !== undefined) { return key.up; }
  if (dir === 'right' && key.right !== undefined) { return key.right; }
  if (dir === 'down' && key.down !== undefined) { return key.down; }
  if (dir === 'left' && key.left !== undefined) { return key.left; }
  return key.center;
}

const FLICK_GRID: FlickKeyDef[][] = [
  [
    { center: 'あ', up: 'い', right: 'う', down: 'え', left: 'お' },
    { center: 'か', up: 'き', right: 'く', down: 'け', left: 'こ' },
    { center: 'さ', up: 'し', right: 'す', down: 'せ', left: 'そ' },
  ],
  [
    { center: 'た', up: 'ち', right: 'つ', down: 'て', left: 'と' },
    { center: 'な', up: 'に', right: 'ぬ', down: 'ね', left: 'の' },
    { center: 'は', up: 'ひ', right: 'ふ', down: 'へ', left: 'ほ' },
  ],
  [
    { center: 'ま', up: 'み', right: 'む', down: 'め', left: 'も' },
    { center: 'や', right: 'ゆ', left: 'よ' },
    { center: 'ら', up: 'り', right: 'る', down: 'れ', left: 'ろ' },
  ],
  [
    { center: '゛', up: '゜', down: '小', special: 'dakuten' },
    { center: 'わ', right: 'を', down: 'ん', left: 'ー' },
    { center: '⌫', special: 'backspace' },
  ],
];

@Component
export struct FlickKeyboardView {
  @Prop inputMode: string = InputMode.HIRAGANA;
  @Prop isLandscape: boolean = false;
  @StorageLink('flickKeyWidthVp') flickKeyWidthVp: number = 120;

  @State activeRow: number = -1;
  @State activeCol: number = -1;
  @State touchStartX: number = 0;
  @State touchStartY: number = 0;
  @State flickDir: FlickDir = 'center';

  private readonly THRESHOLD: number = 20;

  private h(): InputHandler {
    return InputHandler.getInstance();
  }

  private toMode(kana: string): string {
    if (this.inputMode === InputMode.KATAKANA && /[ぁ-ん]/.test(kana)) {
      return toKatakana(kana);
    }
    return kana;
  }

  private rowH(): number {
    return this.isLandscape ? 40 : 56;
  }

  private dirFrom(dx: number, dy: number): FlickDir {
    if (Math.abs(dx) < this.THRESHOLD && Math.abs(dy) < this.THRESHOLD) { return 'center'; }
    if (Math.abs(dx) >= Math.abs(dy)) { return dx > 0 ? 'right' : 'left'; }
    return dy < 0 ? 'up' : 'down';
  }

  private isActive(row: number, col: number): boolean {
    return this.activeRow === row && this.activeCol === col;
  }

  private hintColor(row: number, col: number, dir: FlickDir): ResourceColor {
    if (this.isActive(row, col) && this.flickDir === dir) { return '#1565C0'; }
    return '#999999';
  }

  private centerLabel(row: number, col: number, key: FlickKeyDef): string {
    if (key.special !== undefined) { return key.center; }
    if (this.isActive(row, col)) { return this.toMode(getKanaByDir(key, this.flickDir)); }
    return this.toMode(key.center);
  }

  private keyBg(row: number, col: number, key: FlickKeyDef): ResourceColor {
    if (key.special !== undefined) { return '#ADB5BD'; }
    if (this.isActive(row, col)) { return '#B8D4F0'; }
    return '#FFFFFF';
  }

  private onCommit(key: FlickKeyDef, dir: FlickDir): void {
    if (key.special === 'backspace') {
      this.h().handleBackspace();
      return;
    }
    if (key.special === 'dakuten') {
      if (dir === 'center' || dir === 'right') {
        this.h().handleDakuten();
      } else if (dir === 'up') {
        this.h().handleHandakuten();
      } else if (dir === 'down') {
        this.h().handleSmall();
      }
      return;
    }
    const kana = this.toMode(getKanaByDir(key, dir));
    this.h().handleDirectKana(kana);
  }

  private onTouch(e: TouchEvent, row: number, col: number, key: FlickKeyDef): void {
    if (e.type === TouchType.Down) {
      const t = e.touches[0];
      this.touchStartX = t.x;
      this.touchStartY = t.y;
      this.activeRow = row;
      this.activeCol = col;
      this.flickDir = 'center';
    } else if (e.type === TouchType.Move) {
      if (this.isActive(row, col) && e.touches.length > 0) {
        const t = e.touches[0];
        this.flickDir = this.dirFrom(t.x - this.touchStartX, t.y - this.touchStartY);
      }
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      if (this.isActive(row, col)) {
        const tc = e.changedTouches.length > 0 ? e.changedTouches[0] : e.touches[0];
        const dir = this.dirFrom(tc.x - this.touchStartX, tc.y - this.touchStartY);
        this.onCommit(key, dir);
      }
      this.activeRow = -1;
      this.activeCol = -1;
      this.flickDir = 'center';
    }
  }

  build() {
    Column({ space: 3 }) {
      ForEach([0, 1, 2, 3], (rowIdx: number) => {
        Row({ space: 3 }) {
          ForEach([0, 1, 2], (colIdx: number) => {
            this.KeyCell(rowIdx, colIdx, FLICK_GRID[rowIdx][colIdx])
          }, (colIdx: number) => String(colIdx))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }, (rowIdx: number) => String(rowIdx))

      // Function row
      Row({ space: 3 }) {
        this.FlickModeKey()
        this.FlickPuncKey('、', () => {
          this.h().commitTopCandidate();
          this.h().insertText('、');
        })
        this.FlickSpaceKey()
        this.FlickPuncKey('。', () => {
          this.h().commitTopCandidate();
          this.h().insertText('。');
        })
        this.FlickEnterKey()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ bottom: 8, top: 4 })
  }

  @Builder KeyCell(rowIdx: number, colIdx: number, key: FlickKeyDef) {
    Column({ space: 0 }) {
      // Top hint
      Text(key.up !== undefined ? this.toMode(key.up) : ' ')
        .fontSize(11)
        .fontColor(this.hintColor(rowIdx, colIdx, 'up'))
        .width('100%')
        .height('28%')
        .textAlign(TextAlign.Center)

      // Middle: left hint | center label | right hint
      Row({ space: 0 }) {
        Text(key.left !== undefined ? this.toMode(key.left) : ' ')
          .fontSize(11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'left'))
          .width('25%')
          .textAlign(TextAlign.Center)

        Text(this.centerLabel(rowIdx, colIdx, key))
          .fontSize(this.isActive(rowIdx, colIdx) ? 22 : 19)
          .fontColor(key.special !== undefined ? Color.White : Color.Black)
          .fontWeight(FontWeight.Medium)
          .width('50%')
          .textAlign(TextAlign.Center)

        Text(key.right !== undefined ? this.toMode(key.right) : ' ')
          .fontSize(11)
          .fontColor(this.hintColor(rowIdx, colIdx, 'right'))
          .width('25%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('44%')

      // Bottom hint
      Text(key.down !== undefined ? this.toMode(key.down) : ' ')
        .fontSize(11)
        .fontColor(this.hintColor(rowIdx, colIdx, 'down'))
        .width('100%')
        .height('28%')
        .textAlign(TextAlign.Center)
    }
    .width(this.flickKeyWidthVp)
    .height(this.rowH())
    .backgroundColor(this.keyBg(rowIdx, colIdx, key))
    .borderRadius(8)
    .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
    .onTouch((e: TouchEvent) => {
      this.onTouch(e, rowIdx, colIdx, key);
    })
  }

  @Builder FlickModeKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'あ'
      : this.inputMode === InputMode.KATAKANA ? 'ア'
      : 'A')
      .fontSize(15)
      .textAlign(TextAlign.Center)
      .width(52)
      .height(44)
      .backgroundColor('#ADB5BD')
      .fontColor(Color.White)
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.h().commitTopCandidate();
        const cur = AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA;
        const next = cur === InputMode.HIRAGANA ? InputMode.KATAKANA
          : cur === InputMode.KATAKANA ? InputMode.ALPHANUMERIC
          : InputMode.HIRAGANA;
        AppStorage.setOrCreate('inputMode', next);
      })
  }

  @Builder FlickPuncKey(label: string, action: () => void) {
    Text(label)
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(44)
      .height(44)
      .backgroundColor('#FFFFFF')
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(action)
  }

  @Builder FlickSpaceKey() {
    Text(this.inputMode === InputMode.HIRAGANA ? 'かな'
      : this.inputMode === InputMode.KATAKANA ? 'カナ'
      : 'space')
      .fontSize(14)
      .textAlign(TextAlign.Center)
      .width(120)
      .height(44)
      .backgroundColor('#FFFFFF')
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.h().handleSpaceKey();
      })
  }

  @Builder FlickEnterKey() {
    Text('⏎')
      .fontSize(17)
      .textAlign(TextAlign.Center)
      .width(52)
      .height(44)
      .backgroundColor('#4A90E2')
      .fontColor(Color.White)
      .borderRadius(5)
      .shadow({ radius: 1, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.h().handleEnterKey();
      })
  }
}
