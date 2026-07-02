// Centralized color theme for the keyboard surface.
// Light and dark variants are selected via the 'isDark' AppStorage flag,
// which KeyboardController populates from the system color mode and keeps
// in sync through InputMethodExtAbility.onConfigurationUpdate.

export interface KbTheme {
  // Backgrounds
  panelBg: ResourceColor;        // outer keyboard panel
  previewBarBg: ResourceColor;   // candidate/toggle row
  composingBarBg: ResourceColor; // composing kana strip
  selectingBarBg: ResourceColor; // preview row while a candidate is selected
  keyBg: ResourceColor;          // normal character keys
  specialKeyBg: ResourceColor;   // shift / backspace / mode keys
  funcKeyBg: ResourceColor;      // layout-toggle and secondary buttons
  candidateBg: ResourceColor;    // candidate chip background
  // Accents
  accentBg: ResourceColor;       // enter / selected candidate
  accentStrongBg: ResourceColor; // active bunsetsu segment
  // Text
  keyText: ResourceColor;        // text on normal keys
  onAccentText: ResourceColor;   // text on accent / special keys
  previewText: ResourceColor;    // composing / candidate text
  subText: ResourceColor;        // secondary labels, flick hints
  // Lines / shadow
  borderColor: ResourceColor;
  shadowColor: ResourceColor;
}

export const LIGHT_THEME: KbTheme = {
  panelBg: '#D1D5DB',
  previewBarBg: '#F0F2F5',
  composingBarBg: '#FAFAFA',
  selectingBarBg: '#E0E3E8',
  keyBg: '#FFFFFF',
  specialKeyBg: '#ADB5BD',
  funcKeyBg: '#C0C5CC',
  candidateBg: '#FFFFFF',
  accentBg: '#4A90E2',
  accentStrongBg: '#1565C0',
  keyText: '#111111',
  onAccentText: '#FFFFFF',
  previewText: '#111111',
  subText: '#444444',
  borderColor: '#CCCCCC',
  shadowColor: '#33000000',
};

export const DARK_THEME: KbTheme = {
  // Matches HUAWEI's stock keyboard panel background so there's no visible
  // seam where the system draws around/behind this panel (e.g. the reserved
  // strip alongside a landscape panel — see KeyboardController.computeKeyWidths).
  panelBg: '#242424',
  previewBarBg: '#202022',
  composingBarBg: '#242426',
  selectingBarBg: '#2C2C2E',
  keyBg: '#48484A',
  specialKeyBg: '#2E2E30',
  funcKeyBg: '#3A3A3C',
  candidateBg: '#48484A',
  accentBg: '#3A6FB0',
  accentStrongBg: '#2A5A96',
  keyText: '#F5F5F5',
  onAccentText: '#FFFFFF',
  previewText: '#F0F0F0',
  subText: '#C0C0C0',
  borderColor: '#000000',
  shadowColor: '#55000000',
};

export function kbTheme(isDark: boolean): KbTheme {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
