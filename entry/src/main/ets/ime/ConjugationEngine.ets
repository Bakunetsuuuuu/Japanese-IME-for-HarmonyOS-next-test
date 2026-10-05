// ユーザー辞書の品詞 (キーボード設定内 DictEditBar の品詞チップ) の型と、動詞の行の見分け。
// 登録した語の活用形は AiConverter.setUserDict が作って AI 変換の網に入れる。
// (以前はここで旧エンジン用に活用形と接続クラスを展開していた。旧エンジンと一緒に外した)

export type VerbGroup = 'ichidan' | 'godan';
export type GodanRow = 'u' | 'ku' | 'gu' | 'su' | 'tsu' | 'nu' | 'bu' | 'mu' | 'ru';
export type PosKind = 'noun' | 'verb' | 'adjective' | 'person' | 'place';

// Per-entry 品詞 metadata shape persisted by UserPosStore -- defined here
// (rather than in UserPosStore.ets) so this module doesn't need to import
// back from its own consumer.
export interface UserPosEntry {
  pos: PosKind;
  // Only meaningful for pos==='verb'; required when the reading ends in る
  // since godan-る and ichidan both end in る (see detectGodanRow).
  group?: VerbGroup;
}

// Detects the godan row from a dictionary-form reading's final kana. る is
// deliberately excluded: godan-る (帰る) and ichidan (食べる) both end in る,
// so that case is ambiguous from spelling alone and the caller must ask the
// user (see DictEditBar's 五段/一段 chips).
export function detectGodanRow(lastKana: string): GodanRow | undefined {
  const map: Record<string, GodanRow> = {
    'う': 'u', 'く': 'ku', 'ぐ': 'gu', 'す': 'su', 'つ': 'tsu',
    'ぬ': 'nu', 'ぶ': 'bu', 'む': 'mu',
  };
  return map[lastKana];
}
