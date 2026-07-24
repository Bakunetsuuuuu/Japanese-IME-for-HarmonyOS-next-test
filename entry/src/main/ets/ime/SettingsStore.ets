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
  // 'custom' = hand-built dictionary (default, unchanged behavior).
  // 'mozc' = optional statistical engine derived from mozc (see
  // KanaKanjiConverter.loadMozcEngine / THIRD_PARTY_NOTICES.md).
  conversionEngine: string;
  // Whether the "あA"/"Aあ" mode-switch key cycles 日本語→アルファベット→数字
  // (numeric pad) or just 日本語⇔アルファベット -- see InputHandler.cycleInputMode
  // and KeyboardView.ets/FlickKeyboardView.ets's ModeKey/LeftKey. Off by
  // default: most users reach digits fine from QWERTY/the number row.
  numericPadEnabled: boolean;
}

const DEFAULTS: KeyboardSettings = {
  keyboardLayout: 'QWERTY',
  oneHandedMode: false,
  oneHandedSide: 'right',
  conversionEngine: 'custom',
  numericPadEnabled: false,
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
      const numericPad = await prefs.get('numericPadEnabled', DEFAULTS.numericPadEnabled);
      console.info('shuntiIME SettingsStore.load ok', JSON.stringify({ layout, oneHanded, side, engine, numericPad, forceReload }));
      return {
        keyboardLayout: String(layout),
        oneHandedMode: oneHanded === true,
        oneHandedSide: String(side),
        conversionEngine: String(engine),
        numericPadEnabled: numericPad === true,
      };
    } catch (e) {
      console.error('shuntiIME SettingsStore.load error', JSON.stringify(e));
      return {
        keyboardLayout: DEFAULTS.keyboardLayout,
        oneHandedMode: DEFAULTS.oneHandedMode,
        oneHandedSide: DEFAULTS.oneHandedSide,
        conversionEngine: DEFAULTS.conversionEngine,
        numericPadEnabled: DEFAULTS.numericPadEnabled,
      };
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

  static async saveNumericPadEnabled(context: common.Context, enabled: boolean): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('numericPadEnabled', enabled);
      await prefs.flush();
    } catch (_e) {}
  }
}

// Reads whether the OS is in dark mode -- the main app (EntryAbility) uses
// this the same way KeyboardController.applyColorMode does for the keyboard,
// so both halves of the app follow the system setting only (no manual
// テーマ override; that was tried and deliberately dropped again).
// Reads via context.config.colorMode, same as the keyboard extension's
// applyColorMode -- NOT display.getDefaultDisplaySync(), whose Display
// object has no colorMode field at all (that was the earlier bug: the
// field read back undefined, so isDark always resolved to false).
// common.Context's declared type has no `config` property (unlike the
// concrete InputMethodExtensionContext type KeyboardController.applyColorMode
// reads, which does) -- cast the context itself rather than context.config.
export function resolveMainAppIsDark(context: common.Context): boolean {
  try {
    return isDarkFromConfiguration((context as ESObject)['config']);
  } catch (_e) {
    return false;
  }
}

// Reads colorMode off a Configuration object directly -- specifically the one
// handed to onConfigurationUpdate(newConfig), NOT a re-read of context.config.
// That distinction matters: nothing in the ability lifecycle contract
// guarantees context.config is kept mutated in place as the OS setting
// changes after the ability/extension was created -- it's confirmed live only
// at that initial read (used by resolveMainAppIsDark/applyColorMode above for
// their one-time startup checks). Re-reading context.config from inside
// onConfigurationUpdate was the actual bug behind light/dark not tracking a
// live OS toggle: the callback fired, but the "fresh" read kept returning
// whatever color mode was active back at startup. The Configuration object
// onConfigurationUpdate is called with is the one value guaranteed to be the
// new state, so every update path must use it directly instead.
export function isDarkFromConfiguration(config: ESObject): boolean {
  try {
    const cm = config['colorMode'] as number;
    // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1.
    return cm === 0;
  } catch (_e) {
    return false;
  }
}
