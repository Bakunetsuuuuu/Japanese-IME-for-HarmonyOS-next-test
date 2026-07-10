import { UserDictStore } from '../ime/UserDictStore';
import { promptAction, router } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import display from '@ohos.display';

const CONSENT_STORE: string = 'shunti_consent';
const CONSENT_KEY: string = 'privacy_agreed';

interface DictRow {
  yomi: string;
  word: string;
}

@Entry
@Component
struct Index {
  @State dict: Record<string, string[]> = {};
  @State rows: DictRow[] = [];
  @State yomiInput: string = '';
  @State wordInput: string = '';
  // First-launch privacy consent gate. true = block UI until the user agrees.
  @State showConsent: boolean = false;
  @State isDark: boolean = false;

  // Hidden access to the developer dictionary: 7 quick taps on the title.
  private titleTapCount: number = 0;
  private titleTapLast: number = 0;

  aboutToAppear(): void {
    this.reload();
    this.checkConsent();
    try {
      const dis = display.getDefaultDisplaySync();
      // display.ColorMode: COLOR_MODE_LIGHT=0, COLOR_MODE_DARK=1
      this.isDark = (dis as ESObject)['colorMode'] === 1;
    } catch (_e) {
      this.isDark = false;
    }
  }

  private checkConsent(): void {
    dataPreferences.getPreferences(getContext(this), CONSENT_STORE)
      .then((prefs: dataPreferences.Preferences) => {
        prefs.get(CONSENT_KEY, false).then((agreed: dataPreferences.ValueType) => {
          this.showConsent = (agreed !== true);
          if (agreed === true) { this.requestClipboardPermission(); }
        });
      })
      .catch((_e: Error) => { this.showConsent = true; });
  }

  private acceptConsent(): void {
    dataPreferences.getPreferences(getContext(this), CONSENT_STORE)
      .then((prefs: dataPreferences.Preferences) => {
        prefs.put(CONSENT_KEY, true).then(() => {
          prefs.flush();
          this.showConsent = false;
          this.requestClipboardPermission();
        });
      })
      .catch((_e: Error) => { this.showConsent = false; });
  }

  // The keyboard extension reads the system pasteboard to show a paste
  // suggestion in the candidate bar (see KeyboardController.refreshClipboardPreview).
  // ohos.permission.READ_PASTEBOARD is user_grant and can only be requested
  // from a UIAbility with a window — the InputMethodExtAbility itself can't
  // prompt for it, so this app's own settings screen is the only place to ask.
  // Safe to call unconditionally: it resolves immediately if already granted.
  private requestClipboardPermission(): void {
    const permissions: Array<Permissions> = ['ohos.permission.READ_PASTEBOARD'];
    abilityAccessCtrl.createAtManager()
      .requestPermissionsFromUser(getContext(this) as common.UIAbilityContext, permissions)
      .catch((_e: Error) => {});
  }

  private declineConsent(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  private onTitleTap(): void {
    const now = Date.now();
    // Reset the run if taps are more than 1.5s apart.
    this.titleTapCount = (now - this.titleTapLast <= 1500) ? this.titleTapCount + 1 : 1;
    this.titleTapLast = now;
    if (this.titleTapCount >= 7) {
      this.titleTapCount = 0;
      router.pushUrl({ url: 'pages/DevDict' });
    }
  }

  private reload(): void {
    UserDictStore.load(getContext(this), true).then((d: Record<string, string[]>) => {
      this.dict = d;
      this.rebuildRows();
    });
  }

  private rebuildRows(): void {
    const list: DictRow[] = [];
    const keys = Object.keys(this.dict).sort();
    for (const yomi of keys) {
      for (const word of this.dict[yomi]) {
        list.push({ yomi: yomi, word: word });
      }
    }
    this.rows = list;
  }

  private isHiragana(s: string): boolean {
    // U+3041–U+3094 covers ぁ…ゔ (incl. ん), U+30FC is the long-vowel mark ー.
    return /^[ぁ-ゔー]+$/.test(s);
  }

  private addEntry(): void {
    const yomi = this.yomiInput.trim();
    const word = this.wordInput.trim();
    if (yomi.length === 0 || word.length === 0) {
      promptAction.showToast({ message: 'よみと単語を入力してください' });
      return;
    }
    if (!this.isHiragana(yomi)) {
      promptAction.showToast({ message: 'よみはひらがなで入力してください' });
      return;
    }
    this.dict = UserDictStore.add(this.dict, yomi, word);
    UserDictStore.save(getContext(this), this.dict).then(() => {
      this.rebuildRows();
      this.yomiInput = '';
      this.wordInput = '';
      promptAction.showToast({ message: `「${word}」を登録しました` });
    });
  }

  private removeEntry(row: DictRow): void {
    this.dict = UserDictStore.remove(this.dict, row.yomi, row.word);
    UserDictStore.save(getContext(this), this.dict).then(() => {
      this.rebuildRows();
    });
  }

  build() {
    Stack() {
    Column() {
      // ── Header ──────────────────────────────────────────────
      Row() {
        Text('ユーザー辞書')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .onClick(() => { this.onTitleTap(); })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16 })
      .backgroundColor('#4A90E2')

      // ── Registration form ───────────────────────────────────
      Column({ space: 10 }) {
        TextInput({ placeholder: 'よみ（ひらがな）', text: this.yomiInput })
          .onChange((v: string) => { this.yomiInput = v; })
          .height(44)
          .backgroundColor(this.isDark ? '#2A2A2A' : '#FFFFFF')
          .fontColor(this.isDark ? '#E0E0E0' : Color.Black)
          .borderRadius(8)

        TextInput({ placeholder: '単語', text: this.wordInput })
          .onChange((v: string) => { this.wordInput = v; })
          .height(44)
          .backgroundColor(this.isDark ? '#2A2A2A' : '#FFFFFF')
          .fontColor(this.isDark ? '#E0E0E0' : Color.Black)
          .borderRadius(8)

        Button('登録')
          .width('100%')
          .height(44)
          .fontSize(16)
          .backgroundColor('#4A90E2')
          .onClick(() => { this.addEntry(); })
      }
      .width('100%')
      .padding(16)

      Divider().color(this.isDark ? '#333333' : '#E0E0E0')

      // ── Registered list ─────────────────────────────────────
      Row() {
        Text(`登録済み（${this.rows.length}件）`)
          .fontSize(14)
          .fontColor('#888888')
      }
      .width('100%')
      .padding({ left: 16, top: 12, bottom: 4 })

      if (this.rows.length === 0) {
        Column() {
          Text('まだ登録がありません')
            .fontSize(15)
            .fontColor('#AAAAAA')
        }
        .width('100%')
        .padding({ top: 40 })
      } else {
        List({ space: 1 }) {
          ForEach(this.rows, (row: DictRow) => {
            ListItem() {
              Row() {
                Column({ space: 2 }) {
                  Text(row.word)
                    .fontSize(17)
                    .fontColor(this.isDark ? '#F0F0F0' : Color.Black)
                  Text(row.yomi)
                    .fontSize(13)
                    .fontColor('#999999')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button('削除')
                  .fontSize(14)
                  .height(34)
                  .backgroundColor(this.isDark ? '#3A3A3A' : '#F0F0F0')
                  .fontColor('#D9534F')
                  .onClick(() => { this.removeEntry(row); })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .backgroundColor(this.isDark ? '#252525' : '#FFFFFF')
            }
          }, (row: DictRow) => row.yomi + '' + row.word)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: this.isDark ? '#333333' : '#EEEEEE' })
      }
      // Footer
      Row() {
        Text('プライバシーポリシー')
          .fontSize(12)
          .fontColor('#4A90E2')
          .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicy' }); })
        Text('  ·  ')
          .fontSize(12)
          .fontColor('#BBBBBB')
        Text('v1.1.0')
          .fontSize(12)
          .fontColor('#BBBBBB')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDark ? '#121212' : '#F5F5F5')

      if (this.showConsent) {
        this.ConsentOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder ConsentOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text('プライバシーポリシーへの同意')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDark ? '#F0F0F0' : '#222222')

        Text('shunti Japanese IME をご利用いただく前に、プライバシーポリシーをお読みください。\n\n' +
             '・入力内容・変換履歴はすべて端末内でのみ処理されます\n' +
             '・外部サーバーへの送信は一切行いません\n' +
             '・分析ツールや広告 SDK は使用していません')
          .fontSize(14)
          .fontColor(this.isDark ? '#AAAAAA' : '#555555')
          .lineHeight(22)
          .width('100%')

        Text('プライバシーポリシー全文を読む')
          .fontSize(14)
          .fontColor('#4A90E2')
          .decoration({ type: TextDecorationType.Underline, color: '#4A90E2' })
          .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicy' }); })

        Button('同意して始める')
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor('#4A90E2')
          .onClick(() => { this.acceptConsent(); })

        Text('同意しない（アプリを終了）')
          .fontSize(13)
          .fontColor('#999999')
          .onClick(() => { this.declineConsent(); })
      }
      .width('86%')
      .padding(24)
      .backgroundColor(this.isDark ? '#252525' : '#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
  }
}
