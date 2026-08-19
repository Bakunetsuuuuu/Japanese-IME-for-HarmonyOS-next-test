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
  deleteRed: ResourceColor;      // destructive actions (settings delete)
}

export const LIGHT_THEME: KbTheme = {
  panelBg: '#F1F3F5',
  keyBg: '#FFFFFF',
  candidateBg: '#FFFFFF',
  specialBg: '#E5E5EA',
  funcBg: '#E5E5EA',
  cardBg: '#FFFFFF',
  accent: '#0A59F7',
  accentSoft: '#0C0A59F7',
  accentStrong: '#CC0A59F7',
  textPrimary: '#E5000000',
  textSecondary: '#66000000',
  onAccent: '#FFFFFF',
  divider: '#E2E5EA',
  shadowColor: '#0F142B0F', // rgba(20,20,43,0.06)
  deleteRed: '#E84026',
};

export const DARK_THEME: KbTheme = {
  panelBg: '#191A1C',
  keyBg: '#202224',
  candidateBg: '#202224',
  specialBg: '#2E3033',
  funcBg: '#2E3033',
  cardBg: '#232325',
  accent: '#317AF7',
  accentSoft: '#0C317AF7',
  accentStrong: '#CC317AF7',
  textPrimary: '#E5FFFFFF',
  textSecondary: '#66FFFFFF',
  onAccent: '#FFFFFF',
  divider: '#2E3033',
  shadowColor: '#0F142B1F',
  deleteRed: '#D94838',
};

export function kbTheme(isDark: boolean): KbTheme {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
