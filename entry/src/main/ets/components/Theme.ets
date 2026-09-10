// Centralized color theme for the keyboard surface.
// Light and dark variants are selected via the 'isDark' AppStorage flag,
// which KeyboardController populates from the system color mode and keeps
// in sync through InputMethodExtAbility.onConfigurationUpdate.
//
// Token names/values match the "Harmony Next 風" redesign handoff
// (design_handoff_ime_redesign/README.md) so the code and design spec read
// as the same vocabulary. accent/accentStrong are the two roles the redesign
// calls out as a single overridable pair -- swap them to recolor Enter, the
// selected candidate, active toggles/segments, and the active flick-drag
// hint everywhere at once.

export interface KbTheme {
  // Backgrounds
  panelBg: ResourceColor;        // outer keyboard panel
  // 変換中のかな表示帯・候補バーの「帯そのもの」の背景。以前は panelBg を
  // そのまま使っていたので、候補チップ(candidateBg)を変えても帯自体は
  // 変わらず、ユーザーが「変換バー」として見ているのはこちらの帯全体
  // だったため「色が変わってない」に見えていた (「変える場所を間違えて
  // るのでは」の指摘どおり)。パネル本体・帯・チップの3段で見分けが付く
  // ようにする。
  previewBg: ResourceColor;
  keyBg: ResourceColor;          // normal character keys
  candidateBg: ResourceColor;    // candidate/bunsetsu chip background (unselected)
  specialBg: ResourceColor;      // shift / backspace / mode / enter-adjacent keys
  funcBg: ResourceColor;         // secondary buttons, inactive segmented-control track
  cardBg: ResourceColor;         // settings row cards
  // Accents
  accent: ResourceColor;         // enter / selected candidate / active segment / active toggle
  accentSoft: ResourceColor;     // active flick-drag cell background
  accentStrong: ResourceColor;   // active flick-drag hint glyph color
  // Text
  textPrimary: ResourceColor;
  textSecondary: ResourceColor;  // secondary labels, flick hints, section headers
  onAccent: ResourceColor;       // text/glyph on accent-filled surfaces
  // Lines / shadow
  divider: ResourceColor;
  shadowColor: ResourceColor;
  deleteRed: ResourceColor;      // destructive actions (settings delete)
}

// 色そのものは実機の Huawei 純正キーボードから採寸した値を使う。
// PR #58 (UIの調整) は HarmonyOS デザインガイドの標準トークン
// (#F1F3F5 / #191A1C, accent #0A59F7 …) への差し替えを提案していたが、
// このキーボードは「純正と並べて違和感が無いこと」を優先しているので
// 実測値のまま据え置いた。PR からは deleteRed トークンだけ取り込んでいる。
//
// 2026-08-28、ライトの panelBg を実機の正確な値 #E3E4E6 に再訂正
// (前回 #E2E6E9 としていたが、青に寄りすぎていた)。前回同様、panelBg の
// ズレ量 (+1,-2,-3) をそのまま他の面 (keyBg/specialBg/funcBg/cardBg/
// divider) にも足し引きして、旧パレットが持っていた相対関係 (パネルより
// 一段明るいキー面、さらに明るい特殊キー面…) を保ったまま合わせてある。
// accent系(Enter等の青)とテキスト色は背景合わせの対象外なので触っていない。
//
// previewBg/candidateBg は当初 accent 系の青みを足していたが、
// 「青すぎて不自然」との指摘を受けてニュートラルな無彩色寄りに変更。
// パネル→帯→チップ の3段の明度差だけで見分けが付くようにしてある。
export const LIGHT_THEME: KbTheme = {
  panelBg: '#E3E4E6',
  previewBg: '#DADBDD',
  keyBg: '#F4F2F0',
  candidateBg: '#EDEEF0',
  specialBg: '#D8DADD',
  funcBg: '#D4D6DA',
  cardBg: '#F4F2F0',
  accent: '#2F6FED',
  accentSoft: '#DCE7FD',
  accentStrong: '#1E54C7',
  textPrimary: '#1C1C1E',
  textSecondary: '#7A7F87',
  onAccent: '#FFFFFF',
  divider: '#D7D8DB',
  shadowColor: '#0F142B0F', // rgba(20,20,43,0.06)
  deleteRed: '#E84026',
};

export const DARK_THEME: KbTheme = {
  panelBg: '#232323',
  previewBg: '#1C1C1C',
  keyBg: '#333333',
  candidateBg: '#3A3A3C',
  specialBg: '#414141',
  funcBg: '#3A3A3B',
  cardBg: '#2A2A2A',
  accent: '#4C8DFF',
  accentSoft: '#274070',
  accentStrong: '#5B9BFF',
  textPrimary: '#F2F2F7',
  textSecondary: '#9A9AA0',
  onAccent: '#FFFFFF',
  divider: '#414141',
  shadowColor: '#0F142B1F',
  deleteRed: '#D94838',
};

export function kbTheme(isDark: boolean): KbTheme {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
