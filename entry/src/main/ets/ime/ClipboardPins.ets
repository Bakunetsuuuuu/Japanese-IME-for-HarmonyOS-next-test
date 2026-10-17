import dataPreferences from '@ohos.data.preferences';

// クリップボードの履歴のうち、固定 (ピン留め) した文。履歴を消しても・新しくコピーしても残る (Gboard と同じ。ユーザー 2026-10-16)。
// 住所・メールアドレス・よく貼る定型など。画面には AppStorage 'clipboardPinned' で配る
const PINS_STORE: string = 'shunti_clip_pins';
const PINS_KEY: string = 'v1';
export const MAX_PINS: number = 20;

export class ClipboardPins {
  static async load(context: ESObject): Promise<void> {
    try {
      await dataPreferences.removePreferencesFromCache(context, PINS_STORE);   // 設定画面 (別のプロセス) で変えた分も読む
      const prefs = await dataPreferences.getPreferences(context, PINS_STORE);
      const raw = await prefs.get(PINS_KEY, '[]');
      const parsed = JSON.parse(String(raw)) as string[];
      const pins = Array.isArray(parsed) ? parsed.filter((s: string) => typeof s === 'string' && s.length > 0) : [];
      AppStorage.setOrCreate('clipboardPinned', pins.slice(0, MAX_PINS));
    } catch (_e) {
      AppStorage.setOrCreate('clipboardPinned', [] as string[]);
    }
  }

  // 固定する / 外す。固定したものは先頭に
  static async toggle(context: ESObject, text: string): Promise<void> {
    if (text.length === 0) { return; }
    const pins = AppStorage.get<string[]>('clipboardPinned') ?? [];
    const next = pins.indexOf(text) >= 0 ? pins.filter((t: string) => t !== text) : [text, ...pins].slice(0, MAX_PINS);
    AppStorage.setOrCreate('clipboardPinned', next);
    try {
      const prefs = await dataPreferences.getPreferences(context, PINS_STORE);
      await prefs.put(PINS_KEY, JSON.stringify(next));
      await prefs.flush();
    } catch (_e) {
      // 書けなくても今のキーボードでは固定したまま (次に開いたときに消える)
    }
  }
}
