import { UIAbility } from '@kit.AbilityKit';
import type { Want, AbilityConstant } from '@kit.AbilityKit';
import type { window } from '@kit.ArkUI';
import { registerJpFont } from '../components/JpFont';

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
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    applyOpenUrlWant(want);
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
  }

  onBackground(): void {
  }
}
