import { UserDictStore } from '../ime/UserDictStore';
import { UserPosStore } from '../ime/UserPosStore';
import type { UserPosEntry } from '../ime/ConjugationEngine';
import { isVerbEnding } from '../ime/ConjugationEngine';
import { promptAction, router } from '@kit.ArkUI';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';

const CARD_RADIUS = 16;
const DELETE_RED = '#E5484D';

interface EditParams {
  yomi?: string;
  word?: string;
}

interface PosOption {
  key: 'noun' | 'verb' | 'adjective' | 'person' | 'place';
  label: string;
}

const POS_OPTIONS: PosOption[] = [
  { key: 'noun', label: '名詞' },
  { key: 'verb', label: '動詞' },
  { key: 'adjective', label: '形容詞' },
  { key: 'person', label: '人名' },
  { key: 'place', label: '地名' },
];

// Add/edit screen for a single user-dictionary entry (design_handoff_ime_redesign/
// README_dictionary.md "2. 追加・編集画面"). Reached from Index.ets's ＋
// button (new entry, both params empty) or tapping a row (existing entry,
// both params filled). The 品詞 picker below drives ConjugationEngine's
// conjugation/classing (see UserPosStore.ets, KeyboardController.reloadUserDict) --
// 名詞 is the implicit default and needs no extra input; 動詞/形容詞 generate
// conjugated forms; 人名/地名 just tag the reading's connection-matrix class.
@Entry
@Component
struct DictionaryEditPage {
  @StorageLink('isDark') isDark: boolean = false;
  @State editWord: string = '';
  @State editYomi: string = '';
  @State pos: 'noun' | 'verb' | 'adjective' | 'person' | 'place' = 'noun';
  // Only asked for a verb whose reading ends in る -- godan-る (帰る) and
  // ichidan (食べる) both end in る, so ConjugationEngine can't tell them
  // apart from spelling alone (see its detectGodanRow comment).
  @State verbGroup: 'ichidan' | 'godan' | undefined = undefined;
  private origWord: string = '';
  private origYomi: string = '';

  private get isExisting(): boolean {
    return this.origYomi.length > 0 && this.origWord.length > 0;
  }

  private get canSave(): boolean {
    return this.editWord.trim().length > 0 && this.editYomi.trim().length > 0;
  }

  private get yomiEndsInRu(): boolean {
    return this.editYomi.trim().endsWith('る');
  }

  private get showVerbGroupPicker(): boolean {
    return this.pos === 'verb' && this.yomiEndsInRu;
  }

  aboutToAppear(): void {
    const params = router.getParams() as EditParams | undefined;
    this.origYomi = params?.yomi ?? '';
    this.origWord = params?.word ?? '';
    this.editYomi = this.origYomi;
    this.editWord = this.origWord;
    if (this.isExisting) {
      UserPosStore.load(getContext(this)).then((posMap: Record<string, UserPosEntry>) => {
        const entry = UserPosStore.get(posMap, this.origYomi, this.origWord);
        if (entry) {
          this.pos = entry.pos;
          this.verbGroup = entry.group;
        }
      });
    }
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
    if (yomi.length < 2 && (this.pos === 'verb' || this.pos === 'adjective')) {
      promptAction.showToast({ message: 'よみが短すぎます' });
      return;
    }
    if (this.pos === 'verb') {
      const last = yomi.charAt(yomi.length - 1);
      if (!isVerbEnding(last)) {
        promptAction.showToast({ message: '動詞のよみは「う」段（る/く/す等）で終わる必要があります' });
        return;
      }
      if (last === 'る' && this.verbGroup === undefined) {
        promptAction.showToast({ message: '五段活用か一段活用かを選んでください' });
        return;
      }
    }
    if (this.pos === 'adjective' && !yomi.endsWith('い')) {
      promptAction.showToast({ message: '形容詞のよみは「い」で終わる必要があります' });
      return;
    }
    const entry: UserPosEntry = {
      pos: this.pos,
      group: (this.pos === 'verb' && yomi.endsWith('る')) ? this.verbGroup : undefined,
    };
    Promise.all([
      UserDictStore.load(getContext(this), true),
      UserPosStore.load(getContext(this), true),
    ]).then((results: [Record<string, string[]>, Record<string, UserPosEntry>]) => {
      let dict = results[0];
      let posMap = results[1];
      // Editing an existing entry: drop the old reading→word pair first
      // (a no-op if only the word text changed and the reading is the
      // same, since add() below would just re-add the same pair) so a
      // changed reading doesn't leave a stale copy behind under the old one.
      if (this.isExisting) {
        dict = UserDictStore.remove(dict, this.origYomi, this.origWord);
        posMap = UserPosStore.remove(posMap, this.origYomi, this.origWord);
      }
      dict = UserDictStore.add(dict, yomi, word);
      posMap = UserPosStore.set(posMap, yomi, word, entry);
      Promise.all([
        UserDictStore.save(getContext(this), dict),
        UserPosStore.save(getContext(this), posMap),
      ]).then(() => {
        promptAction.showToast({ message: `「${word}」を保存しました` });
        router.back();
      });
    });
  }

  private deleteEntry(): void {
    Promise.all([
      UserDictStore.load(getContext(this), true),
      UserPosStore.load(getContext(this), true),
    ]).then((results: [Record<string, string[]>, Record<string, UserPosEntry>]) => {
      const dict = UserDictStore.remove(results[0], this.origYomi, this.origWord);
      const posMap = UserPosStore.remove(results[1], this.origYomi, this.origWord);
      Promise.all([
        UserDictStore.save(getContext(this), dict),
        UserPosStore.save(getContext(this), posMap),
      ]).then(() => {
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
              TextInput({ placeholder: '例：会議', text: $$this.editWord })
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .placeholderColor(kbTheme(this.isDark).textSecondary)
                .backgroundColor(Color.Transparent)
                .padding(0)
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
              TextInput({ placeholder: '例：かいぎ', text: $$this.editYomi })
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .placeholderColor(kbTheme(this.isDark).textSecondary)
                .backgroundColor(Color.Transparent)
                .padding(0)
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 12, bottom: 12 })
          }
          .backgroundColor(kbTheme(this.isDark).cardBg)
          .borderRadius(CARD_RADIUS)
          .padding({ left: 14, right: 14 })
          .margin({ bottom: 22 })

          Text('品詞')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(0.6)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .padding({ left: 4, bottom: 8 })
            .width('100%')

          Column({ space: 10 }) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(POS_OPTIONS, (opt: PosOption) => {
                Text(opt.label)
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(13)
                  .fontWeight(this.pos === opt.key ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.pos === opt.key ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                  .backgroundColor(this.pos === opt.key ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
                  .borderRadius(16)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.pos = opt.key;
                    if (opt.key !== 'verb') { this.verbGroup = undefined; }
                  })
              }, (opt: PosOption) => opt.key)
            }
            .width('100%')

            if (this.showVerbGroupPicker) {
              Row() {
                Text('一段（食べる型）')
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(13)
                  .fontWeight(this.verbGroup === 'ichidan' ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.verbGroup === 'ichidan' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                  .backgroundColor(this.verbGroup === 'ichidan' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .padding({ top: 9, bottom: 9 })
                  .borderRadius({ topLeft: 10, bottomLeft: 10 })
                  .onClick(() => { this.verbGroup = 'ichidan'; })

                Text('五段（帰る型）')
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(13)
                  .fontWeight(this.verbGroup === 'godan' ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.verbGroup === 'godan' ? kbTheme(this.isDark).onAccent : kbTheme(this.isDark).textPrimary)
                  .backgroundColor(this.verbGroup === 'godan' ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .padding({ top: 9, bottom: 9 })
                  .borderRadius({ topRight: 10, bottomRight: 10 })
                  .onClick(() => { this.verbGroup = 'godan'; })
              }
              .width('100%')

              Text('「〜る」で終わる読みは活用の種類を判別できないため選択してください')
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(11)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .width('100%')
            }
          }
          .width('100%')
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
