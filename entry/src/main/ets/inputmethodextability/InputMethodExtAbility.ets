import { InputMethodExtensionAbility } from '@kit.IMEKit';
import type { Want } from '@kit.AbilityKit';
import { KeyboardController } from '../ime/KeyboardController';

export default class InputMethodExtAbility extends InputMethodExtensionAbility {
  private kbController: KeyboardController | undefined = undefined;

  onCreate(want: Want): void {
    this.kbController = new KeyboardController(this.context);
    this.kbController.onCreate();
  }

  onConfigurationUpdate(config: object): void {
    try {
      // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1
      const cm = (config as Record<string, number>)['colorMode'];
      if (cm !== undefined) {
        AppStorage.setOrCreate('isDark', cm === 0);
      } else {
        this.kbController?.applyColorMode();
      }
    } catch (_e) {
      this.kbController?.applyColorMode();
    }
  }

  onDestroy(): void {
    this.kbController?.onDestroy();
    this.kbController = undefined;
  }
}
