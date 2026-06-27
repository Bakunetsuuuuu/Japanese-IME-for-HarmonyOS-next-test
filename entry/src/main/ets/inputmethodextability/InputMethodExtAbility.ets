import { InputMethodExtensionAbility } from '@kit.IMEKit';
import type { Want } from '@kit.AbilityKit';
import { KeyboardController } from '../ime/KeyboardController';

export default class InputMethodExtAbility extends InputMethodExtensionAbility {
  private kbController: KeyboardController | undefined = undefined;

  onCreate(want: Want): void {
    this.kbController = new KeyboardController(this.context);
    this.kbController.onCreate();
  }

  onDestroy(): void {
    this.kbController?.onDestroy();
    this.kbController = undefined;
  }
}
