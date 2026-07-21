import { UserDictStore } from '../ime/UserDictStore';
import { UserPosStore } from '../ime/UserPosStore';
import type { UserPosEntry } from '../ime/ConjugationEngine';
import { AppMaintenance } from '../ime/AppMaintenance';
import { router, promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { common, abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';

const CONSENT_STORE: string = 'shunti_consent';
const CONSENT_KEY: string = 'privacy_agreed';
const CARD_RADIUS = 16;
const DELETE_RED = '#E5484D';

// A top-level Record<string,string> object literal with actual entries
// doesn't compile under ArkTS's stricter object-literal typing (unlike a
// class-member initializer, or an empty {} -- see ConjugationEngine.ets's
// GODAN_BUILDERS for the same issue with function values); a Map sidesteps it.
const POS_LABELS: Map<string, string> = new Map<string, string>([
  ['verb', '動詞'], ['adjective', '形容詞'], ['person', '人名'], ['place', '地名'],
]);

interface DictRow {
  yomi: string;
  word: string;
  posLabel: string;
}

// User-dictionary list screen (design_handoff_ime_redesign/README_dictionary.md
// "1. 一覧画面"). Registration/editing moved to its own page
// (DictionaryEditPage.ets, "2. 追加・編集画面") reached via the header's ＋
// button or tapping a row -- this used to be a single combined screen with
// an inline add-only form and no way to edit an existing entry's text.
// Each row's 品詞 (part-of-speech) subtitle comes from UserPosStore -- see
// DictionaryEditPage's 品詞 picker and ConjugationEngine.ets for how it
// drives real conjugation/segmentation behaviour, not just a display tag.
@Entry
@Component
struct Index {
  @State dict: Record<string, string[]> = {};
  @State posMap: Record<string, UserPosEntry> = {};
  @State rows: DictRow[] = [];
  @State searchQuery: string = '';
  // First-launch privacy consent gate. true = block UI until the user agrees.
  @State showConsent: boolean = false;
  // Repair sheet (footer "修復" link): recover from a corrupt-state crash
  // without reinstalling. confirmFullReset gates the destructive option
  // behind a second tap.
  @State showRepair: boolean = false;
  @State confirmFullReset: boolean = false;
  @State repairBusy: boolean = false;
  // Set by EntryAbility.applyColorMode (OS color mode only -- no manual
  // override, see git history if that's ever wanted again).
  @StorageLink('isDark') isDark: boolean = false;

  // Set by EntryAbility (onCreate for a cold start, onNewWant for a
  // re-launch into an already-running instance -- see its own comment) when
  // the keyboard's settings panel asks to open a URL (e.g. GitHub) in the
  // in-app browser. @Watch fires on both the initial bind and later changes,
  // so this covers a re-launch without needing a page-visibility callback.
  @StorageLink('pendingWebViewUrl') @Watch('onPendingWebViewUrlChanged') pendingWebViewUrl: string = '';
  @StorageLink('pendingWebViewTitle') pendingWebViewTitle: string = '';

  // Hidden access to the developer dictionary: 7 quick taps on the title.
  private titleTapCount: number = 0;
  private titleTapLast: number = 0;

  private onPendingWebViewUrlChanged(): void {
    if (this.pendingWebViewUrl.length === 0) { return; }
    const url = this.pendingWebViewUrl;
    const title = this.pendingWebViewTitle;
    AppStorage.setOrCreate('pendingWebViewUrl', '');
    router.pushUrl({ url: 'pages/WebViewPage', params: { url, title } });
  }

  aboutToAppear(): void {
    this.reload();
    this.checkConsent();
    this.onPendingWebViewUrlChanged();
  }

  // Refresh the list when coming back from DictionaryEditPage (add/edit/
  // delete all happen there now, not inline on this page).
  onPageShow(): void {
    this.reload();
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
      .then((result: PermissionRequestResult) => {
        console.info('shuntiIME clipboard permission result', JSON.stringify(result.authResults));
      })
      .catch((err: Error) => console.error('shuntiIME requestPermissionsFromUser error', JSON.stringify(err)));
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
    Promise.all([
      UserDictStore.load(getContext(this), true),
      UserPosStore.load(getContext(this), true),
    ]).then((results: [Record<string, string[]>, Record<string, UserPosEntry>]) => {
      this.dict = results[0];
      this.posMap = results[1];
      this.rebuildRows();
    }).catch((err: Error) => {
      // The main app is the recovery surface (it hosts the repair option),
      // so it must render even if the stores are unreadable -- show an
      // empty list rather than letting an unhandled rejection take it down.
      console.error('shuntiIME Index.reload failed', JSON.stringify(err));
      this.dict = {};
      this.posMap = {};
      this.rebuildRows();
    });
  }

  private rebuildRows(): void {
    const list: DictRow[] = [];
    const keys = Object.keys(this.dict).sort();
    for (const yomi of keys) {
      for (const word of this.dict[yomi]) {
        const entry = UserPosStore.get(this.posMap, yomi, word);
        const posLabel = entry ? (POS_LABELS.get(entry.pos) ?? '') : '';
        list.push({ yomi: yomi, word: word, posLabel: posLabel });
      }
    }
    this.rows = list;
  }

  private visibleRows(): DictRow[] {
    const q = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) { return this.rows; }
    return this.rows.filter((r: DictRow) => r.word.toLowerCase().includes(q) || r.yomi.toLowerCase().includes(q));
  }

  private openEditor(row?: DictRow): void {
    router.pushUrl({
      url: 'pages/DictionaryEditPage',
      params: { yomi: row?.yomi ?? '', word: row?.word ?? '' },
    });
  }

  build() {
    Stack() {
      Column() {
        // ── Header: symmetric 56px gutters so the title stays centered ──
        Row() {
          Row().width(56)
          Text('ユーザー辞書')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.onTitleTap(); })
          Row() {
            Text('＋')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(17)
              .textAlign(TextAlign.Center)
              .width(28).height(28)
              .fontColor(kbTheme(this.isDark).accent)
              .backgroundColor(kbTheme(this.isDark).funcBg)
              .borderRadius(14)
              .onClick(() => { this.openEditor(); })
          }
          .width(56)
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

        // ── Search bar ──────────────────────────────────────────
        TextInput({ placeholder: '単語・読みで検索', text: $$this.searchQuery })
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .height(38)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .placeholderColor(kbTheme(this.isDark).textSecondary)
          .borderRadius(11)
          .margin({ left: 16, right: 16, top: 10, bottom: 10 })

        // ── 登録済み一覧 ─────────────────────────────────────
        if (this.visibleRows().length === 0) {
          Column() {
            Text(this.rows.length === 0
              ? '登録された単語がありません\n右上の＋から追加できます'
              : '一致する単語が見つかりません')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(13)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 64 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.visibleRows(), (row: DictRow, index: number) => {
                Column() {
                  Row() {
                    Column({ space: 2 }) {
                      Text(row.word)
                        .fontFamily(JP_FONT_FAMILY)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(kbTheme(this.isDark).textPrimary)
                      Text(row.posLabel.length > 0 ? `${row.yomi} ・ ${row.posLabel}` : row.yomi)
                        .fontFamily(JP_FONT_FAMILY)
                        .fontSize(12)
                        .fontColor(kbTheme(this.isDark).textSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text('›')
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(15)
                      .fontColor(kbTheme(this.isDark).textSecondary)
                  }
                  .width('100%')
                  .padding({ top: 13, bottom: 13 })
                  .onClick(() => { this.openEditor(row); })

                  if (index < this.visibleRows().length - 1) {
                    Divider().color(kbTheme(this.isDark).divider)
                  }
                }
              }, (row: DictRow) => row.yomi + '' + row.word)
            }
            .width('100%')
            .backgroundColor(kbTheme(this.isDark).cardBg)
            .borderRadius(CARD_RADIUS)
            .padding({ left: 14, right: 14 })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
          .align(Alignment.Top)
        }

        // Footer
        Row() {
          Text('プライバシーポリシー')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).accent)
            .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicy' }); })
          Text('  ·  ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('v1.5.0')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('  ·  ')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
          Text('修復')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).accent)
            .onClick(() => { this.confirmFullReset = false; this.showRepair = true; })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 12, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).panelBg)

      if (this.showConsent) {
        this.ConsentOverlay()
      }
      if (this.showRepair) {
        this.RepairOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  private doResetLearning(): void {
    if (this.repairBusy) { return; }
    this.repairBusy = true;
    AppMaintenance.resetLearning(getContext(this)).then(() => {
      this.repairBusy = false;
      this.showRepair = false;
      promptAction.showToast({ message: '変換学習・入力履歴をリセットしました' });
    });
  }

  private doResetAll(): void {
    if (this.repairBusy) { return; }
    this.repairBusy = true;
    AppMaintenance.resetAll(getContext(this)).then(() => {
      // Reflect the wipe in the list immediately.
      this.dict = {};
      this.posMap = {};
      this.rows = [];
      this.repairBusy = false;
      this.showRepair = false;
      this.confirmFullReset = false;
      promptAction.showToast({ message: 'アプリのデータを初期化しました。キーボードを一度閉じて開き直してください' });
    });
  }

  @Builder RepairOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text('困ったときの修復')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)

        Text('アプリやキーボードの動作がおかしいとき、保存データをリセットして回復できます。再インストールせずに直せる場合があります。')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .lineHeight(22)
          .width('100%')

        // ── Safe reset: keeps registered words ──
        Column({ space: 3 }) {
          Text('変換学習・入力履歴をリセット')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .width('100%')
          Text('登録した単語は残ります')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(12)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .width('100%')
        }
        .width('100%')
        .backgroundColor(kbTheme(this.isDark).funcBg)
        .borderRadius(10)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => { this.doResetLearning(); })

        Divider().color(kbTheme(this.isDark).divider)

        // ── Full reset: destructive, second-tap gated ──
        if (!this.confirmFullReset) {
          Text('アプリのデータをすべて初期化…')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(DELETE_RED)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 4 })
            .onClick(() => { this.confirmFullReset = true; })
        } else {
          Text('登録単語・設定を含むすべての保存データを削除します。この操作は取り消せません。')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .lineHeight(20)
            .width('100%')
          Button('すべて削除して初期化する')
            .fontFamily(JP_FONT_FAMILY)
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor(DELETE_RED)
            .onClick(() => { this.doResetAll(); })
        }

        Text('閉じる')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .padding({ top: 2 })
          .onClick(() => { this.showRepair = false; this.confirmFullReset = false; })
      }
      .width('86%')
      .padding(24)
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
  }

  @Builder ConsentOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text('プライバシーポリシーへの同意')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)

        Text('shunti Japanese IME をご利用いただく前に、プライバシーポリシーをお読みください。\n\n' +
             '・入力内容・変換履歴はすべて端末内でのみ処理されます\n' +
             '・外部サーバーへの送信は一切行いません\n' +
             '・分析ツールや広告 SDK は使用していません')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .lineHeight(22)
          .width('100%')

        Text('プライバシーポリシー全文を読む')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).accent)
          .decoration({ type: TextDecorationType.Underline, color: kbTheme(this.isDark).accent })
          .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicy' }); })

        Button('同意して始める')
          .fontFamily(JP_FONT_FAMILY)
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor(kbTheme(this.isDark).accent)
          .onClick(() => { this.acceptConsent(); })

        Text('同意しない（アプリを終了）')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .onClick(() => { this.declineConsent(); })
      }
      .width('86%')
      .padding(24)
      .backgroundColor(kbTheme(this.isDark).cardBg)
      .borderRadius(CARD_RADIUS)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
  }
}
