import dataPreferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';

// User-registered dictionary, shared between the main app (registration UI)
// and the IME extension (conversion) via @ohos.data.preferences.
// Storage: store 'shunti_userdict', key 'v1' = JSON of Record<よみ, 単語[]>.
export class UserDictStore {
  private static readonly STORE: string = 'shunti_userdict';
  private static readonly KEY: string = 'v1';

  // Load the user dictionary fresh from disk. forceReload drops the in-process
  // cache so writes made by the other process (app ⇄ IME) are picked up.
  static async load(
    context: common.Context,
    forceReload: boolean = false
  ): Promise<Record<string, string[]>> {
    try {
      if (forceReload) {
        await dataPreferences.removePreferencesFromCache(context, UserDictStore.STORE);
      }
      const prefs = await dataPreferences.getPreferences(context, UserDictStore.STORE);
      const raw = await prefs.get(UserDictStore.KEY, '{}');
      return JSON.parse(String(raw)) as Record<string, string[]>;
    } catch (_e) {
      return {};
    }
  }

  static async save(
    context: common.Context,
    dict: Record<string, string[]>
  ): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, UserDictStore.STORE);
      await prefs.put(UserDictStore.KEY, JSON.stringify(dict));
      await prefs.flush();
    } catch (_e) {}
  }

  // Add a reading→word pair. Returns the updated dictionary.
  static add(
    dict: Record<string, string[]>,
    yomi: string,
    word: string
  ): Record<string, string[]> {
    if (yomi.length === 0 || word.length === 0) { return dict; }
    const list = dict[yomi] ?? [];
    if (!list.includes(word)) {
      // New words go first so they lead the candidate list.
      dict[yomi] = [word, ...list];
    }
    return dict;
  }

  // Remove a specific reading→word pair. Returns the updated dictionary.
  static remove(
    dict: Record<string, string[]>,
    yomi: string,
    word: string
  ): Record<string, string[]> {
    const list = dict[yomi];
    if (!list) { return dict; }
    const next = list.filter((w: string) => w !== word);
    if (next.length === 0) {
      delete dict[yomi];
    } else {
      dict[yomi] = next;
    }
    return dict;
  }
}
