import { InputHandler } from '../ime/KeyboardController';

const SYM_TABS: string[] = ['🕐', '1?#', '( )', '→', '⊞', '①', '◇', '[全]'];

const SYMBOL_CATEGORIES: string[][][] = [
  // 0: 🕐 recently used — show subset of common symbols
  [
    ['、', '。', '！', '？', '・', '…', '〜', '―'],
    ['「', '」', '『', '』', '【', '】', '（', '）'],
    ['♪', '♥', '★', '☆', '◎', '○', '●', '◆'],
  ],
  // 1: 1?# — ASCII symbols
  [
    ['1', '2', '3', '4', '5', '6', '7', '8'],
    ['9', '0', '!', '@', '#', '$', '%', '^'],
    ['&', '*', '(', ')', "'", '"', '=', '_'],
    ['`', ':', ';', '?', '~', '|', '+', '-'],
    ['\\', '/', '[', ']', '{', '}', '<', '>'],
    ['“', '”', '.', '‘', '’', 'ı', '¿', '¥'],
    ['€', '£', '¢', '©', '®', '™', '℃', '°F'],
  ],
  // 2: ( ) brackets / Japanese punctuation
  [
    ['(', ')', '[', ']', '{', '}', '〈', '〉'],
    ['《', '》', '「', '」', '『', '』', '【', '】'],
    ['〔', '〕', '（', '）', '［', '］', '｛', '｝'],
    ['＜', '＞', '〝', '〟', '〃', '‥', '…', '―'],
    ['、', '。', '・', '：', '；', '！', '？', '〜'],
  ],
  // 3: → arrows
  [
    ['←', '→', '↑', '↓', '↖', '↗', '↘', '↙'],
    ['⇐', '⇒', '⇑', '⇓', '⇖', '⇗', '⇘', '⇙'],
    ['↔', '↕', '⇔', '⇕', '⤴', '⤵', '↩', '↪'],
    ['➡', '⬆', '⬇', '⬅', '↳', '↰', '↱', '↲'],
    ['▷', '▶', '◁', '◀', '▽', '▼', '△', '▲'],
  ],
  // 4: ⊞ math / special
  [
    ['×', '÷', '±', '∓', '√', '∞', 'π', 'μ'],
    ['∑', '∏', '∫', '∂', '∇', '°', '′', '″'],
    ['≠', '≈', '≡', '≤', '≥', '≪', '≫', '∝'],
    ['∈', '∉', '∅', '∩', '∪', '⊂', '⊃', '⊕'],
    ['α', 'β', 'γ', 'δ', 'θ', 'λ', 'σ', 'φ'],
  ],
  // 5: ① circled numbers / Roman numerals
  [
    ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧'],
    ['⑨', '⑩', '⑪', '⑫', '⑬', '⑭', '⑮', '⑯'],
    ['⑰', '⑱', '⑲', '⑳', '㉑', '㉒', '㉓', '㉔'],
    ['Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ', 'Ⅵ', 'Ⅶ', 'Ⅷ'],
    ['Ⅸ', 'Ⅹ', 'ⅰ', 'ⅱ', 'ⅲ', 'ⅳ', 'ⅴ', 'ⅵ'],
  ],
  // 6: ◇ shapes / symbols
  [
    ['★', '☆', '♠', '♥', '♦', '♣', '♪', '♫'],
    ['☀', '☁', '☂', '☃', '⚡', '❄', '✿', '❀'],
    ['♀', '♂', '☯', '☮', '✓', '✗', '✔', '✘'],
    ['◆', '◇', '■', '□', '▲', '△', '▼', '▽'],
    ['●', '○', '◎', '◉', '◈', '◊', '⬛', '⬜'],
  ],
  // 7: [全] full-width ASCII
  [
    ['！', '＂', '＃', '＄', '％', '＆', '＇', '（'],
    ['）', '＊', '＋', '，', '－', '．', '／', '：'],
    ['；', '＜', '＝', '＞', '？', '＠', '｛', '｝'],
    ['｜', '￥', '＾', '＿', '｀', '～', '【', '】'],
    ['Ａ', 'Ｂ', 'Ｃ', 'Ｄ', 'Ｅ', 'Ｆ', 'Ｇ', 'Ｈ'],
    ['Ｉ', 'Ｊ', 'Ｋ', 'Ｌ', 'Ｍ', 'Ｎ', 'Ｏ', 'Ｐ'],
    ['Ｑ', 'Ｒ', 'Ｓ', 'Ｔ', 'Ｕ', 'Ｖ', 'Ｗ', 'Ｘ'],
  ],
];

@Component
export struct SymbolView {
  @StorageLink('symKeyWidthVp') symKeyWidthVp: number = 46;
  @State currentTab: number = 1;

  private h(): InputHandler { return InputHandler.getInstance(); }

  private insert(sym: string): void {
    this.h().commitTopCandidate();
    this.h().insertText(sym);
  }

  build() {
    Column({ space: 0 }) {
      // ── Top tab row ──────────────────────────────────────────
      Row({ space: 2 }) {
        // ← back to kana
        Text('←')
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .width(48).height(40)
          .fontColor(Color.White)
          .backgroundColor('#ADB5BD')
          .borderRadius(20)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        // Category tabs
        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
          Text(SYM_TABS[i])
            .fontSize(i === 1 ? 12 : 13)
            .textAlign(TextAlign.Center)
            .width(38).height(32)
            .fontColor(this.currentTab === i ? Color.White : '#444444')
            .backgroundColor(this.currentTab === i ? '#6C757D' : '#C8CDD4')
            .borderRadius(8)
            .onClick(() => {
              this.currentTab = i;
            })
        }, (i: number) => String(i))
      }
      .width('100%')
      .height(48)
      .padding({ left: 4, right: 4, top: 4 })
      .alignItems(VerticalAlign.Center)

      // ── Symbol grid (scrollable) ──────────────────────────────
      Scroll() {
        Column({ space: 2 }) {
          ForEach([0, 1, 2, 3, 4, 5, 6], (rowIdx: number) => {
            if (rowIdx < SYMBOL_CATEGORIES[this.currentTab].length) {
              Row({ space: 2 }) {
                ForEach(SYMBOL_CATEGORIES[this.currentTab][rowIdx], (sym: string) => {
                  Text(sym)
                    .fontSize(sym.length > 1 ? 12 : 17)
                    .textAlign(TextAlign.Center)
                    .width(this.symKeyWidthVp)
                    .height(34)
                    .fontColor(Color.Black)
                    .backgroundColor('#FFFFFF')
                    .borderRadius(6)
                    .shadow({ radius: 1, color: '#33000000', offsetY: 1 })
                    .onClick(() => { this.insert(sym); })
                }, (sym: string) => String(this.currentTab) + sym)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
          }, (rowIdx: number) => String(rowIdx))
        }
        .width('100%')
        .padding({ top: 2 })
      }
      .width('100%')
      .height(252)

      // ── Bottom function row ───────────────────────────────────
      Row({ space: 0 }) {
        // あいう — back to kana
        Text('あいう')
          .fontSize(13).textAlign(TextAlign.Center)
          .width(68).height(44)
          .fontColor('#444444')
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        // Emoji / GIF / Sticker / Emoticons (visual only)
        ForEach(['😊', 'GIF', '🎨', ':-)'], (btn: string) => {
          Text(btn)
            .fontSize(btn === 'GIF' ? 13 : 17)
            .textAlign(TextAlign.Center)
            .width(btn === 'GIF' ? 52 : 46).height(44)
            .fontColor('#444444')
            .backgroundColor('#C8CDD4')
            .borderRadius(8)
        }, (btn: string) => btn)

        // ☆ favorites (visual)
        Text('☆')
          .fontSize(18).textAlign(TextAlign.Center)
          .width(46).height(44)
          .fontColor('#444444')
          .backgroundColor('#B0B7BF')
          .borderRadius(8)

        // ⌫ backspace
        Text('⌫')
          .fontSize(18).textAlign(TextAlign.Center)
          .width(52).height(44)
          .fontColor(Color.White)
          .backgroundColor('#ADB5BD')
          .borderRadius(8)
          .onClick(() => { this.h().handleBackspace(); })
      }
      .width('100%')
      .height(52)
      .padding({ left: 4, right: 4, bottom: 4 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#D1D5DB')
  }
}
