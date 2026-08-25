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
  panelBg: ResourceColor;        // outer keyboard panel + preview/candidate row
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
}

// 2026-08-25、Huawei純正キーボードの背景色のスクリーンショット(単色の
// 切り抜き2枚、ライト/ダーク)をもらって panelBg を合わせた。前回
// (「キーボードの外側」= 同じ画面のChrome側と見比べた版) はダークを
// #020202 まで黒に寄せすぎていた -- 今回の直接の色指定でほぼ元の
// #1C1C1E 付近が正解だったと判明。panelBg のズレ量をそのまま他の面
// (keyBg/specialBg/funcBg/cardBg/divider) にも同じだけ足し引きして、
// 手つかずの旧パレットが持っていた相対関係 (パネルより一段明るいキー面、
// さらに明るい特殊キー面…) を保ったまま合わせてある。accent系(Enter等の
// 青)とテキスト色は背景合わせの対象外なので触っていない。
export const LIGHT_THEME: KbTheme = {
  panelBg: '#E1E4E9',
  keyBg: '#F2F2F3',
  candidateBg: '#F2F2F3',
  specialBg: '#D6DAE0',
  funcBg: '#D2D6DD',
  cardBg: '#F2F2F3',
  accent: '#2F6FED',
  accentSoft: '#DCE7FD',
  accentStrong: '#1E54C7',
  textPrimary: '#1C1C1E',
  textSecondary: '#7A7F87',
  onAccent: '#FFFFFF',
  divider: '#D5D8DE',
  shadowColor: '#0F142B0F', // rgba(20,20,43,0.06)
};

export const DARK_THEME: KbTheme = {
  panelBg: '#1E1E20',
  keyBg: '#2E2E30',
  candidateBg: '#2E2E30',
  specialBg: '#3C3C3E',
  funcBg: '#353538',
  cardBg: '#252527',
  accent: '#4C8DFF',
  accentSoft: '#274070',
  accentStrong: '#5B9BFF',
  textPrimary: '#F2F2F7',
  textSecondary: '#9A9AA0',
  onAccent: '#FFFFFF',
  divider: '#3C3C3E',
  shadowColor: '#0F142B1F',
};

export function kbTheme(isDark: boolean): KbTheme {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
