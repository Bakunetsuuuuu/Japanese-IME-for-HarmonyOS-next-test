import { UserDictStore } from '../ime/UserDictStore';
import { promptAction, router } from '@kit.ArkUI';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';

const CARD_RADIUS = 16;
const DELETE_RED = '#E5484D';

interface EditParams {
  yomi?: string;
  word?: string;
}

// Add/edit screen for a single user-dictionary entry (design_handoff_ime_redesign/
// README_dictionary.md "2. 追加・編集画面"). Reached from Index.ets's ＋
// button (new entry, both params empty) or tapping a row (existing entry,
// both params filled). No 品詞 field -- see Index.ets's own comment for why.
@Entry
@Component
struct DictionaryEditPage {
  @StorageLink('isDark') isDark: boolean = false;
  @State editWord: string = '';
  @State editYomi: string = '';
  private origWord: string = '';
  private origYomi: string = '';

  private get isExisting(): boolean {
    return this.origYomi.length > 0 && this.origWord.length > 0;
  }

  private get canSave(): boolean {
    return this.editWord.trim().length > 0 && this.editYomi.trim().length > 0;
  }

  aboutToAppear(): void {
    const params = router.getParams() as EditParams | undefined;
    this.origYomi = params?.yomi ?? '';
    this.origWord = params?.word ?? '';
    this.editYomi = this.origYomi;
    this.editWord = this.origWord;
  }

  private isHiragana(s: string): boolean {
    // U+3041–U+3094 covers ぁ…ゔ (incl. ん), U+30FC is the long-vowel mark ー.
    return /^[ぁ-ゔー]+$/.test(s);
  }

  private saveEntry(): void {
    const yomi = this.editYomi.trim();
    const word = this.editWord.trim();
    if (yomi.length === 0 || word.length === 0) {
      promptAction.showToast({ message: 'よみと単語を入力してください' });
      return;
    }
    if (!this.isHiragana(yomi)) {
      promptAction.showToast({ message: 'よみはひらがなで入力してください' });
      return;
    }
    UserDictStore.load(getContext(this), true).then((d: Record<string, string[]>) => {
      let dict = d;
      // Editing an existing entry: drop the old reading→word pair first
      // (a no-op if only the word text changed and the reading is the
      // same, since add() below would just re-add the same pair) so a
      // changed reading doesn't leave a stale copy behind under the old one.
      if (this.isExisting) {
        dict = UserDictStore.remove(dict, this.origYomi, this.origWord);
      }
      dict = UserDictStore.add(dict, yomi, word);
      UserDictStore.save(getContext(this), dict).then(() => {
        promptAction.showToast({ message: `「${word}」を保存しました` });
        router.back();
      });
    });
  }

  private deleteEntry(): void {
    UserDictStore.load(getContext(this), true).then((d: Record<string, string[]>) => {
      const dict = UserDictStore.remove(d, this.origYomi, this.origWord);
      UserDictStore.save(getContext(this), dict).then(() => {
        router.back();
      });
    });
  }

  build() {
    Column() {
      // ── Header: symmetric 56px gutters so the title stays centered ──
      Row() {
        Row() {
          Text('‹ 戻る')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(kbTheme(this.isDark).accent)
            .onClick(() => { router.back(); })
        }
        .width(56)
        .justifyContent(FlexAlign.Start)

        Text(this.isExisting ? '単語を編集' : '単語を追加')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row() {
          Text('保存')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(kbTheme(this.isDark).accent)
            .opacity(this.canSave ? 1 : 0.4)
            .onClick(() => { if (this.canSave) { this.saveEntry(); } })
        }
        .width(56)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

      Scroll() {
        Column() {
          Text('単語情報')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(0.6)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .padding({ left: 4, bottom: 8 })
            .width('100%')

          Column() {
            Column({ space: 4 }) {
              Text('単語')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(11)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .width('100%')
              TextInput({ placeholder: '例：会議', text: this.editWord })
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .placeholderColor(kbTheme(this.isDark).textSecondary)
                .backgroundColor(Color.Transparent)
                .padding(0)
                .onChange((v: string) => { this.editWord = v; })
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 12, bottom: 12 })
            .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

            Column({ space: 4 }) {
              Text('読み（ひらがな）')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(11)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .width('100%')
              TextInput({ placeholder: '例：かいぎ', text: this.editYomi })
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .placeholderColor(kbTheme(this.isDark).textSecondary)
                .backgroundColor(Color.Transparent)
                .padding(0)
                .onChange((v: string) => { this.editYomi = v; })
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 12, bottom: 12 })
          }
          .backgroundColor(kbTheme(this.isDark).cardBg)
          .borderRadius(CARD_RADIUS)
          .padding({ left: 14, right: 14 })
          .margin({ bottom: 22 })

          if (this.isExisting) {
            Text('この単語を削除')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(DELETE_RED)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 14 })
              .onClick(() => { this.deleteEntry(); })
          }
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
