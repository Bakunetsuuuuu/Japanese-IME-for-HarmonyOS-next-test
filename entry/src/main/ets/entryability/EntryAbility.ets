import { UIAbility } from '@kit.AbilityKit';
import type { Want, AbilityConstant } from '@kit.AbilityKit';
import type { window } from '@kit.ArkUI';
import { isDarkFromConfiguration, isDarkFromResourceManager } from '../ime/SettingsStore';

// Stashes a "please open this URL in the in-app browser" request (see
// KeyboardController.openGithubRepo) into AppStorage for Index.ets to pick
// up -- covers both a cold start (read in Index.aboutToAppear) and a
// re-launch into an already-running instance (onNewWant below, picked up by
// Index's @Watch on the same key), since onNewWant has no direct handle to
// the already-mounted page to navigate it itself.
function applyOpenUrlWant(want: Want): void {
  const url = want.parameters?.openUrl;
  if (typeof url === 'string' && url.length > 0) {
    AppStorage.setOrCreate('pendingWebViewUrl', url);
    const title = want.parameters?.openTitle;
    AppStorage.setOrCreate('pendingWebViewTitle', typeof title === 'string' ? title : '');
  }
  // Same hand-off pattern as openUrl above, but for raising the system share
  // sheet (KeyboardController.shareUrl → Index.onPendingShareUrlChanged) --
  // the share sheet needs a UIAbilityContext the IME extension lacks.
  const shareUrl = want.parameters?.shareUrl;
  if (typeof shareUrl === 'string' && shareUrl.length > 0) {
    AppStorage.setOrCreate('pendingShareUrl', shareUrl);
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    applyOpenUrlWant(want);
    this.applyColorMode();
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    applyOpenUrlWant(want);
  }

  // Resolves the live OS color mode into AppStorage('isDark'), which every
  // main-app page (Index/PrivacyPolicy/WebViewPage) reads via
  // @StorageLink instead of each independently calling
  // display.getDefaultDisplaySync() on its own in aboutToAppear (which
  // never updated again after that first read, and read the wrong field
  // besides). Backed by resourceManager (isDarkFromResourceManager), not
  // context.config -- see that function's comment for why: context.config
  // is only a snapshot from ability creation, so calling this from
  // onForeground with a context.config-based read (the previous approach)
  // never actually picked up a theme change made while backgrounded.
  private applyColorMode(): void {
    AppStorage.setOrCreate('isDark', isDarkFromResourceManager(this.context as ESObject));
  }

  // Fires on an OS-level color-mode change while the app is already running
  // (system config changed, not window-stage recreated), on OS
  // versions/timings where this callback actually reaches the ability. Uses
  // the pushed Configuration directly -- see isDarkFromConfiguration's
  // comment for why only the object handed to this callback (not a
  // context.config re-read) is guaranteed fresh here.
  onConfigurationUpdate(newConfig: object): void {
    AppStorage.setOrCreate('isDark', isDarkFromConfiguration(newConfig as ESObject));
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // The Japanese font is registered by Index.aboutToAppear, not here: at
    // this point loadContent hasn't run and there is no UI instance to
    // register into (see components/JpFont.ets).
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error('shuntiIME loadContent failed', JSON.stringify(err));
      }
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // Also covers "app already open, user switches OS dark mode in Settings,
    // comes back" on OS versions where onConfigurationUpdate doesn't fire
    // for a backgrounded (not destroyed) ability.
    this.applyColorMode();
  }

  onBackground(): void {
  }
}
