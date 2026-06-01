import { UserDictStore } from '../ime/UserDictStore';
import { promptAction, router } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';

interface DictRow {
  yomi: string;
  word: string;
}

// Hidden developer dictionary. Reached only via the 7-tap easter egg on the
// user-dictionary header, then a password gate. Entries are an editing
// workspace persisted on-device; "JSONエクスポート" copies them to the
// clipboard so the developer can paste them into rawfile/global_dict.json and
// ship to all users in the next patch.
const GLOBAL_STORE: string = 'shunti_globaldict';

// Password is matched by hash so the plaintext is not in the repo.
// To change it, recompute devHash(newPassword) and replace the constant below.
const PASSWORD_HASH: number = 371391235;

function devHash(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
  }
  return h;
}

@Entry
@Component
struct DevDict {
  @State unlocked: boolean = false;
  @State passwordInput: string = '';
  @State dict: Record<string, string[]> = {};
  @State rows: DictRow[] = [];
  @State yomiInput: string = '';
  @State wordInput: string = '';

  private tryUnlock(): void {
    if (devHash(this.passwordInput) === PASSWORD_HASH) {
      this.unlocked = true;
      this.passwordInput = '';
      this.reload();
    } else {
      this.passwordInput = '';
      promptAction.showToast({ message: 'パスワードが違います' });
    }
  }

  private reload(): void {
    UserDictStore.load(getContext(this), true, GLOBAL_STORE).then((d: Record<string, string[]>) => {
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
    UserDictStore.save(getContext(this), this.dict, GLOBAL_STORE).then(() => {
      this.rebuildRows();
      this.yomiInput = '';
      this.wordInput = '';
      promptAction.showToast({ message: `「${word}」を登録しました` });
    });
  }

  private removeEntry(row: DictRow): void {
    this.dict = UserDictStore.remove(this.dict, row.yomi, row.word);
    UserDictStore.save(getContext(this), this.dict, GLOBAL_STORE).then(() => {
      this.rebuildRows();
    });
  }

  private exportJson(): void {
    const json = JSON.stringify(this.dict);
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: 'JSONをコピーしました（global_dict.jsonに貼付）' });
    }).catch(() => {
      promptAction.showToast({ message: 'コピーに失敗しました' });
    });
  }

  build() {
    Column() {
      // ── Header ──────────────────────────────────────────────
      Row() {
        Text('← 戻る')
          .fontSize(15)
          .fontColor(Color.White)
          .onClick(() => { router.back(); })
        Text('開発者辞書（非公開）')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16 })
      .backgroundColor('#5A3E8E')

      if (!this.unlocked) {
        // ── Password gate ─────────────────────────────────────
        Column({ space: 14 }) {
          Text('開発者用パスワードを入力')
            .fontSize(15)
            .fontColor('#666666')
          TextInput({ placeholder: 'パスワード', text: this.passwordInput })
            .type(InputType.Password)
            .onChange((v: string) => { this.passwordInput = v; })
            .onSubmit(() => { this.tryUnlock(); })
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          Button('解錠')
            .width('100%')
            .height(44)
            .backgroundColor('#5A3E8E')
            .onClick(() => { this.tryUnlock(); })
        }
        .width('100%')
        .padding(24)
        .margin({ top: 40 })
      } else {
        // ── Registration form ───────────────────────────────────
        Column({ space: 10 }) {
          TextInput({ placeholder: 'よみ（ひらがな）', text: this.yomiInput })
            .onChange((v: string) => { this.yomiInput = v; })
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)

          TextInput({ placeholder: '単語', text: this.wordInput })
            .onChange((v: string) => { this.wordInput = v; })
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)

          Row({ space: 10 }) {
            Button('登録')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#5A3E8E')
              .onClick(() => { this.addEntry(); })
            Button('JSONエクスポート')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .backgroundColor('#8266B3')
              .onClick(() => { this.exportJson(); })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)

        Divider().color('#E0E0E0')

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
                      .fontColor(Color.Black)
                    Text(row.yomi)
                      .fontSize(13)
                      .fontColor('#999999')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Button('削除')
                    .fontSize(14)
                    .height(34)
                    .backgroundColor('#F0F0F0')
                    .fontColor('#D9534F')
                    .onClick(() => { this.removeEntry(row); })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor('#FFFFFF')
              }
            }, (row: DictRow) => row.yomi + '' + row.word)
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 1, color: '#EEEEEE' })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
