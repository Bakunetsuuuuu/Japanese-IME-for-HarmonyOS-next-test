import { InputMethodExtensionAbility } from '@kit.IMEKit';
import type { Want } from '@kit.AbilityKit';
import { KeyboardController } from '../ime/KeyboardController';

export default class InputMethodExtAbility extends InputMethodExtensionAbility {
  private kbController: KeyboardController | undefined = undefined;

  onCreate(want: Want): void {
    this.kbController = new KeyboardController(this.context);
    this.kbController.onCreate();
  }

  onConfigurationUpdate(newConfig: object): void {
    // Use the pushed Configuration directly (applyColorModeFrom), not
    // applyColorMode()'s context.config re-read -- see
    // isDarkFromConfiguration's comment (SettingsStore.ets) for why only the
    // object handed to this callback is guaranteed to reflect the OS's
    // current light/dark setting.
    this.kbController?.applyColorModeFrom(newConfig as ESObject);
  }

  onDestroy(): void {
    this.kbController?.onDestroy();
    this.kbController = undefined;
  }
}
