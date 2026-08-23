import dataPreferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';

// Keyboard-wide settings persisted via @ohos.data.preferences, shared between
// the main app (settings UI) and the IME extension — same idiom as
// UserDictStore: the main app writes, the extension calls load(ctx, true) to
// force a fresh disk read past its own process's in-memory cache.
export interface KeyboardSettings {
  // Split so kana (ひらがな) and alphabet (アルファベット) input can each use
  // QWERTY or FLICK independently -- see load()'s legacyLayout migration note.
  kanaKeyboardLayout: string;
  alphabetKeyboardLayout: string;
  oneHandedMode: boolean;
  oneHandedSide: string;
  // 'hybrid' = 既定。mozc の統計エンジンで文を決めたうえで、候補の2番目以降に
  // 独自辞書の同音語を織り交ぜる (composeMozcCandidates 参照)。
  // 'mozc' = 織り交ぜ無しの素の mozc。'custom' = 独自の手作り辞書のみ。
  //
  // 根拠は tools/blind-eval の盲検350文 (Tatoeba由来で、この企画のどの調整も
  // 届いていない)。手持ちコーパスでは custom が勝つが、あれは custom に
  // 合わせて育てたものなので判断材料にならない。
  //
  // 候補[0]の完全一致:  custom 44.6%  /  mozc・hybrid 59.4%
  // 正解が候補リストの何位に出るか (tools/ime-eval/run_candlist.js):
  //
  //            1位     3位以内   5位以内   リストに無い
  //   custom   44.6%   44.6%     44.6%     55.4%
  //   mozc     59.4%   63.1%     65.4%     22.9%
  //   hybrid   59.4%   68.9%     70.3%     20.6%
  //
  // custom は候補が平均4.1個あるのに2番目以降がまったく効いていない
  // (正解は1位にあるか無いかのどちらか)。hybrid は候補[0]では mozc と同点で、
  // リストは全面的に上 -- 下がる指標が無いので既定はこれ。
  //
  // 影響するのは conversionEngine を一度も保存していない利用者だけ。
  // 自分で「独自辞書」を選んだ人は prefs の値が優先されるので変わらない。
  // 代わりに mozc のデータを読むぶんメモリが増える (実測で +46MB 程度)。
  conversionEngine: string;
  // Whether the "あA"/"Aあ" mode-switch key cycles 日本語→アルファベット→数字
  // (numeric pad) or just 日本語⇔アルファベット -- see InputHandler.cycleInputMode
  // and KeyboardView.ets/FlickKeyboardView.ets's ModeKey/LeftKey. Off by
  // default: most users reach digits fine from QWERTY/the number row.
  numericPadEnabled: boolean;
  // キーを押したときに短く振動させるか。
  hapticEnabled: boolean;
}

const DEFAULTS: KeyboardSettings = {
  kanaKeyboardLayout: 'QWERTY',
  alphabetKeyboardLayout: 'QWERTY',
  oneHandedMode: false,
  oneHandedSide: 'right',
  conversionEngine: 'hybrid',
  numericPadEnabled: false,
  hapticEnabled: false,
};

export class SettingsStore {
  private static readonly STORE: string = 'shunti_settings';

  static async load(context: common.Context, forceReload: boolean = false): Promise<KeyboardSettings> {
    try {
      if (forceReload) {
        await dataPreferences.removePreferencesFromCache(context, SettingsStore.STORE);
      }
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      // Legacy single 'keyboardLayout' key from before kana/alphabet were
      // split -- read it as the fallback default for both new keys, so an
      // existing install's FLICK/QWERTY choice carries over unchanged until
      // the user picks them independently (at which point the new keys win).
      const legacyLayout = await prefs.get('keyboardLayout', DEFAULTS.kanaKeyboardLayout);
      const kanaLayout = await prefs.get('kanaKeyboardLayout', legacyLayout);
      const alphabetLayout = await prefs.get('alphabetKeyboardLayout', legacyLayout);
      const oneHanded = await prefs.get('oneHandedMode', DEFAULTS.oneHandedMode);
      const side = await prefs.get('oneHandedSide', DEFAULTS.oneHandedSide);
      const engine = await prefs.get('conversionEngine', DEFAULTS.conversionEngine);
      const numericPad = await prefs.get('numericPadEnabled', DEFAULTS.numericPadEnabled);
      const haptic = await prefs.get('hapticEnabled', DEFAULTS.hapticEnabled);
      console.info('shuntiIME SettingsStore.load ok', JSON.stringify({ kanaLayout, alphabetLayout, oneHanded, side, engine, numericPad, forceReload }));
      return {
        kanaKeyboardLayout: String(kanaLayout),
        alphabetKeyboardLayout: String(alphabetLayout),
        oneHandedMode: oneHanded === true,
        oneHandedSide: String(side),
        conversionEngine: String(engine),
        numericPadEnabled: numericPad === true,
        hapticEnabled: haptic === true,
      };
    } catch (e) {
      console.error('shuntiIME SettingsStore.load error', JSON.stringify(e));
      return {
        kanaKeyboardLayout: DEFAULTS.kanaKeyboardLayout,
        alphabetKeyboardLayout: DEFAULTS.alphabetKeyboardLayout,
        oneHandedMode: DEFAULTS.oneHandedMode,
        oneHandedSide: DEFAULTS.oneHandedSide,
        conversionEngine: DEFAULTS.conversionEngine,
        numericPadEnabled: DEFAULTS.numericPadEnabled,
        hapticEnabled: DEFAULTS.hapticEnabled,
      };
    }
  }

  static async saveKanaKeyboardLayout(context: common.Context, layout: string): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('kanaKeyboardLayout', layout);
      await prefs.flush();
      console.info('shuntiIME SettingsStore.saveKanaKeyboardLayout ok', layout);
    } catch (e) {
      console.error('shuntiIME SettingsStore.saveKanaKeyboardLayout error', JSON.stringify(e));
    }
  }

  static async saveAlphabetKeyboardLayout(context: common.Context, layout: string): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('alphabetKeyboardLayout', layout);
      await prefs.flush();
      console.info('shuntiIME SettingsStore.saveAlphabetKeyboardLayout ok', layout);
    } catch (e) {
      console.error('shuntiIME SettingsStore.saveAlphabetKeyboardLayout error', JSON.stringify(e));
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

  static async saveHapticEnabled(context: common.Context, enabled: boolean): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, SettingsStore.STORE);
      await prefs.put('hapticEnabled', enabled);
      await prefs.flush();
    } catch (_e) {}
  }
}

// Reads colorMode off a Configuration object directly -- specifically the one
// handed to onConfigurationUpdate(newConfig), NOT a re-read of context.config.
// That distinction matters: nothing in the ability lifecycle contract
// guarantees context.config is kept mutated in place as the OS setting
// changes after the ability/extension was created -- it's confirmed live only
// at the ability/extension's own initial creation. Re-reading context.config
// later (whether from onConfigurationUpdate or from an onForeground/
// inputStart-style recheck) was the actual bug behind light/dark not
// tracking a live OS toggle: the recheck ran, but kept returning whatever
// color mode was active back at startup. The Configuration object
// onConfigurationUpdate is called with is the one value guaranteed to be the
// new state; isDarkFromResourceManager below is the fix for every other
// recheck point, which can't rely on that callback firing.
export function isDarkFromConfiguration(config: ESObject): boolean {
  try {
    const cm = config['colorMode'] as number;
    // ConfigurationConstant.ColorMode: COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1.
    return cm === 0;
  } catch (_e) {
    return false;
  }
}

// Reads the OS color mode via resourceManager.getConfigurationSync() instead
// of context.config -- unlike context.config (a snapshot, only guaranteed
// live at ability/extension creation -- see isDarkFromConfiguration's
// comment), resourceManager's Configuration re-resolves the current system
// setting on every call. This is the fix for isDark staying stuck until a
// full app/keyboard restart: calling this from every "about to show UI
// again" point (inputStart, onForeground) gets the live value without
// depending on onConfigurationUpdate actually firing, which HarmonyOS
// doesn't reliably deliver to a long-lived, mostly-idle IME extension.
export function isDarkFromResourceManager(context: ESObject): boolean {
  try {
    const cm = context['resourceManager'].getConfigurationSync()['colorMode'] as number;
    return cm === 0;
  } catch (_e) {
    return false;
  }
}
