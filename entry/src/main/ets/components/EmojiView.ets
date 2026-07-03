import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';

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

@Component
export struct EmojiView {
  @StorageLink('symKeyWidthVp') symKeyWidthVp: number = 46;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('themeVariant') themeVariant: string = 'original';
  @State currentTab: number = 0;


  private h(): InputHandler { return InputHandler.getInstance(); }

  build() {
    Column({ space: 0 }) {
      // ── Tab row ───────────────────────────────────────────────
      Row({ space: 2 }) {
        Text('←')
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .width(44).height(40)
          .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
          .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
          .borderRadius(20)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'symbol');
          })

        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
          Text(EMOJI_TABS[i])
            .fontSize(16)
            .textAlign(TextAlign.Center)
            .width(34).height(32)
            .backgroundColor(this.currentTab === i ? '#6C757D' : kbTheme(this.isDark, this.themeVariant).funcKeyBg)
            .borderRadius(8)
            .onClick(() => { this.currentTab = i; })
        }, (i: number) => String(i))
      }
      .width('100%')
      .height(48)
      .padding({ left: 4, right: 4, top: 4 })
      .alignItems(VerticalAlign.Center)

      // ── Emoji grid (scrollable) ───────────────────────────────
      Scroll() {
        Column({ space: 2 }) {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (rowIdx: number) => {
            if (rowIdx < EMOJI_CATEGORIES[this.currentTab].length) {
              Row({ space: 2 }) {
                ForEach(EMOJI_CATEGORIES[this.currentTab][rowIdx], (emoji: string) => {
                  Text(emoji)
                    .fontSize(22)
                    .textAlign(TextAlign.Center)
                    .width(this.symKeyWidthVp)
                    .height(36)
                    .backgroundColor(kbTheme(this.isDark, this.themeVariant).keyBg)
                    .borderRadius(6)
                    .shadow({ radius: 1, color: kbTheme(this.isDark, this.themeVariant).shadowColor, offsetY: 1 })
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
        .padding({ top: 2 })
      }
      .width('100%')
      .height(252)

      // ── Bottom row ────────────────────────────────────────────
      Row({ space: 0 }) {
        Text('あいう')
          .fontSize(13).textAlign(TextAlign.Center)
          .width(68).height(44)
          .fontColor(kbTheme(this.isDark, this.themeVariant).subText)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        Text('←記')
          .fontSize(13).textAlign(TextAlign.Center)
          .width(60).height(44)
          .fontColor(kbTheme(this.isDark, this.themeVariant).subText)
          .backgroundColor(kbTheme(this.isDark, this.themeVariant).funcKeyBg)
          .borderRadius(8)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'symbol');
          })

        Text('⌫')
          .fontSize(18).textAlign(TextAlign.Center)
          .width(52).height(44)
          .fontColor(kbTheme(this.isDark, this.themeVariant).onAccentText)
          .backgroundColor(kbTheme(this.isDark, this.themeVariant).specialKeyBg)
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
    .backgroundColor(kbTheme(this.isDark, this.themeVariant).panelBg)
  }
}
