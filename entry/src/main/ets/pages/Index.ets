import { router } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { common, abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { JP_FONT_FAMILY, registerJpFont } from '../components/JpFont';
import { kbTheme } from '../components/Theme';

const CONSENT_STORE: string = 'shunti_consent';
const CONSENT_KEY: string = 'privacy_agreed';
const CARD_RADIUS = 16;

// 本体アプリの画面。
//
// かつてはここにユーザー辞書の一覧・登録、削除した候補、修復、入力ログが
// あったが、すべてキーボード側 (設定パネル) に移してこの画面からは撤去した。
//
// 理由: 入力方式の拡張は本体アプリと別プロセスかつ別サンドボックスで動いており、
// 両者はデータを一切共有できない。実機で確認したところ、本体アプリが書いた
// shunti_userdict は拡張から 0 件にしか見えず、逆に拡張が保存に成功した
// shunti_settings は本体アプリから存在しない。つまりこの画面で辞書を登録しても
// 変換には一生効かず、消した候補も入力ログも常に空にしか見えなかった。
// プラットフォーム側の共有手段 (dataGroupIds + getGroupDir) は応用市場での
// 発行が前提で、AGC に登録導線が無く使えない。
// 動かない画面を残すと「登録したのに効かない」を再生産するだけなので消した。
//
// この画面に残っている仕事:
//   1. 初回のプライバシー同意
//   2. READ_PASTEBOARD の要求 ── user_grant 権限は画面を持つ UIAbility から
//      しか要求できず、拡張自身では出せない。この画面が存在する主目的。
//   3. キーボードからの「URLを開く」「共有する」の受け口 (EntryAbility 経由)
//   4. プライバシーポリシーとライセンス（キーボードからは開けない）
@Entry
@Component
struct Index {
  // First-launch privacy consent gate. true = block UI until the user agrees.
  @State showConsent: boolean = false;
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

  // Set by EntryAbility when the keyboard's 開発を応援 section asks to share a
  // donation URL (KeyboardController.shareUrl). Raises the system share sheet
  // so the link can be forwarded to a device that has a payment method
  // registered, instead of opening a card form in the in-app browser.
  @StorageLink('pendingShareUrl') @Watch('onPendingShareUrlChanged') pendingShareUrl: string = '';

  private onPendingWebViewUrlChanged(): void {
    if (this.pendingWebViewUrl.length === 0) { return; }
    const url = this.pendingWebViewUrl;
    const title = this.pendingWebViewTitle;
    AppStorage.setOrCreate('pendingWebViewUrl', '');
    router.pushUrl({ url: 'pages/WebViewPage', params: { url, title } });
  }

  private onPendingShareUrlChanged(): void {
    if (this.pendingShareUrl.length === 0) { return; }
    const url = this.pendingShareUrl;
    AppStorage.setOrCreate('pendingShareUrl', '');
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      content: url,
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    controller.show(getContext(this) as common.UIAbilityContext, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL,
    }).catch((err: Error) => console.error('shuntiIME share failed', JSON.stringify(err)));
  }

  aboutToAppear(): void {
    // Must happen here, not in EntryAbility -- see registerJpFont's comment.
    // aboutToAppear runs before this page's first build, so the very first
    // Text already measures with the Japanese font.
    registerJpFont(this.getUIContext());
    this.checkConsent();
    this.onPendingWebViewUrlChanged();
    this.onPendingShareUrlChanged();
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
  // prompt for it, so this app's own screen is the only place to ask.
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

  build() {
    Stack() {
      Column() {
        Row() {
          Text($r('app.string.home_title'))
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(kbTheme(this.isDark).textPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

        Scroll() {
          Column({ space: 14 }) {
            // 辞書も設定もキーボード内にある。ここで探させないよう明示する。
            Column({ space: 8 }) {
              Text($r('app.string.home_where_title'))
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .width('100%')
              Text($r('app.string.home_where_body'))
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(13)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .lineHeight(21)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(kbTheme(this.isDark).cardBg)
            .borderRadius(CARD_RADIUS)

            Column({ space: 8 }) {
              Text($r('app.string.home_enable_title'))
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(kbTheme(this.isDark).textPrimary)
                .width('100%')
              Text($r('app.string.home_enable_body'))
                .fontFamily(JP_FONT_FAMILY)
                .fontSize(13)
                .fontColor(kbTheme(this.isDark).textSecondary)
                .lineHeight(21)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(kbTheme(this.isDark).cardBg)
            .borderRadius(CARD_RADIUS)

            Text($r('app.string.privacy_policy'))
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(kbTheme(this.isDark).textPrimary)
              .width('100%')
              .padding(16)
              .backgroundColor(kbTheme(this.isDark).cardBg)
              .borderRadius(CARD_RADIUS)
              .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicy' }); })

            Text($r('app.string.license_title'))
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(kbTheme(this.isDark).textPrimary)
              .width('100%')
              .padding(16)
              .backgroundColor(kbTheme(this.isDark).cardBg)
              .borderRadius(CARD_RADIUS)
              .onClick(() => { router.pushUrl({ url: 'pages/License' }); })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        Text('v1.5.2')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).panelBg)

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
        Text($r('app.string.consent_title'))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)

        Text($r('app.string.consent_body'))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .lineHeight(22)
          .width('100%')

        Text($r('app.string.consent_read_full'))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(kbTheme(this.isDark).accent)
          .decoration({ type: TextDecorationType.Underline, color: kbTheme(this.isDark).accent })
          .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicy' }); })

        Button($r('app.string.consent_accept'))
          .fontFamily(JP_FONT_FAMILY)
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor(kbTheme(this.isDark).accent)
          .onClick(() => { this.acceptConsent(); })

        Text($r('app.string.consent_decline'))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
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
