import { InputMethodExtensionAbility } from '@kit.IMEKit';
import type { Want } from '@kit.AbilityKit';
import { KeyboardController } from '../ime/KeyboardController';

export default class InputMethodExtAbility extends InputMethodExtensionAbility {
  private kbController: KeyboardController | undefined = undefined;

  onCreate(want: Want): void {
    this.kbController = new KeyboardController(this.context);
    this.kbController.onCreate();
  }

  onConfigurationUpdate(_config: object): void {
    // Always go through applyColorMode() (not a direct isDark write here)
    // so a user-pinned テーマ (settings panel 外観 > テーマ) keeps winning
    // over an OS color-mode change instead of being silently overridden.
    this.kbController?.applyColorMode();
  }

  onDestroy(): void {
    this.kbController?.onDestroy();
    this.kbController = undefined;
  }
}
