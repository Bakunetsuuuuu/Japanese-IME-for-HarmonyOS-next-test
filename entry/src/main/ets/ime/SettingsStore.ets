import dataPreferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';

// Keyboard-wide settings persisted via @ohos.data.preferences, shared between
// the main app (settings UI) and the IME extension — same idiom as
// UserDictStore: the main app writes, the extension calls load(ctx, true) to
// force a fresh disk read past its own process's in-memory cache.
export interface KeyboardSettings {
  keyboardLayout: string;
  oneHandedMode: boolean;
  oneHandedSide: string;
}

const DEFAULTS: KeyboardSettings = {
  keyboardLayout: 'QWERTY',
  oneHandedMode: false,
  oneHandedSide: 'right',
};

export class SettingsStore {
  private static readonly STORE: string = 'shunti_settings';

  static async load(context: common.Context, forceReload: boolean = false): Promise<KeyboardSettings> {
    try {
      if (forceReload) {
        await dataPreferences.removePreferencesFromCache(context, SettingsStore.STORE);
      }
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      const layout = await prefs.get('keyboardLayout', DEFAULTS.keyboardLayout);
      const oneHanded = await prefs.get('oneHandedMode', DEFAULTS.oneHandedMode);
      const side = await prefs.get('oneHandedSide', DEFAULTS.oneHandedSide);
      console.info('shuntiIME SettingsStore.load ok', JSON.stringify({ layout, oneHanded, side, forceReload }));
      return {
        keyboardLayout: String(layout),
        oneHandedMode: oneHanded === true,
        oneHandedSide: String(side),
      };
    } catch (e) {
      console.error('shuntiIME SettingsStore.load error', JSON.stringify(e));
      return { keyboardLayout: DEFAULTS.keyboardLayout, oneHandedMode: DEFAULTS.oneHandedMode, oneHandedSide: DEFAULTS.oneHandedSide };
    }
  }

  static async saveKeyboardLayout(context: common.Context, layout: string): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('keyboardLayout', layout);
      await prefs.flush();
      console.info('shuntiIME SettingsStore.saveKeyboardLayout ok', layout);
    } catch (e) {
      console.error('shuntiIME SettingsStore.saveKeyboardLayout error', JSON.stringify(e));
    }
  }

  static async saveOneHanded(context: common.Context, enabled: boolean, side: string): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('oneHandedMode', enabled);
      await prefs.put('oneHandedSide', side);
      await prefs.flush();
    } catch (_e) {}
  }
}
