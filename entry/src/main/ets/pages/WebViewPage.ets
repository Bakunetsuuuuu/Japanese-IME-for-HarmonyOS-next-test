import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';

interface WebViewParams {
  url?: string;
  title?: string;
}

// Generic in-app browser page, launched via router.pushUrl({ url: 'pages/WebViewPage',
// params: { url, title } }). Used so links (e.g. the GitHub repo from the
// keyboard's settings panel) open inside the app's own window instead of
// handing off to the system "choose a browser" chooser -- HarmonyOS's Web
// component (ArkWeb) is a system-provided Chromium-based webview, no
// third-party browser dependency needed.
@Entry
@Component
struct WebViewPage {
  // Set by EntryAbility.applyColorMode (OS color mode only). Only affects
  // this page's own header/background chrome -- the loaded website's own
  // content styles itself (ArkWeb, like any browser, respects the page's own
  // prefers-color-scheme handling, which is unrelated).
  @StorageLink('isDark') isDark: boolean = false;
  @State pageTitle: string = '';
  @State canGoBack: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();
  private url: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as WebViewParams | undefined;
    this.url = params?.url ?? '';
    this.pageTitle = params?.title ?? this.url;
  }

  // Back button steps through in-page browser history first (matches every
  // other in-app browser's expected behavior), only leaving the page once
  // there's nothing left to go back to within the webview itself.
  private handleBack(): void {
    if (this.canGoBack) {
      this.controller.backward();
      return;
    }
    router.back();
  }

  onBackPress(): boolean {
    this.handleBack();
    return true;
  }

  build() {
    Column() {
      Row() {
        Text('← 戻る')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(16)
          .fontColor(kbTheme(this.isDark).onAccent)
          .onClick(() => { this.handleBack(); })
        Text(this.pageTitle)
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).onAccent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .backgroundColor(kbTheme(this.isDark).accent)
      .alignItems(VerticalAlign.Center)

      if (this.url.length > 0) {
        Web({ src: this.url, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .onPageBegin(() => {
            this.canGoBack = this.controller.accessBackward();
          })
          .onPageEnd(() => {
            this.canGoBack = this.controller.accessBackward();
          })
          .width('100%')
          .layoutWeight(1)
      } else {
        Text('表示するURLが指定されていません')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(14)
          .fontColor(this.isDark ? '#AAAAAA' : '#555555')
          .width('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDark ? '#121212' : '#FFFFFF')
  }
}
