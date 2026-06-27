import { InputMethodExtensionAbility } from '@kit.IMEKit';
import type { Want, Configuration } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { KeyboardController } from '../ime/KeyboardController';

export default class InputMethodExtAbility extends InputMethodExtensionAbility {
  private kbController: KeyboardController | undefined = undefined;

  onCreate(want: Want): void {
    this.kbController = new KeyboardController(this.context);
    this.kbController.onCreate();
  }

  // Fired when the system color mode (or other config) changes while the
  // keyboard is alive. Refresh the dark-mode flag so the theme switches live.
  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate(
      'isDark',
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    );
  }

  onDestroy(): void {
    this.kbController?.onDestroy();
    this.kbController = undefined;
  }
}
