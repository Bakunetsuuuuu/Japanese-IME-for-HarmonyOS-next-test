import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';

const EMOJI_TABS: string[] = ['😀', '👋', '🐶', '🍎', '🚗', '⚽', '💡', '❤️'];

const EMOJI_CATEGORIES: string[][][] = [
  // 0: 😀 顔・感情
  [
    ['😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂'],
    ['🙂', '😉', '😊', '😇', '🥰', '😍', '😘', '😗'],
    ['😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭'],
    ['🤔', '🤐', '😐', '😑', '😶', '😏', '😒', '🙄'],
    ['😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🥳'],
    ['😎', '🤓', '🧐', '😕', '🙁', '😮', '😳', '🥺'],
    ['😢', '😭', '😱', '😣', '😞', '😓', '😩', '😫'],
    ['😤', '😡', '😠', '🤬', '😈', '👿', '💀', '👻'],
  ],
  // 1: 👋 人・ジェスチャー
  [
    ['👋', '🤚', '✋', '🖐', '👌', '✌', '🤞', '🤙'],
    ['👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌'],
    ['🤲', '🙏', '💪', '🦾', '☝', '👆', '👇', '👉'],
    ['👦', '👧', '🧒', '👩', '👨', '🧑', '👶', '👼'],
    ['👮', '💂', '🥷', '🦸', '🦹', '🧙', '🧚', '🧛'],
    ['💆', '💇', '🚶', '🧍', '🧎', '🏃', '💃', '🕺'],
    ['😺', '😸', '😹', '😻', '😼', '😽', '🙀', '😿'],
    ['👫', '👬', '👭', '💑', '👨‍👩‍👦', '👨‍👩‍👧', '👪', '🧑‍🤝‍🧑'],
  ],
  // 2: 🐶 動物・自然
  [
    ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼'],
    ['🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔'],
    ['🐧', '🐦', '🦆', '🦅', '🦉', '🦋', '🐛', '🐌'],
    ['🐞', '🐜', '🐢', '🐍', '🦎', '🐳', '🐬', '🦈'],
    ['🐠', '🐡', '🐙', '🦑', '🦐', '🦞', '🦀', '🐊'],
    ['🌸', '🌺', '🌻', '🌹', '🌷', '🌼', '🌿', '🍀'],
    ['🍁', '🍂', '🌲', '🌳', '🌴', '🌵', '🎋', '🎍'],
    ['🌞', '🌝', '🌛', '🌚', '🌕', '🌈', '⛅', '🌊'],
  ],
  // 3: 🍎 食べ物・飲み物
  [
    ['🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓'],
    ['🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆'],
    ['🥑', '🥦', '🥬', '🌽', '🥕', '🍄', '🧅', '🧄'],
    ['🍞', '🥐', '🥖', '🧀', '🥚', '🍳', '🥞', '🧇'],
    ['🍔', '🍟', '🍕', '🌭', '🌮', '🌯', '🥙', '🧆'],
    ['🍣', '🍱', '🍛', '🍲', '🍜', '🍝', '🍤', '🍙'],
    ['🍦', '🍧', '🍨', '🍩', '🍪', '🎂', '🍰', '🧁'],
    ['☕', '🍵', '🧃', '🥤', '🧋', '🍺', '🍷', '🥂'],
  ],
  // 4: 🚗 乗り物・場所
  [
    ['🚗', '🚕', '🚙', '🚌', '🚎', '🏎', '🚓', '🚑'],
    ['🚒', '🚐', '🚚', '🚛', '🚜', '🏍', '🛵', '🚲'],
    ['✈', '🚀', '🛸', '🚁', '⛵', '🚢', '🚂', '🚃'],
    ['🌍', '🗺', '🗻', '🏔', '🏕', '🏖', '🏝', '🏜'],
    ['🏡', '🏢', '🏣', '🏥', '🏦', '🏨', '🗼', '🗽'],
    ['🎡', '🎢', '🎠', '⛩', '🕌', '🕍', '⛪', '🛕'],
    ['🌃', '🌆', '🌇', '🌉', '🌁', '🌄', '🌅', '🌠'],
    ['⛰', '🌋', '🏗', '🏙', '🌐', '🧭', '🚏', '⛽'],
  ],
  // 5: ⚽ スポーツ・活動
  [
    ['⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🎱'],
    ['🏓', '🏸', '🥊', '🏹', '🎣', '🤿', '🎿', '⛷'],
    ['🏂', '🏋', '🤸', '⛹', '🏌', '🏇', '🏊', '🚵'],
    ['🎯', '🎳', '🏆', '🥇', '🥈', '🥉', '🎖', '🏅'],
    ['🎮', '🕹', '🎲', '♟', '🎭', '🎪', '🎨', '🖼'],
    ['🎬', '🎥', '📹', '📷', '🎤', '🎧', '🎵', '🎶'],
    ['🎸', '🎹', '🎺', '🎻', '🥁', '🎷', '🪕', '🎙'],
    ['🎠', '🎡', '🎢', '🎪', '🎫', '🎟', '🎗', '🏮'],
  ],
  // 6: 💡 モノ
  [
    ['💡', '🔦', '🕯', '🔋', '🔌', '💻', '🖥', '📱'],
    ['⌨', '🖱', '🖨', '📠', '📺', '📻', '📷', '📹'],
    ['📚', '📖', '📝', '✏', '🖊', '📌', '📎', '🔑'],
    ['🔓', '🔒', '🔨', '⛏', '🔧', '🔩', '⚙', '🪛'],
    ['💊', '🩺', '💉', '🌡', '🔭', '🔬', '🧪', '🧫'],
    ['⌚', '👓', '🕶', '🥽', '👜', '👝', '🎒', '💼'],
    ['💰', '💳', '📮', '🗑', '🚪', '🛋', '🚽', '🛁'],
    ['🎁', '🎀', '🎊', '🎉', '🎈', '🧨', '✉', '📦'],
  ],
  // 7: ❤️ 記号・ハート
  [
    ['❤', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍'],
    ['🤎', '💖', '💗', '💓', '💞', '💕', '💟', '💔'],
    ['💯', '💢', '💥', '💫', '💦', '💨', '🔥', '✨'],
    ['⭐', '🌟', '⚡', '🌈', '☀', '🌙', '❄', '🌊'],
    ['🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫', '⚪'],
    ['🔺', '🔻', '🔷', '🔶', '🔹', '🔸', '🔲', '🔳'],
    ['✅', '❎', '🆗', '🆕', '🆙', '🆒', '🆓', '🔃'],
    ['🚫', '⛔', '❌', '⭕', '❓', '❗', '‼', '⁉'],
  ],
];

// Grid area budget — matches SymbolView's so switching between the symbol
// and emoji panels never shifts the keyboard's total height.
const GRID_AREA_H = 252;
const GRID_ROW_GAP = 4;
// Bounded dynamic row height (see SymbolView.ets for the full rationale).
// Every emoji category has exactly 8 rows, and the previous fixed 36px row
// height (8*36 + 7*2 = 302px) overflowed the 252px grid area by 50px,
// silently forcing a scroll to reach the bottom row on every tab — this
// formula sizes rows to actually fit instead.
const GRID_ROW_MAX = 48;
const GRID_ROW_MIN = 24;

function gridRowHeight(numRows: number): number {
  if (numRows <= 0) { return GRID_ROW_MAX; }
  const gaps = GRID_ROW_GAP * (numRows - 1);
  const raw = Math.floor((GRID_AREA_H - gaps) / numRows);
  return Math.max(GRID_ROW_MIN, Math.min(GRID_ROW_MAX, raw));
}

@Component
export struct EmojiView {
  @StorageLink('symKeyWidthVp') symKeyWidthVp: number = 46;
  @StorageLink('isDark') isDark: boolean = false;
  @State currentTab: number = 0;

  private h(): InputHandler { return InputHandler.getInstance(); }

  build() {
    Column({ space: 0 }) {
      // ── Tab row ───────────────────────────────────────────────
      Row({ space: 4 }) {
        Text('←')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .width(48).height(40)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .backgroundColor(kbTheme(this.isDark).specialBg)
          .borderRadius(20)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'symbol');
          })

        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
          Text(EMOJI_TABS[i])
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(16)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .textAlign(TextAlign.Center)
            .width(34).height(32)
            .backgroundColor(this.currentTab === i ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
            .borderRadius(12)
            .onClick(() => { this.currentTab = i; })
        }, (i: number) => String(i))
      }
      .width('100%')
      .height(48)
      .padding({ left: 4, right: 4, top: 4 })
      .alignItems(VerticalAlign.Center)

      // ── Emoji grid: row height fills the fixed grid budget (capped, and
      // guaranteed to fit all 8 rows — see gridRowHeight above). ──
      Column({ space: GRID_ROW_GAP }) {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (rowIdx: number) => {
          if (rowIdx < EMOJI_CATEGORIES[this.currentTab].length) {
            Row({ space: 4 }) {
              ForEach(EMOJI_CATEGORIES[this.currentTab][rowIdx], (emoji: string) => {
                Text(emoji)
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(20)
                  .textAlign(TextAlign.Center)
                  .width(this.symKeyWidthVp)
                  .height(gridRowHeight(EMOJI_CATEGORIES[this.currentTab].length))
                  .backgroundColor(kbTheme(this.isDark).keyBg)
                  .borderRadius(10)
                  .shadow({ radius: 2, color: kbTheme(this.isDark).shadowColor, offsetY: 1 })
                  .onClick(() => {
                    this.h().commitTopCandidate();
                    this.h().insertText(emoji);
                  })
              }, (emoji: string) => 'e' + String(this.currentTab) + emoji)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
        }, (rowIdx: number) => String(rowIdx))
      }
      .width('100%')
      .height(GRID_AREA_H)
      .justifyContent(FlexAlign.Center)

      // ── Bottom row ────────────────────────────────────────────
      Row({ space: 0 }) {
        Text('あいう')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13).textAlign(TextAlign.Center)
          .width(68).height(44)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        Text('←記')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13).textAlign(TextAlign.Center)
          .width(60).height(44)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .borderRadius(12)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'symbol');
          })

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
