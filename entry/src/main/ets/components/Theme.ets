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

export const LIGHT_THEME: KbTheme = {
  panelBg: '#EEF1F5',
  keyBg: '#FFFFFF',
  candidateBg: '#FFFFFF',
  specialBg: '#E3E7EC',
  funcBg: '#DFE3E9',
  cardBg: '#FFFFFF',
  accent: '#2F6FED',
  accentSoft: '#DCE7FD',
  accentStrong: '#1E54C7',
  textPrimary: '#1C1C1E',
  textSecondary: '#7A7F87',
  onAccent: '#FFFFFF',
  divider: '#E2E5EA',
  shadowColor: '#0F142B0F', // rgba(20,20,43,0.06)
};

export const DARK_THEME: KbTheme = {
  panelBg: '#1C1C1E',
  keyBg: '#2C2C2E',
  candidateBg: '#2C2C2E',
  specialBg: '#3A3A3C',
  funcBg: '#333336',
  cardBg: '#232325',
  accent: '#4C8DFF',
  accentSoft: '#274070',
  accentStrong: '#5B9BFF',
  textPrimary: '#F2F2F7',
  textSecondary: '#9A9AA0',
  onAccent: '#FFFFFF',
  divider: '#3A3A3C',
  shadowColor: '#0F142B1F',
};

export function kbTheme(isDark: boolean): KbTheme {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
