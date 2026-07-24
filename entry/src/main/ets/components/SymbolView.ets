import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

const SYM_TABS: string[] = ['🕐', '1?#', '( )', '→', '⊞', '①', '◇', '[全]'];

// Fallback for the 🕐 tab until the user has actually tapped enough symbols
// for real usage data (see InputHandler.recordSymbolUse/publishFrequentSymbols)
// to fill it in.
const DEFAULT_RECENT_SYMBOLS: string[] = [
  '、', '。', '！', '？', '・', '…', '〜', '―',
  '「', '」', '『', '』', '【', '】', '（', '）',
  '♪', '♥', '★', '☆', '◎', '○', '●', '◆',
];

const SYMBOL_CATEGORIES: string[][][] = [
  // 0: 🕐 recently used — replaced at render time by SymbolView.recentRows()
  [],
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

const LICENSE_TEXT: string =
  'shunti Japanese IME\n\n' +
  '■ 変換辞書 (dict.json, global_dict.json)\n' +
  '独自収集データを使用しています。\n' +
  '・常用漢字（文部科学省告示、パブリックドメイン）\n' +
  '・Unicode Unihan データベース（パブリックドメイン）\n' +
  '・Wikipedia日本語版から収集した読み情報（CC BY-SA 4.0）\n' +
  '・Wiktionary日本語版から収集した読み情報\n' +
  '  （CC BY-SA 4.0 / GFDL、ja.wiktionary.org）\n' +
  '・JMdict/EDICT（電子化辞書研究開発グループ、CC BY-SA 4.0）\n' +
  '  https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project\n' +
  '・日本郵便 郵便番号データ\n' +
  '・独自収録語彙（global_dict）\n\n' +
  '詳細な出典一覧は DATA_SOURCES.md を参照してください。\n\n' +
  '■ 文節分割\n' +
  '外部データファイルには依存せず、文法ルールをアプリ内に実装した\n' +
  '独自のViterbiアルゴリズムで分割しています。\n\n' +
  '■ 統計データ変換エンジン (mozc_dict.json 等, 設定でオプション有効化)\n' +
  '上記の独自辞書とは完全に別データの、切り替え式の第二変換エンジンです。\n' +
  '・mozc（Google, BSD-3-Clause）\n' +
  '  https://github.com/google/mozc\n' +
  '・JMdict/EDICT（電子化辞書研究開発グループ、CC BY-SA 4.0）\n' +
  '  https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project\n' +
  '・SudachiDict（Works Applications, Apache License 2.0）\n' +
  '  https://github.com/WorksApplications/SudachiDict\n' +
  '詳細なライセンス全文は THIRD_PARTY_NOTICES.md を参照してください。\n\n' +
  '■ アプリコード\n' +
  'MIT License';

// Grid area budget (unchanged from before the redesign, so the overall
// keyboard body height doesn't shift when switching into the symbol panel).
const GRID_AREA_H = 252;
const GRID_ROW_GAP = 4;
// Row height is computed per tab (row count ranges 1-7 across categories/the
// usage-based recent tab) but capped so a low-row tab (e.g. 🕐 with only 1-3
// rows) gets modestly bigger buttons instead of a few buttons stretched into
// tall rectangles — the remaining slack is centered as padding instead
// (design review flag: avoid disproportionate cell stretching).
const GRID_ROW_MAX = 48;
const GRID_ROW_MIN = 24;

function gridRowHeight(numRows: number): number {
  if (numRows <= 0) { return GRID_ROW_MAX; }
  const gaps = GRID_ROW_GAP * (numRows - 1);
  const raw = Math.floor((GRID_AREA_H - gaps) / numRows);
  return Math.max(GRID_ROW_MIN, Math.min(GRID_ROW_MAX, raw));
}

@Component
export struct SymbolView {
  @StorageLink('symKeyWidthVp') symKeyWidthVp: number = 46;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('frequentSymbols') frequentSymbols: string[] = [];
  @State currentTab: number = 1;
  @State showLicense: boolean = false;

  private h(): InputHandler { return InputHandler.getInstance(); }

  // Snapshot the 🕐 "recent" tab ordering once, when the panel opens -- so it
  // stays stable while the user taps within it (recordSymbolUse no longer
  // re-sorts live). Re-runs each time the panel is reopened.
  aboutToAppear(): void {
    this.h().refreshFrequentSymbols();
  }

  private insert(sym: string): void {
    this.h().commitTopCandidate();
    this.h().insertText(sym);
    this.h().recordSymbolUse(sym);
  }

  // Chunks the user's most-tapped symbols into rows of 8 for the 🕐 tab,
  // falling back to a fixed common-punctuation set until real usage data
  // (persisted via InputHandler.recordSymbolUse) has built up.
  private recentRows(): string[][] {
    const flat = this.frequentSymbols.length > 0 ? this.frequentSymbols : DEFAULT_RECENT_SYMBOLS;
    const rows: string[][] = [];
    for (let i = 0; i < flat.length; i += 8) {
      rows.push(flat.slice(i, i + 8));
    }
    return rows;
  }

  private currentRows(): string[][] {
    return this.currentTab === 0 ? this.recentRows() : SYMBOL_CATEGORIES[this.currentTab];
  }

  build() {
    Column({ space: 0 }) {
      // ── Top tab row ──────────────────────────────────────────
      Row({ space: 4 }) {
        // ← back to kana
        Text('←')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .width(48).height(40)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .backgroundColor(kbTheme(this.isDark).specialBg)
          .borderRadius(20)
          .onClick(() => {
            this.showLicense = false;
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        if (!this.showLicense) {
          // Category tabs
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
            Text(SYM_TABS[i])
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(i === 1 ? 12 : 13)
              .textAlign(TextAlign.Center)
              .width(38).height(32)
              .fontColor(this.currentTab === i ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
              .backgroundColor(this.currentTab === i ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
              .borderRadius(12)
              .onClick(() => {
                this.currentTab = i;
              })
          }, (i: number) => String(i))
        } else {
          Text('ⓘ ライセンス')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).textSecondary)
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
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .lineHeight(20)
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        .width('100%')
        .height(GRID_AREA_H)
        .backgroundColor(kbTheme(this.isDark).panelBg)
      } else {
        // ── Symbol grid: row height fills the fixed grid budget (capped —
        // see gridRowHeight above), extra slack centers as padding so
        // switching tabs never changes the panel's total height. ──
        Column({ space: GRID_ROW_GAP }) {
          ForEach([0, 1, 2, 3, 4, 5, 6], (rowIdx: number) => {
            if (rowIdx < this.currentRows().length) {
              Row({ space: 4 }) {
                ForEach(this.currentRows()[rowIdx], (sym: string) => {
                  Text(sym)
                    .fontFamily(JP_FONT_FAMILY)
                    .fontSize(sym.length > 1 ? 12 : 18)
                    .textAlign(TextAlign.Center)
                    .width(this.symKeyWidthVp)
                    .height(gridRowHeight(this.currentRows().length))
                    .fontColor(kbTheme(this.isDark).textPrimary)
                    .backgroundColor(kbTheme(this.isDark).keyBg)
                    .borderRadius(10)
                    .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
                    .onClick(() => { this.insert(sym); })
                }, (sym: string) => String(this.currentTab) + sym)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
          }, (rowIdx: number) => String(rowIdx))
        }
        .width('100%')
        .height(GRID_AREA_H)
        .justifyContent(FlexAlign.Center)
      }

      // ── Bottom function row ───────────────────────────────────
      Row({ space: 0 }) {
        // あいう — back to kana
        Text('あいう')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13).textAlign(TextAlign.Center)
          .width(68).height(44)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .onClick(() => {
            this.showLicense = false;
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        // Emoji button → emoji panel
        Text('☺')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(17)
          .textAlign(TextAlign.Center)
          .width(46).height(44)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .borderRadius(12)
          .onClick(() => { AppStorage.setOrCreate('keyboardSubMode', 'emoji'); })

        // ⓘ license info toggle
        Text('ⓘ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18).textAlign(TextAlign.Center)
          .width(46).height(44)
          .fontColor(this.showLicense ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
          .backgroundColor(this.showLicense ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
          .borderRadius(12)
          .onClick(() => { this.showLicense = !this.showLicense; })

        // ⌫ backspace
        Text('⌫')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18).textAlign(TextAlign.Center)
          .width(52).height(44)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .backgroundColor(kbTheme(this.isDark).specialBg)
          .borderRadius(14)
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
