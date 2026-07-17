// Runtime conjugation/classification engine for user-dictionary POS support
// (DictionaryEditPage's 品詞 picker). Ported from tools/build_inline_dict.py's
// conj_ichidan/conj_godan_*/classify_verb_right_class, which built the
// built-in VERB_CLASS table baked into KanaKanjiConverter.ets. This module
// does the same thing at runtime, scoped to whatever the user just typed in
// the main app, instead of at build time for the whole dictionary.
//
// Class IDs match the Phase-2.5 100-class connection matrix (see
// KanaKanjiConverter.ets's "Nouns 0-13 | Verbs 14-33 | Adj 34-41 …" comment
// and tools/gen_matrix_default.py, the source of truth for the IDs below):
//   N_PROPER_P=4 (人名) N_PROPER_L=5 (地名)
//   V_BASE: godan=14, ichidan=22 -- entering-edge class, constant per group
//   V suffix classes: TA=18 TE=17 COND(ば)=20 MASU=14 NAI/TAI=34 NAKATTA/TAKATTA=37
//                      NAKUTE/TAKUTE=36 TAKUNAI=38
//   ADJ_BASE=34 ADJ_KU=35 ADJ_TE=36 ADJ_TA=37 ADJ_NAI_KU=38

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

export const N_PROPER_P = 4; // 人名
export const N_PROPER_L = 5; // 地名

// Detects the godan row from a dictionary-form reading's final kana. る is
// deliberately excluded: godan-る (帰る) and ichidan (食べる) both end in る,
// so that case is ambiguous from spelling alone and the caller must ask the
// user (see DictionaryEditPage's 五段/一段 picker).
export function detectGodanRow(lastKana: string): GodanRow | undefined {
  const map: Record<string, GodanRow> = {
    'う': 'u', 'く': 'ku', 'ぐ': 'gu', 'す': 'su', 'つ': 'tsu',
    'ぬ': 'nu', 'ぶ': 'bu', 'む': 'mu',
  };
  return map[lastKana];
}

// True if `lastKana` can end a verb dictionary form at all (godan row or る).
export function isVerbEnding(lastKana: string): boolean {
  return lastKana === 'る' || detectGodanRow(lastKana) !== undefined;
}

function buildForms(rStem: string, kStem: string, pairs: string[][]): Record<string, string[]> {
  const d: Record<string, string[]> = {};
  for (const p of pairs) {
    d[rStem + p[0]] = [kStem + p[1]];
  }
  return d;
}

function conjIchidan(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['る', 'る'], ['ない', 'ない'], ['なかった', 'なかった'], ['ないで', 'ないで'],
    ['なくて', 'なくて'], ['た', 'た'], ['て', 'て'], ['ます', 'ます'],
    ['ません', 'ません'], ['ました', 'ました'], ['ませんでした', 'ませんでした'],
    ['たい', 'たい'], ['たかった', 'たかった'], ['たくない', 'たくない'],
    ['ている', 'ている'], ['ていた', 'ていた'], ['ていない', 'ていない'],
    ['ています', 'ています'], ['てから', 'てから'], ['てください', 'てください'],
    ['てみる', 'てみる'], ['てみた', 'てみた'], ['たら', 'たら'], ['たり', 'たり'],
    ['れば', 'れば'], ['られる', 'られる'], ['られた', 'られた'], ['られない', 'られない'],
    ['させる', 'させる'], ['させた', 'させた'], ['させない', 'させない'],
  ]);
}

function conjGodanU(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['う', 'う'], ['わない', 'わない'], ['わなかった', 'わなかった'], ['わないで', 'わないで'],
    ['った', 'った'], ['って', 'って'], ['います', 'います'], ['いません', 'いません'],
    ['いました', 'いました'], ['いたい', 'いたい'], ['いたかった', 'いたかった'],
    ['っている', 'っている'], ['っていた', 'っていた'], ['っていない', 'っていない'],
    ['っています', 'っています'], ['ってから', 'ってから'], ['ってください', 'ってください'],
    ['ったら', 'ったら'], ['えば', 'えば'], ['える', 'える'], ['われる', 'われる'],
    ['われた', 'われた'], ['わせる', 'わせる'],
  ]);
}

function conjGodanKu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['く', 'く'], ['かない', 'かない'], ['かなかった', 'かなかった'], ['いた', 'いた'],
    ['いて', 'いて'], ['きます', 'きます'], ['きません', 'きません'], ['きました', 'きました'],
    ['きたい', 'きたい'], ['きたかった', 'きたかった'], ['いている', 'いている'],
    ['いていた', 'いていた'], ['いていない', 'いていない'], ['いています', 'いています'],
    ['いてから', 'いてから'], ['いてください', 'いてください'], ['いたら', 'いたら'],
    ['けば', 'けば'], ['ける', 'ける'], ['かれる', 'かれる'], ['かれた', 'かれた'],
    ['かせる', 'かせる'],
  ]);
}

function conjGodanGu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['ぐ', 'ぐ'], ['がない', 'がない'], ['がなかった', 'がなかった'], ['いだ', 'いだ'],
    ['いで', 'いで'], ['ぎます', 'ぎます'], ['ぎません', 'ぎません'], ['ぎました', 'ぎました'],
    ['ぎたい', 'ぎたい'], ['いでいる', 'いでいる'], ['いでいた', 'いでいた'],
    ['いでください', 'いでください'], ['いだら', 'いだら'], ['げば', 'げば'], ['げる', 'げる'],
    ['がれる', 'がれる'], ['がせる', 'がせる'],
  ]);
}

function conjGodanSu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['す', 'す'], ['さない', 'さない'], ['さなかった', 'さなかった'], ['した', 'した'],
    ['して', 'して'], ['します', 'します'], ['しません', 'しません'], ['しました', 'しました'],
    ['したい', 'したい'], ['したかった', 'したかった'], ['している', 'している'],
    ['していた', 'していた'], ['していない', 'していない'], ['しています', 'しています'],
    ['してから', 'してから'], ['してください', 'してください'], ['したら', 'したら'],
    ['せば', 'せば'], ['せる', 'せる'], ['される', 'される'], ['された', 'された'],
    ['させる', 'させる'],
  ]);
}

function conjGodanTsu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['つ', 'つ'], ['たない', 'たない'], ['たなかった', 'たなかった'], ['った', 'った'],
    ['って', 'って'], ['ちます', 'ちます'], ['ちません', 'ちません'], ['ちました', 'ちました'],
    ['ちたい', 'ちたい'], ['っている', 'っている'], ['っていた', 'っていた'],
    ['っています', 'っています'], ['ってください', 'ってください'], ['ったら', 'ったら'],
    ['てば', 'てば'], ['てる', 'てる'], ['たれる', 'たれる'], ['たせる', 'たせる'],
  ]);
}

function conjGodanNu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['ぬ', 'ぬ'], ['なない', 'なない'], ['んだ', 'んだ'], ['んで', 'んで'],
    ['にます', 'にます'], ['にたい', 'にたい'], ['んでいる', 'んでいる'],
    ['んでいた', 'んでいた'], ['んだら', 'んだら'],
  ]);
}

function conjGodanBu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['ぶ', 'ぶ'], ['ばない', 'ばない'], ['ばなかった', 'ばなかった'], ['んだ', 'んだ'],
    ['んで', 'んで'], ['びます', 'びます'], ['びません', 'びません'], ['びました', 'びました'],
    ['びたい', 'びたい'], ['んでいる', 'んでいる'], ['んでいた', 'んでいた'],
    ['んでいない', 'んでいない'], ['んでいます', 'んでいます'], ['んでください', 'んでください'],
    ['んだら', 'んだら'], ['べば', 'べば'], ['べる', 'べる'], ['ばれる', 'ばれる'],
    ['ばれた', 'ばれた'], ['ばせる', 'ばせる'],
  ]);
}

function conjGodanMu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['む', 'む'], ['まない', 'まない'], ['まなかった', 'まなかった'], ['んだ', 'んだ'],
    ['んで', 'んで'], ['みます', 'みます'], ['みません', 'みません'], ['みました', 'みました'],
    ['みたい', 'みたい'], ['みたかった', 'みたかった'], ['んでいる', 'んでいる'],
    ['んでいた', 'んでいた'], ['んでいない', 'んでいない'], ['んでいます', 'んでいます'],
    ['んでください', 'んでください'], ['んだら', 'んだら'], ['めば', 'めば'], ['める', 'める'],
    ['まれる', 'まれる'], ['まれた', 'まれた'], ['ませる', 'ませる'],
  ]);
}

function conjGodanRu(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['る', 'る'], ['らない', 'らない'], ['らなかった', 'らなかった'], ['らないで', 'らないで'],
    ['った', 'った'], ['って', 'って'], ['ります', 'ります'], ['りません', 'りません'],
    ['りました', 'りました'], ['りたい', 'りたい'], ['りたかった', 'りたかった'],
    ['っている', 'っている'], ['っていた', 'っていた'], ['っていない', 'っていない'],
    ['っています', 'っています'], ['ってから', 'ってから'], ['ってください', 'ってください'],
    ['ったら', 'ったら'], ['れば', 'れば'], ['れる', 'れる'], ['られる', 'られる'],
    ['られた', 'られた'], ['らせる', 'らせる'],
  ]);
}

const GODAN_BUILDERS: Record<GodanRow, (r: string, k: string) => Record<string, string[]>> = {
  u: conjGodanU, ku: conjGodanKu, gu: conjGodanGu, su: conjGodanSu, tsu: conjGodanTsu,
  nu: conjGodanNu, bu: conjGodanBu, mu: conjGodanMu, ru: conjGodanRu,
};

// Generates {conjugatedReading: [conjugatedSurface]} for a verb whose
// dictionary-form reading/surface stems are rStem/kStem (i.e. with the final
// kana of the dictionary form already stripped -- たべる/食べる → たべ/食べ,
// はなす/話す → はな/話).
export function conjugateVerb(rStem: string, kStem: string, group: VerbGroup, row?: GodanRow): Record<string, string[]> {
  if (group === 'ichidan') { return conjIchidan(rStem, kStem); }
  if (row === undefined) { return {}; }
  return GODAN_BUILDERS[row](rStem, kStem);
}

// Mirrors classify_verb_right_class in tools/build_inline_dict.py. Order
// matters: more specific suffixes must be checked before shorter suffixes
// they also end with (たくない before ない).
function classifyVerbSuffix(suffix: string, groupBase: number): number {
  if (suffix.endsWith('なかった') || suffix.endsWith('たかった')) { return 37; }
  if (suffix.endsWith('なくて') || suffix.endsWith('たくて')) { return 36; }
  if (suffix.endsWith('たくない')) { return 38; }
  if (suffix.endsWith('ない') || suffix.endsWith('たい')) { return 34; }
  if (suffix.endsWith('た') || suffix.endsWith('だ')) { return 18; }
  if (suffix.endsWith('て') || suffix.endsWith('で')) { return 17; }
  if (suffix.endsWith('ば')) { return 20; }
  if (suffix.endsWith('ます') || suffix.endsWith('ません')) { return 14; }
  return groupBase;
}

// [leftClass, rightClass] for every reading in `forms` (as generated by
// conjugateVerb for the same rStem/group). leftClass is the constant
// group-base class (this span's identity as seen by whatever precedes it --
// nothing before a verb cares which conjugated form it turns out to be).
// rightClass is the fine-grained suffix class (this span's identity as seen
// by whatever follows it -- た-form vs て-form vs ない-form connect very
// differently). Same asymmetric split as the built-in VERB_CLASS table.
export function verbClassMap(rStem: string, group: VerbGroup, forms: Record<string, string[]>): Record<string, number[]> {
  const left = group === 'ichidan' ? 22 : 14;
  const out: Record<string, number[]> = {};
  for (const reading of Object.keys(forms)) {
    const suffix = reading.slice(rStem.length);
    out[reading] = [left, classifyVerbSuffix(suffix, left)];
  }
  return out;
}

// い-adjective conjugation, scoped to the core forms (see
// HANDOFF_trackA_pos_layer.md-style phase-1 precedent: whole-word forms with
// a real class beat the flat noun-default, exhaustive coverage isn't the
// goal). rStem/kStem have the dictionary form's trailing い already stripped
// (たのしい/楽しい → たのし/楽し).
function conjAdjective(r: string, k: string): Record<string, string[]> {
  return buildForms(r, k, [
    ['い', 'い'], ['く', 'く'], ['くて', 'くて'], ['くない', 'くない'],
    ['くなかった', 'くなかった'], ['かった', 'かった'],
  ]);
}

export function conjugateAdjective(rStem: string, kStem: string): Record<string, string[]> {
  return conjAdjective(rStem, kStem);
}

function classifyAdjSuffix(suffix: string): number {
  if (suffix === 'く') { return 35; }
  if (suffix === 'くて') { return 36; }
  if (suffix === 'かった' || suffix === 'くなかった') { return 37; }
  if (suffix === 'くない') { return 38; }
  return 34; // い (base) and anything unexpected
}

// Same asymmetric split as verbs: leftClass constant at ADJ_BASE (34) --
// nothing before an adjective cares which conjugated ending it becomes --
// rightClass is the fine-grained form class actually consumed by the
// (already-tuned, see gen_matrix_default.py) ADJ_BASE/ADJ_KU/ADJ_TE/ADJ_TA/
// ADJ_NAI_KU connection-matrix rows.
export function adjectiveClassMap(rStem: string, forms: Record<string, string[]>): Record<string, number[]> {
  const out: Record<string, number[]> = {};
  for (const reading of Object.keys(forms)) {
    const suffix = reading.slice(rStem.length);
    out[reading] = [34, classifyAdjSuffix(suffix)];
  }
  return out;
}

export interface UserExpansion {
  dict: Record<string, string[]>;
  classMap: Record<string, number[]>;
}

function mergeReading(dict: Record<string, string[]>, reading: string, cands: string[]): void {
  const existing = dict[reading];
  if (existing === undefined) {
    dict[reading] = cands;
    return;
  }
  for (const c of cands) {
    if (!existing.includes(c)) { existing.push(c); }
  }
}

// Expands the base user dictionary (yomi→word, exactly what the user typed
// into DictionaryEditPage and what Index.ets's list shows) into the
// candidate map + connection-matrix class map the keyboard extension
// actually loads: every verb/adjective entry additionally contributes its
// conjugated forms (たべる→食べる also yields たべなかった→食べなかった etc.),
// and every verb/adjective/person/place entry contributes a class override
// so the segmenter treats it as its real POS instead of the generic noun
// default. Pure function of its inputs -- KeyboardController calls this
// fresh on every reload; nothing produced here is itself persisted (see
// UserPosStore's own comment for why the metadata is kept separate from the
// base dictionary).
export function buildUserExpansion(
  dict: Record<string, string[]>,
  posMap: Record<string, UserPosEntry>
): UserExpansion {
  const outDict: Record<string, string[]> = {};
  for (const yomi of Object.keys(dict)) {
    outDict[yomi] = dict[yomi].slice();
  }
  const classMap: Record<string, number[]> = {};

  for (const yomi of Object.keys(dict)) {
    for (const word of dict[yomi]) {
      const entry = posMap[yomi + '\t' + word];
      if (entry === undefined || entry.pos === 'noun') { continue; }

      if (entry.pos === 'person') { classMap[yomi] = [N_PROPER_P, N_PROPER_P]; continue; }
      if (entry.pos === 'place') { classMap[yomi] = [N_PROPER_L, N_PROPER_L]; continue; }

      if (yomi.length < 2 || word.length < 2) { continue; }
      const lastKana = yomi.charAt(yomi.length - 1);

      if (entry.pos === 'verb') {
        const group: VerbGroup | undefined = entry.group ?? (lastKana === 'る' ? undefined : 'godan');
        if (group === undefined) { continue; } // る-ending with no recorded group -- can't conjugate safely
        const row: GodanRow | undefined = group === 'godan'
          ? (lastKana === 'る' ? 'ru' : detectGodanRow(lastKana))
          : undefined;
        if (group === 'godan' && row === undefined) { continue; }
        const rStem = yomi.slice(0, -1);
        const kStem = word.slice(0, -1);
        const forms = conjugateVerb(rStem, kStem, group, row);
        for (const reading of Object.keys(forms)) {
          mergeReading(outDict, reading, forms[reading]);
        }
        const cm = verbClassMap(rStem, group, forms);
        for (const reading of Object.keys(cm)) {
          classMap[reading] = cm[reading];
        }
        continue;
      }

      if (entry.pos === 'adjective') {
        if (lastKana !== 'い') { continue; }
        const rStem = yomi.slice(0, -1);
        const kStem = word.slice(0, -1);
        const forms = conjugateAdjective(rStem, kStem);
        for (const reading of Object.keys(forms)) {
          mergeReading(outDict, reading, forms[reading]);
        }
        const cm = adjectiveClassMap(rStem, forms);
        for (const reading of Object.keys(cm)) {
          classMap[reading] = cm[reading];
        }
      }
    }
  }

  return { dict: outDict, classMap };
}
