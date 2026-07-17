import dataPreferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';
import display from '@ohos.display';

// Keyboard-wide settings persisted via @ohos.data.preferences, shared between
// the main app (settings UI) and the IME extension — same idiom as
// UserDictStore: the main app writes, the extension calls load(ctx, true) to
// force a fresh disk read past its own process's in-memory cache.
export interface KeyboardSettings {
  keyboardLayout: string;
  oneHandedMode: boolean;
  oneHandedSide: string;
  // 'custom' = hand-built dictionary (default, unchanged behavior).
  // 'mozc' = optional statistical engine derived from mozc (see
  // KanaKanjiConverter.loadMozcEngine / THIRD_PARTY_NOTICES.md).
  conversionEngine: string;
  // 'system' (default) follows the OS color mode, same as before this
  // setting existed. 'light'/'dark' pin the keyboard's own theme regardless
  // of the OS setting (design redesign's 外観 > テーマ control).
  themeMode: string;
}

const DEFAULTS: KeyboardSettings = {
  keyboardLayout: 'QWERTY',
  oneHandedMode: false,
  oneHandedSide: 'right',
  conversionEngine: 'custom',
  themeMode: 'system',
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
      const engine = await prefs.get('conversionEngine', DEFAULTS.conversionEngine);
      const themeMode = await prefs.get('themeMode', DEFAULTS.themeMode);
      console.info('shuntiIME SettingsStore.load ok', JSON.stringify({ layout, oneHanded, side, engine, themeMode, forceReload }));
      return {
        keyboardLayout: String(layout),
        oneHandedMode: oneHanded === true,
        oneHandedSide: String(side),
        conversionEngine: String(engine),
        themeMode: String(themeMode),
      };
    } catch (e) {
      console.error('shuntiIME SettingsStore.load error', JSON.stringify(e));
      return { keyboardLayout: DEFAULTS.keyboardLayout, oneHandedMode: DEFAULTS.oneHandedMode, oneHandedSide: DEFAULTS.oneHandedSide, conversionEngine: DEFAULTS.conversionEngine, themeMode: DEFAULTS.themeMode };
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

  static async saveConversionEngine(context: common.Context, engine: string): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('conversionEngine', engine);
      await prefs.flush();
      console.info('shuntiIME SettingsStore.saveConversionEngine ok', engine);
    } catch (e) {
      console.error('shuntiIME SettingsStore.saveConversionEngine error', JSON.stringify(e));
    }
  }

  static async saveThemeMode(context: common.Context, mode: string): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('themeMode', mode);
      await prefs.flush();
      console.info('shuntiIME SettingsStore.saveThemeMode ok', mode);
    } catch (e) {
      console.error('shuntiIME SettingsStore.saveThemeMode error', JSON.stringify(e));
    }
  }
}

// Resolves the persisted themeMode ('system'/'light'/'dark') into an actual
// isDark boolean, reading the OS color mode only when actually needed
// ('system'). Shared by both processes: KeyboardController.applyThemeMode
// has its own copy (it reads InputMethodExtensionContext.config directly,
// a different config shape than display.getDefaultDisplaySync() used here),
// this one is for the main app (EntryAbility / Index / DevDict /
// PrivacyPolicy / WebViewPage) so a テーマ choice made from the keyboard's
// own settings panel (SettingsBar's 外観 > テーマ) applies consistently to
// the main app too, instead of the main app only ever following the OS.
export async function resolveMainAppIsDark(context: common.Context): Promise<boolean> {
  const settings = await SettingsStore.load(context);
  if (settings.themeMode === 'light') { return false; }
  if (settings.themeMode === 'dark') { return true; }
  try {
    const dis = display.getDefaultDisplaySync();
    // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1.
    return (dis as ESObject)['colorMode'] === 0;
  } catch (_e) {
    return false;
  }
}
