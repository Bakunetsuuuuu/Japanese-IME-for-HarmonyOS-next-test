// Centralized color theme for the keyboard surface.
// Light and dark variants are selected via the 'isDark' AppStorage flag,
// which KeyboardController populates from the system color mode and keeps
// in sync through InputMethodExtAbility.onConfigurationUpdate.

export interface KbTheme {
  panelBg: ResourceColor;
  previewBarBg: ResourceColor;
  composingBarBg: ResourceColor;
  selectingBarBg: ResourceColor;
  keyBg: ResourceColor;
  specialKeyBg: ResourceColor;
  funcKeyBg: ResourceColor;
  candidateBg: ResourceColor;
  accentBg: ResourceColor;
  accentStrongBg: ResourceColor;
  keyText: ResourceColor;
  onAccentText: ResourceColor;
  previewText: ResourceColor;
  subText: ResourceColor;
  borderColor: ResourceColor;
  shadowColor: ResourceColor;
}

// Light Glass — iOS風の明るい半透明ガラスキーボード
export const LIGHT_THEME: KbTheme = {
  panelBg:          '#D9E4E7EB',
  previewBarBg:     '#D9F5F6F8',
  composingBarBg:   '#BFFAFAFC',
  selectingBarBg:   '#D9EEF1F3',
  keyBg:            '#D9FFFFFF',
  specialKeyBg:     '#E6D8DCE0',
  funcKeyBg:        '#E6CDD1D6',
  candidateBg:      '#D9FFFFFF',
  accentBg:         '#3B82F6',
  accentStrongBg:   '#2563EB',
  keyText:          '#1C1C1E',
  onAccentText:     '#FFFFFF',
  previewText:      '#1C1C1E',
  subText:          '#8E8E93',
  borderColor:      '#30B8BDC2',
  shadowColor:      '#08000000',
};

// Dark — ダークモード用（ソリッド）
export const DARK_THEME: KbTheme = {
  panelBg:          '#1C1C1E',
  previewBarBg:     '#2C2C2E',
  composingBarBg:   '#323234',
  selectingBarBg:   '#3A3A3C',
  keyBg:            '#505052',
  specialKeyBg:     '#36363A',
  funcKeyBg:        '#424246',
  candidateBg:      '#505052',
  accentBg:         '#3B82F6',
  accentStrongBg:   '#2563EB',
  keyText:          '#F5F5F5',
  onAccentText:     '#FFFFFF',
  previewText:      '#F0F0F0',
  subText:          '#AEAEB2',
  borderColor:      '#38383A',
  shadowColor:      '#3A000000',
};

export function kbTheme(isDark: boolean): KbTheme {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
