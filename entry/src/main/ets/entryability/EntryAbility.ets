import { UIAbility } from '@kit.AbilityKit';
import type { Want, AbilityConstant } from '@kit.AbilityKit';
import type { window } from '@kit.ArkUI';
import { registerJpFont } from '../components/JpFont';
import { resolveMainAppIsDark } from '../ime/SettingsStore';

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
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    applyOpenUrlWant(want);
    this.applyColorMode();
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    applyOpenUrlWant(want);
  }

  // Resolves the OS color mode into AppStorage('isDark'), which every
  // main-app page (Index/DevDict/PrivacyPolicy/WebViewPage) reads via
  // @StorageLink instead of each independently calling
  // display.getDefaultDisplaySync() on its own in aboutToAppear (which
  // never updated again after that first read).
  private applyColorMode(): void {
    AppStorage.setOrCreate('isDark', resolveMainAppIsDark());
  }

  // Fires on an OS-level color-mode change while the app is already
  // running (system config changed, not window-stage recreated) -- without
  // this, isDark would only ever be (re-)computed at the next cold start.
  onConfigurationUpdate(_newConfig: object): void {
    this.applyColorMode();
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    registerJpFont();
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
