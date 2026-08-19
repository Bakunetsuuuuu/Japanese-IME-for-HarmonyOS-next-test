import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { promptAction } from '@kit.ArkUI';
import { JP_FONT_FAMILY } from './JpFont';
import { DEBUG_INPUT_LOG } from '../ime/InputLog'; // [DEBUG-LOG]

// Segmented-control / card metrics (design tokens: settings cards 16px,
// segmented-control track 20px / inner pill 20px).
const CARD_RADIUS = 16;
const TRACK_RADIUS = 20;
const PILL_RADIUS = 20;
// 全消去に必要な連打回数。誤操作で到達しない回数にしてある。
const RESET_ALL_TAPS = 5;

// Dedicated settings sub-mode, entered via keyboardSubMode === 'settings'
// (the ⚙ button in KeyboardPage). Takes the full IME panel the same way
// SymbolView/EmojiView do (header row + Scroll content) rather than
// floating a narrow card over the keyboard -- the previous floating-card
// version was too cramped once enough menu items accumulated.
@Component
export struct SettingsBar {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  @StorageLink('clipboardHistory') clipboardHistory: string[] = [];
  @StorageLink('oneHandedMode') oneHandedMode: boolean = false;
  @StorageLink('oneHandedSide') oneHandedSide: string = 'right';
  @StorageLink('kanaKeyboardLayout') kanaKeyboardLayout: string = 'QWERTY';
  @StorageLink('alphabetKeyboardLayout') alphabetKeyboardLayout: string = 'QWERTY';
  @StorageLink('conversionEngine') conversionEngine: string = 'mozc';
  @StorageLink('numericPadEnabled') numericPadEnabled: boolean = false;
  @StorageLink('hapticEnabled') hapticEnabled: boolean = false;
  // キーボードのライト／ダーク。'system' = 端末に合わせる。
  @StorageLink('themeMode') themeMode: string = 'system';
  @StorageLink('keyChromeEnabled') keyChromeEnabled: boolean = true;
  // この端末では拡張プロセスからの振動が許可されていない、と分かった状態。
  @StorageLink('hapticUnavailable') hapticUnavailable: boolean = false;
  @State showHistory: boolean = false;
  @State showDict: boolean = false;
  // ユーザー辞書の中の下位画面。'' = 入口のメニュー / 'suggest' = 登録候補 /
  // 'registered' = 登録済み。どちらも件数が多くなるので画面を分けている。
  @State dictSub: string = '';
  // ユーザー辞書はキーボード側で完結させる (本体アプリの辞書画面から登録しても
  // 拡張には届かない ── InputHandler.registerUserWord のコメント参照)。
  // "よみ\t表記\t回数" / "よみ\t表記" の文字列配列。構造体配列だと @StorageLink の
  // 更新検知が効きにくいため。
  @StorageLink('dictSuggestions') dictSuggestions: string[] = [];
  @StorageLink('dictRegistered') dictRegistered: string[] = [];
  // 候補の長押しで削除した語 ("よみ	表記")。
  @StorageLink('suppressedRows') suppressedRows: string[] = [];
  // 自由入力の欄の中身と、いまどちらの欄に打鍵が入るか。
  @StorageLink('dictEditYomi') dictEditYomi: string = '';
  @StorageLink('dictEditWord') dictEditWord: string = '';
  @StorageLink('dictCaptureTarget') dictCaptureTarget: string = '';
  // 学習リセットは2回押しで確認する。
  @State confirmResetLearning: boolean = false;
  // 全消去は RESET_ALL_TAPS 回の連打を要求する。手が止まると0に戻す。
  @State resetAllTaps: number = 0;
  private resetAllTimer: number = -1;
  @State showLog: boolean = false; // [DEBUG-LOG]
  @StorageLink('inputLogSummary') inputLogSummary: string = ''; // [DEBUG-LOG]
  @StorageLink('inputLogRows') inputLogRows: string[] = []; // [DEBUG-LOG]

  // Re-read the system clipboard whenever the settings panel opens, so the
  // クリップボード履歴 count/list is current -- a copy made in the host app
  // while the keyboard stayed up otherwise wasn't reflected until the keyboard
  // was closed and reopened (AppGallery reviewer feedback).
  aboutToAppear(): void {
    InputHandler.getInstance().refreshClipboard();
  }

  private close(): void {
    // 自由入力を掴んだままパネルを閉じると、以降ホストアプリに文字が入らなく
    // なる。抜ける経路では必ず解除する。
    InputHandler.getInstance().stopCapture();
    AppStorage.setOrCreate('keyboardSubMode', 'kana');
    this.showHistory = false;
    this.showDict = false;
    this.dictSub = '';
  }

  // Opening the クリップボード履歴 view re-reads the clipboard first, so the
  // most recent copy is always shown without closing/reopening the keyboard.
  private openHistory(): void {
    InputHandler.getInstance().refreshClipboard();
    this.showHistory = true;
  }

  // 開くたびに最新を配り直す。登録候補は打つたびに増えるので、
  // 開いた瞬間の内容で作らないと古いままになる。
  private openDict(): void {
    InputHandler.getInstance().publishDictRows();
    this.dictSub = '';
    this.showDict = true;
  }

  private openLog(): void { // [DEBUG-LOG]
    InputHandler.getInstance().publishInputLogRows();
    this.showLog = true;
  }

  build() {
    Column({ space: 0 }) {
      // ── Header: symmetric 56px gutters so the title stays centered
      // regardless of which side has a control (design tokens). ──
      Row() {
        Row() {
          if (this.showHistory || this.showDict || this.showLog) {
            Text('‹ 戻る')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(kbTheme(this.isDark).accent)
              .onClick(() => {
                InputHandler.getInstance().stopCapture();
                // 辞書の下位画面にいるときは、まず辞書の入口へ戻る。
                if (this.showDict && this.dictSub.length > 0) {
                  this.dictSub = '';
                  return;
                }
                this.showHistory = false;
                this.showDict = false;
                this.showLog = false; // [DEBUG-LOG]
              })
          }
        }
        .width(56)
        .justifyContent(FlexAlign.Start)

        Text(this.showHistory
          ? 'クリップボード履歴'
          : (this.showDict
            ? (this.dictSub === 'suggest' ? '登録候補'
              : (this.dictSub === 'registered' ? '登録済み'
                : (this.dictSub === 'suppressed' ? '削除した候補' : 'ユーザー辞書')))
            : (this.showLog ? '入力ログ' : '設定')))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row() {
          if (this.showHistory) {
            Text('削除')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .onClick(() => {
                InputHandler.getInstance().clearClipboardHistory();
              })
          } else if (!this.showDict && !this.showLog) {
            Text('✕')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .width(28).height(28)
              .textAlign(TextAlign.Center)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .backgroundColor(kbTheme(this.isDark).funcBg)
              .borderRadius(8)
              .onClick(() => { this.close(); })
          }
        }
        .width(56)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

      Divider().color(kbTheme(this.isDark).divider)

      // ── Content (scrolls if it doesn't fit the panel height) ──
      Scroll() {
        Column() {
          if (this.showHistory) {
            this.HistoryView()
          } else if (this.showDict && this.dictSub === 'suggest') {
            this.DictSuggestView()
          } else if (this.showDict && this.dictSub === 'registered') {
            this.DictRegisteredView()
          } else if (this.showDict && this.dictSub === 'suppressed') {
            this.SuppressedView()
          } else if (this.showDict) {
            this.DictView()
          } else if (this.showLog) {
            this.LogView() // [DEBUG-LOG]
          } else {
            this.MenuView()
          }
        }
        .padding(16)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }

  @Builder SectionLabel(text: string) {
    Text(text)
      .fontFamily(JP_FONT_FAMILY)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .letterSpacing(0.6)
      .fontColor(kbTheme(this.isDark).textSecondary)
      .padding({ left: 4, bottom: 8 })
      .width('100%')
  }

  // Segmented-control options are written inline (not as a shared @Builder
  // taking an "active" boolean parameter) — ArkUI's fine-grained update
  // didn't reliably re-invoke a parameterized child @Builder when only the
  // underlying @StorageLink changed (the toggle's highlighted state stuck
  // until the whole panel was torn down and rebuilt, i.e. closed/reopened).
  // Each option below reads its @StorageLink field directly so the
  // dependency is unambiguous.

  @Builder MenuView() {
    // Clipboard history is one of the most-reached-for items, so it leads the
    // settings panel rather than sitting near the bottom of その他.
    this.SectionLabel('クリップボード')
    Column() {
      Row() {
        Text('クリップボード履歴')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Row({ space: 6 }) {
          Text(String(this.clipboardHistory.length))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('›')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => { this.openHistory(); })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('辞書')
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('ユーザー辞書')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .width('100%')
          Text('打った語をここから登録できます')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .width('100%')
        }
        .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => { this.openDict(); })

      // [DEBUG-LOG] リリース前に削除する。収集した内容は本体アプリからは
      // 読めない (サンドボックスが別) ので、書いた側であるここから見る。
      // DEBUG_INPUT_LOG が false のときは入口ごと消える (InputLog.ets の
      // 「とりあえず無効化だけしたい場合」がそう振る舞うと書いてあるのに、
      // ここにガードが無く項目だけ残っていた)。
      if (DEBUG_INPUT_LOG) { // [DEBUG-LOG]
        Divider().color(kbTheme(this.isDark).divider) // [DEBUG-LOG]
        Row() { // [DEBUG-LOG]
          Text('入力ログ(デバッグ)') // [DEBUG-LOG]
            .fontFamily(JP_FONT_FAMILY) // [DEBUG-LOG]
            .fontSize(14) // [DEBUG-LOG]
            .fontColor(kbTheme(this.isDark).textPrimary) // [DEBUG-LOG]
            .layoutWeight(1) // [DEBUG-LOG]
          Text('›') // [DEBUG-LOG]
            .fontFamily(JP_FONT_FAMILY) // [DEBUG-LOG]
            .fontSize(14) // [DEBUG-LOG]
            .fontColor(kbTheme(this.isDark).textSecondary) // [DEBUG-LOG]
        } // [DEBUG-LOG]
        .width('100%') // [DEBUG-LOG]
        .padding({ top: 14, bottom: 14 }) // [DEBUG-LOG]
        .onClick(() => { this.openLog(); }) // [DEBUG-LOG]
      } // [DEBUG-LOG]
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('入力')
    Column() {
      // Switches immediately (same process as the keyboard itself) — more
      // reliable than the main app's copy of this same toggle, which has to
      // round-trip through shared preferences for the extension to pick it up.
      Row() {
        Text('かな入力レイアウト')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)

        Row({ space: 2 }) {
          Text('QWERTY')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.kanaKeyboardLayout === 'QWERTY' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.kanaKeyboardLayout === 'QWERTY' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setKanaKeyboardLayout('QWERTY'); })

          Text('フリック')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.kanaKeyboardLayout === 'FLICK' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.kanaKeyboardLayout === 'FLICK' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setKanaKeyboardLayout('FLICK'); })
        }
        .backgroundColor(kbTheme(this.isDark).funcBg)
        .borderRadius(TRACK_RADIUS)
        .padding(2)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })

      Row() {
        Text('アルファベット入力レイアウト')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)

        Row({ space: 2 }) {
          Text('QWERTY')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.alphabetKeyboardLayout === 'QWERTY' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.alphabetKeyboardLayout === 'QWERTY' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setAlphabetKeyboardLayout('QWERTY'); })

          Text('フリック')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.alphabetKeyboardLayout === 'FLICK' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.alphabetKeyboardLayout === 'FLICK' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setAlphabetKeyboardLayout('FLICK'); })
        }
        .backgroundColor(kbTheme(this.isDark).funcBg)
        .borderRadius(TRACK_RADIUS)
        .padding(2)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color(kbTheme(this.isDark).divider)

      // 打鍵の手応え。既定はオフ (勝手に振動すると煩わしいため)。
      // オンにした瞬間に一度鳴らして、効きが分かるようにしている。
      Row() {
        Column({ space: 2 }) {
          Text('キー入力時の振動')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text(this.hapticUnavailable
            ? 'この端末では利用できません（OSがキーボードからの振動を許可していません）'
            : 'キーを押したときに短く振動します')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.hapticEnabled })
          .width(44)
          .height(26)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((isOn: boolean) => {
            InputHandler.getInstance().setHapticEnabled(isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color(kbTheme(this.isDark).divider)

      // Off by default -- see SettingsStore's numericPadEnabled comment. The
      // 「あA」キーは常に日本語⇔アルファベットを切り替えるが、これがオンだと
      // アルファベット状態からもう一度押すことで数字パッドまで進むようになる
      // (InputHandler.cycleInputMode参照)。取消キーは常時表示のため文言不要。
      Row() {
        Column({ space: 2 }) {
          Text('数字パッド')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text('オンにすると「あA」キーで日本語→アルファベット→数字と切り替わります')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.numericPadEnabled })
          .width(44)
          .height(26)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((isOn: boolean) => {
            InputHandler.getInstance().setNumericPadEnabled(isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('片手モード')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.oneHandedMode })
          .width(44)
          .height(26)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((isOn: boolean) => {
            InputHandler.getInstance().setOneHandedMode(isOn, this.oneHandedSide);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: this.oneHandedMode ? 8 : 12 })

      if (this.oneHandedMode) {
        Row({ space: 8 }) {
          Text('左寄せ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.oneHandedSide === 'left' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
            .fontColor(this.oneHandedSide === 'left' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setOneHandedMode(true, 'left'); })

          Text('右寄せ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.oneHandedSide === 'right' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
            .fontColor(this.oneHandedSide === 'right' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setOneHandedMode(true, 'right'); })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: 14 })
      }

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('変換エンジン')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)

        Row({ space: 2 }) {
          Text('独自辞書')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.conversionEngine === 'custom' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.conversionEngine === 'custom' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setConversionEngine('custom'); })

          Text('統計データ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.conversionEngine === 'mozc' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.conversionEngine === 'mozc' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setConversionEngine('mozc'); })
        }
        .backgroundColor(kbTheme(this.isDark).funcBg)
        .borderRadius(TRACK_RADIUS)
        .padding(2)
      }
      .width('100%')
      .padding({ top: 12, bottom: 4 })
      // hybrid supersedes this 2-way choice entirely while active -- see the
      // beta toggle below. Dimmed + non-interactive rather than hidden, so
      // switching back off is discoverable (just turn the beta toggle off).
      .opacity(this.conversionEngine === 'hybrid' ? 0.4 : 1)
      .enabled(this.conversionEngine !== 'hybrid')

      Text(this.conversionEngine === 'mozc'
        ? '高性能だが比較的鈍重（推奨）'
        : this.conversionEngine === 'hybrid' ? '' : '軽量だが発展途上')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(10)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .padding({ bottom: this.conversionEngine === 'hybrid' ? 4 : 12 })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Column({ space: 2 }) {
          Text('ハイブリッド（β）')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text('独自辞書と統計データの融合を試験中。有効にすると上の選択は一時的に無効になります')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.conversionEngine === 'hybrid' })
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((isOn: boolean) => {
            // 切ったときの戻り先は 'mozc'。hybrid は mozc の上に乗る位置づけ
            // なので、切っただけで独自辞書まで落ちるのは選んでいない変更になる。
            InputHandler.getInstance().setConversionEngine(isOn ? 'hybrid' : 'mozc');
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 12 })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('テーマ')
    Column() {
      Row() {
        Text('外観')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)

        Row({ space: 2 }) {
          Text('自動')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.themeMode === 'system' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.themeMode === 'system' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setThemeMode('system'); })

          Text('ライト')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.themeMode === 'light' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.themeMode === 'light' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setThemeMode('light'); })

          Text('ダーク')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(PILL_RADIUS)
            .backgroundColor(this.themeMode === 'dark' ? kbTheme(this.isDark).accent : 'transparent')
            .fontColor(this.themeMode === 'dark' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textSecondary)
            .onClick(() => { InputHandler.getInstance().setThemeMode('dark'); })
        }
        .backgroundColor(kbTheme(this.isDark).funcBg)
        .borderRadius(TRACK_RADIUS)
        .padding(2)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Column({ space: 2 }) {
          Text('キーの外枠')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text('キーの背景色を有効にする')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.keyChromeEnabled })
          .width(44)
          .height(26)
          .selectedColor(kbTheme(this.isDark).accent)
          .onChange((isOn: boolean) => {
            InputHandler.getInstance().setKeyChromeEnabled(isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    // 本体アプリの「修復」はアプリ側のストアしか消せず、キーボードの学習・設定・
    // 辞書には届かない (別サンドボックス)。復旧手段はここに置く。
    this.SectionLabel('修復')
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(this.confirmResetLearning ? 'もう一度押すとリセットします' : '学習をリセット')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .width('100%')
          Text('変換の学習・次単語予測・記号の履歴を消します')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => {
        // 1回目は確認、2回目で実行。
        if (!this.confirmResetLearning) {
          this.confirmResetLearning = true;
          return;
        }
        this.confirmResetLearning = false;
        InputHandler.getInstance().resetLearningData();
        promptAction.showToast({ message: '学習をリセットしました' });
      })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Column({ space: 2 }) {
          Text(this.resetAllTaps > 0
            ? `あと${RESET_ALL_TAPS - this.resetAllTaps}回押すと全消去します`
            : 'すべてリセット')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).deleteRed)
            .width('100%')
          Text(`${RESET_ALL_TAPS}回連続で押すと実行。学習に加えユーザー辞書・削除した候補・設定も消えます`)
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      // 全消去は取り返しがつかないので、意図しないと成立しない操作にする。
      // 2回押しでは続けて押せば起きうるし、長押しも持ち替えの拍子に成立しうる。
      // 5回連打を要求し、残り回数を出して「今これを消そうとしている」と分かる
      // ようにする。手が止まれば (2.5秒) カウントは0に戻る。
      .onClick(() => {
        clearTimeout(this.resetAllTimer);
        this.resetAllTaps += 1;
        if (this.resetAllTaps >= RESET_ALL_TAPS) {
          this.resetAllTaps = 0;
          InputHandler.getInstance().resetAllData();
          promptAction.showToast({ message: 'すべてリセットしました' });
          return;
        }
        this.resetAllTimer = setTimeout(() => { this.resetAllTaps = 0; }, 2500);
      })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('その他')
    Column() {
      Row() {
        Text('アプリを開く')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => {
        InputHandler.getInstance().openMainApp();
        this.close();
      })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('レビューを書く')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => {
        const opened = InputHandler.getInstance().openAppGalleryReview();
        if (!opened) {
          promptAction.showToast({ message: 'まだAppGalleryに公開されていません' });
        }
        this.close();
      })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('開発を支援 / ソースコード（GitHub）')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => {
        InputHandler.getInstance().openGithubRepo();
        this.close();
      })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
    .margin({ bottom: 22 })

    this.SectionLabel('開発を応援')
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('Buy Me a Coffee')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text('リンクを共有 → 決済できる端末で開いて応援（缶コーヒー1杯から）')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        InputHandler.getInstance().openBuyMeACoffeeLink();
        this.close();
      })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Column({ space: 2 }) {
          Text('GitHub Sponsors')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text('リンクを共有 → GitHubで月額/単発の支援（要アカウント）')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        InputHandler.getInstance().openGithubSponsorsLink();
        this.close();
      })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
  }

  @Builder HistoryView() {
    if (this.clipboardHistory.length === 0) {
      Text('履歴がありません')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 48, bottom: 48 })
    } else {
      List() {
        ForEach(this.clipboardHistory, (item: string, index: number) => {
          ListItem() {
            Text(item)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(14)
              .fontColor(kbTheme(this.isDark).textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ top: 14, bottom: 14 })
              .onClick(() => {
                InputHandler.getInstance().pasteFromHistory(index);
                this.close();
              })
          }
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 14, right: 14 })
      .divider({ strokeWidth: 1, color: kbTheme(this.isDark).divider })
    }
  }

  // ユーザー辞書。上段が「登録候補」(打った語のうち辞書に無いものを
  // UnknownWordLearner が拾ったもの)、下段が「登録済み」。
  // 読みと表記を手で打ち直させないので、パネル内に文字入力欄が要らない。
  // ユーザー辞書の入口。「登録候補」と「登録済み」はどちらも件数が多くなるので、
  // 1画面に積まず、それぞれ別画面に開く。
  @Builder DictView() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('任意の語を登録')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .width('100%')
          Text('この画面を閉じて、キーボードの上に入力欄を出します')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .width('100%')
        }
        .layoutWeight(1)
        Text('›')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => {
        this.showDict = false;
        InputHandler.getInstance().beginDictEdit();
      })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('登録候補')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Row({ space: 6 }) {
          Text(String(this.dictSuggestions.length))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('›')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => { this.dictSub = 'suggest'; })

      Divider().color(kbTheme(this.isDark).divider)

      Row() {
        Text('登録済み')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Row({ space: 6 }) {
          Text(String(this.dictRegistered.length))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('›')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => { this.dictSub = 'registered'; })

      Divider().color(kbTheme(this.isDark).divider)

      // 候補の長押し削除で消した語。復元もここで行う。
      Row() {
        Text('削除した候補')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
        Row({ space: 6 }) {
          Text(String(this.suppressedRows.length))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('›')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .onClick(() => {
        InputHandler.getInstance().publishSuppressedRows();
        this.dictSub = 'suppressed';
      })
    }
    .backgroundColor(kbTheme(this.isDark).cardBg)
    .borderRadius(CARD_RADIUS)
    .padding({ left: 14, right: 14 })
  }

  // 登録候補 (打った語のうち辞書に無いものを UnknownWordLearner が拾ったもの)。
  @Builder DictSuggestView() {
    // 見出しと操作を横に並べる箇所では SectionLabel を使わない。
    // あれは width('100%') なので、Row に入れると右の操作を画面外へ押し出す。
    Row() {
      Text('打った語のうち辞書に無いもの')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .letterSpacing(0.6)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .padding({ left: 4 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.dictSuggestions.length > 0) {
        Text('すべて消去')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontColor(kbTheme(this.isDark).deleteRed)
          .padding({ left: 8 })
          .onClick(() => { InputHandler.getInstance().clearUnknownWords(); })
      }
    }
    .width('100%')
    .padding({ bottom: 8 })
    .alignItems(VerticalAlign.Center)

    if (this.dictSuggestions.length === 0) {
      Text('候補はありません\n変換できない語を打って確定すると、ここに出ます')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 20 })
        .margin({ bottom: 22 })
    } else {
      Column() {
        ForEach(this.dictSuggestions, (row: string) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(row.split('\t')[1])
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .width('100%')
              Text(`${row.split('\t')[0]}   組み立て ${row.split('\t')[2]}回`)
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(10)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .width('100%')
            }
            .layoutWeight(1)
            Text('登録')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(kbTheme(this.isDark).onAccent)
              .backgroundColor(kbTheme(this.isDark).accent)
              .borderRadius(8)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .onClick(() => {
                const p = row.split('\t');
                InputHandler.getInstance().registerUserWord(p[0], p[1]);
                promptAction.showToast({ message: `${p[1]} を登録しました` });
              })
            Text('✕')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .width(28).height(28)
              .textAlign(TextAlign.Center)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .onClick(() => {
                const p = row.split('\t');
                InputHandler.getInstance().dismissUnknownWord(p[0], p[1]);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }, (row: string) => row)
      }
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 14, right: 14 })
    }
  }

  // 候補の長押しで削除した語。ここから元に戻せる。
  @Builder SuppressedView() {
    Row() {
      Text('変換候補から消した語')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .letterSpacing(0.6)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .padding({ left: 4 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.suppressedRows.length > 0) {
        Text('すべて戻す')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontColor(kbTheme(this.isDark).accent)
          .padding({ left: 8 })
          .onClick(() => { InputHandler.getInstance().clearAllSuppressed(); })
      }
    }
    .width('100%')
    .padding({ bottom: 8 })
    .alignItems(VerticalAlign.Center)

    if (this.suppressedRows.length === 0) {
      Text('ありません\n候補を長押しして削除すると、ここに出ます')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 20 })
    } else {
      Column() {
        ForEach(this.suppressedRows, (row: string) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(row.split('\t')[1])
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(16)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .width('100%')
              Text(row.split('\t')[0])
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(10)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .width('100%')
            }
            .layoutWeight(1)
            Text('戻す')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(kbTheme(this.isDark).onAccent)
              .backgroundColor(kbTheme(this.isDark).accent)
              .borderRadius(8)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .onClick(() => {
                const p = row.split('\t');
                InputHandler.getInstance().restoreSuppressedWord(p[0], p[1]);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }, (row: string) => row)
      }
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 14, right: 14 })
    }
  }

  // 登録済みのユーザー辞書。
  @Builder DictRegisteredView() {
    if (this.dictRegistered.length === 0) {
      Text('まだありません')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 20 })
    } else {
      Column() {
        ForEach(this.dictRegistered, (row: string) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(row.split('\t')[1])
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(16)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .width('100%')
              Text(row.split('\t')[0])
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(10)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .width('100%')
            }
            .layoutWeight(1)
            Text('削除')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .fontColor(kbTheme(this.isDark).deleteRed)
              .padding({ left: 10, right: 4, top: 6, bottom: 6 })
              .onClick(() => {
                const p = row.split('\t');
                InputHandler.getInstance().removeUserWord(p[0], p[1]);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }, (row: string) => row)
      }
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 14, right: 14 })
    }
  }

  // [DEBUG-LOG] 収集した入力ログの閲覧。リリース前にこの Builder ごと削除する。
  @Builder LogView() {
    Row({ space: 8 }) {
      Text(this.inputLogSummary.length > 0 ? this.inputLogSummary : '—')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .layoutWeight(1)
      Text('コピー')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).accent)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          InputHandler.getInstance().exportInputLog();
          promptAction.showToast({ message: 'クリップボードにコピーしました' });
        })
      Text('消去')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).deleteRed)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => { InputHandler.getInstance().clearInputLog(); })
    }
    .width('100%')
    .padding({ bottom: 10 })

    if (this.inputLogRows.length === 0) {
      Text('記録がありません')
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(12)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 32, bottom: 32 })
    } else {
      Column() {
        ForEach(this.inputLogRows, (row: string, index: number) => {
          Text(row.split('\t').join('  '))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(10)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ top: 6, bottom: 6 })
        }, (row: string, index: number) => `${index}-${row}`)
      }
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 12, right: 12 })
    }
  }
}
