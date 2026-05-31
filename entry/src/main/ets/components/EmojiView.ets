import { InputHandler } from '../ime/KeyboardController';

const EMOJI_TABS: string[] = ['😀', '👋', '🐶', '🍎', '❤️'];

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
  // 4: ❤️ 記号・ハート
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
          .fontColor(Color.White)
          .backgroundColor('#ADB5BD')
          .borderRadius(20)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'symbol');
          })

        ForEach([0, 1, 2, 3, 4], (i: number) => {
          Text(EMOJI_TABS[i])
            .fontSize(16)
            .textAlign(TextAlign.Center)
            .width(44).height(32)
            .backgroundColor(this.currentTab === i ? '#6C757D' : '#C8CDD4')
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
                    .backgroundColor('#FFFFFF')
                    .borderRadius(6)
                    .shadow({ radius: 1, color: '#33000000', offsetY: 1 })
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
          .fontColor('#444444')
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'kana');
          })

        Text('←記')
          .fontSize(13).textAlign(TextAlign.Center)
          .width(60).height(44)
          .fontColor('#444444')
          .backgroundColor('#C8CDD4')
          .borderRadius(8)
          .onClick(() => {
            AppStorage.setOrCreate('keyboardSubMode', 'symbol');
          })

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
