import dataPreferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';
import type { UserPosEntry } from './ConjugationEngine';

// UserPosEntry itself is defined in ConjugationEngine.ets, next to the
// PosKind/VerbGroup unions it's built from -- callers needing the type
// import it from there directly.
//
// Per-entry 品詞 (part-of-speech) metadata for the user dictionary, keyed the
// same way DictionaryEditPage already identifies an entry (yomi + word).
// Kept as its own @ohos.data.preferences store (not folded into
// UserDictStore's Record<よみ, 単語[]>) so the base yomi→word format the
// keyboard extension has always read stays untouched -- this store is purely
// additive metadata the extension consults separately (see
// ConjugationEngine.buildUserExpansion / KeyboardController.reloadUserDict).

// ArkTS doesn't support the `delete` operator on index-signature types --
// rebuild the record without the given key instead (used by set()/remove()
// below in place of `delete map[k]`).
function omitKey(map: Record<string, UserPosEntry>, key: string): Record<string, UserPosEntry> {
  const out: Record<string, UserPosEntry> = {};
  for (const k of Object.keys(map)) {
    if (k !== key) { out[k] = map[k]; }
  }
  return out;
}

export class UserPosStore {
  private static readonly STORE: string = 'shunti_userpos';
  private static readonly KEY: string = 'v1';

  static key(yomi: string, word: string): string {
    return yomi + '\t' + word;
  }

  static async load(
    context: common.Context,
    forceReload: boolean = false
  ): Promise<Record<string, UserPosEntry>> {
    try {
      if (forceReload) {
        await dataPreferences.removePreferencesFromCache(context, UserPosStore.STORE);
      }
      const prefs = await dataPreferences.getPreferences(context, UserPosStore.STORE);
      const raw = await prefs.get(UserPosStore.KEY, '{}');
      const parsed = JSON.parse(String(raw)) as Record<string, UserPosEntry>;
      const clean: Record<string, UserPosEntry> = {};
      if (parsed === null || typeof parsed !== 'object') { return clean; }
      for (const k of Object.keys(parsed)) {
        // Only keep entries with a valid pos string; anything malformed is
        // dropped so buildUserExpansion never sees a surprise shape.
        const e = parsed[k];
        if (e !== null && typeof e === 'object' && typeof e.pos === 'string') {
          clean[k] = e;
        }
      }
      return clean;
    } catch (_e) {
      return {};
    }
  }

  static async save(
    context: common.Context,
    map: Record<string, UserPosEntry>
  ): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, UserPosStore.STORE);
      await prefs.put(UserPosStore.KEY, JSON.stringify(map));
      await prefs.flush();
    } catch (_e) {}
  }

  // noun is the implicit default (no conjugation, no class override) so
  // there's no need to persist an entry for it -- keeps the store limited to
  // words that actually need special handling.
  static set(
    map: Record<string, UserPosEntry>,
    yomi: string,
    word: string,
    entry: UserPosEntry
  ): Record<string, UserPosEntry> {
    const k = UserPosStore.key(yomi, word);
    if (entry.pos === 'noun') {
      return omitKey(map, k);
    }
    map[k] = entry;
    return map;
  }

  static remove(
    map: Record<string, UserPosEntry>,
    yomi: string,
    word: string
  ): Record<string, UserPosEntry> {
    return omitKey(map, UserPosStore.key(yomi, word));
  }

  static get(
    map: Record<string, UserPosEntry>,
    yomi: string,
    word: string
  ): UserPosEntry | undefined {
    return map[UserPosStore.key(yomi, word)];
  }
}
