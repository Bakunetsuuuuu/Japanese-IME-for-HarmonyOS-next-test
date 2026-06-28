import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

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
    ['“', '”', '.', '\u2018', '\u2019', 'ı', '¿', '¥'],
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

const LICENSE_TEXT: string =
  'shunti Japanese IME\n\n' +
  '■ 変換辞書 (dict.json)\n' +
  '独自収集データを使用しています。\n' +
  '・常用漢字（文部科学省告示、パブリックドメイン）\n' +
  '・Unicode Unihan データベース（パブリックドメイン）\n' +
  '・独自収録語彙（global_dict）\n\n' +
  '■ 文節分割コストデータ (reading_cost.json)\n' +
  'mecab-ipadic 2.7.0 を変換して使用しています。\n\n' +
  'Copyright 2000, 2001, 2002, 2003\n' +
  'Nara Institute of Science and Technology (NAIST).\n' +
  'All Rights Reserved.\n\n' +
  'ライセンス: NAIST License（商用利用可）\n\n' +
  '■ アプリコード\n' +
  'MIT License';

@Component
export struct SymbolView {
  @StorageLink('symKeyWidthVp') symKeyWidthVp: number = 46;
  @StorageLink('isDark') isDark: boolean = false;
  @State currentTab: number = 1;
  @State showLicense: boolean = false;

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
          .fontColor(kbTheme(this.isDark).onAccentText)
          .backgroundColor(kbTheme(this.isDark).specialKeyBg)
          .borderRadius(20)
          .onClick(() => {
            this.showLicense = false;
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        if (!this.showLicense) {
          // Category tabs
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
            Text(SYM_TABS[i])
              .fontSize(i === 1 ? 12 : 13)
              .textAlign(TextAlign.Center)
              .width(38).height(32)
              .fontColor(this.currentTab === i ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
              .backgroundColor(this.currentTab === i ? '#6C757D' : kbTheme(this.isDark).funcKeyBg)
              .borderRadius(8)
              .onClick(() => {
                this.currentTab = i;
              })
          }, (i: number) => String(i))
        } else {
          Text('ⓘ ライセンス')
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).subText)
            .padding({ left: 8 })
        }
      }
      .width('100%')
      .height(48)
      .padding({ left: 4, right: 4, top: 4 })
      .alignItems(VerticalAlign.Center)

      if (this.showLicense) {
        // ── License view ─────────────────────────────────────────
        Scroll() {
          Text(LICENSE_TEXT)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).previewText)
            .lineHeight(20)
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        .width('100%')
        .height(252)
        .backgroundColor(kbTheme(this.isDark).composingBarBg)
      } else {
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
                      .fontColor(kbTheme(this.isDark).keyText)
                      .backgroundColor(kbTheme(this.isDark).keyBg)
                      .borderRadius(6)
                      .shadow({ radius: 1, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
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
      }

      // ── Bottom function row ───────────────────────────────────
      Row({ space: 0 }) {
        // あいう — back to kana
        Text('あいう')
          .fontSize(13).textAlign(TextAlign.Center)
          .width(68).height(44)
          .fontColor(kbTheme(this.isDark).subText)
          .onClick(() => {
            this.showLicense = false;
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        // Emoji button → emoji panel
        Text('☺')
          .fontSize(17)
          .textAlign(TextAlign.Center)
          .width(46).height(44)
          .fontColor(kbTheme(this.isDark).subText)
          .backgroundColor(kbTheme(this.isDark).funcKeyBg)
          .borderRadius(8)
          .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'emoji'); })

        // ⓘ license info toggle
        Text('ⓘ')
          .fontSize(18).textAlign(TextAlign.Center)
          .width(46).height(44)
          .fontColor(this.showLicense ? kbTheme(this.isDark).onAccentText : kbTheme(this.isDark).subText)
          .backgroundColor(this.showLicense ? '#6C757D' : kbTheme(this.isDark).funcKeyBg)
          .borderRadius(8)
          .onClick(() => { this.showLicense = !this.showLicense; })

        // ⌫ backspace
        Text('⌫')
          .fontSize(18).textAlign(TextAlign.Center)
          .width(52).height(44)
          .fontColor(kbTheme(this.isDark).onAccentText)
          .backgroundColor(kbTheme(this.isDark).specialKeyBg)
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
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
