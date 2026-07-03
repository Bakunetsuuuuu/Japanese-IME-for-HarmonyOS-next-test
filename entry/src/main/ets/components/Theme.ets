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

// Original theme — オリジナルフラットカラー
export const ORIGINAL_LIGHT: KbTheme = {
  panelBg: '#D1D5DB', previewBarBg: '#F0F2F5', composingBarBg: '#FAFAFA',
  selectingBarBg: '#E0E3E8', keyBg: '#FFFFFF', specialKeyBg: '#ADB5BD',
  funcKeyBg: '#C0C5CC', candidateBg: '#FFFFFF', accentBg: '#4A90E2',
  accentStrongBg: '#1565C0', keyText: '#111111', onAccentText: '#FFFFFF',
  previewText: '#111111', subText: '#444444', borderColor: '#CCCCCC',
  shadowColor: '#33000000',
};

export const ORIGINAL_DARK: KbTheme = {
  panelBg: '#161618', previewBarBg: '#202022', composingBarBg: '#242426',
  selectingBarBg: '#2C2C2E', keyBg: '#48484A', specialKeyBg: '#2E2E30',
  funcKeyBg: '#3A3A3C', candidateBg: '#48484A', accentBg: '#3A6FB0',
  accentStrongBg: '#2A5A96', keyText: '#F5F5F5', onAccentText: '#FFFFFF',
  previewText: '#F0F0F0', subText: '#C0C0C0', borderColor: '#000000',
  shadowColor: '#55000000',
};

// Glass theme — iOS Liquid Glass 風
export const GLASS_LIGHT: KbTheme = {
  panelBg: '#D9E4E7EB', previewBarBg: '#D9F5F6F8', composingBarBg: '#BFFAFAFC',
  selectingBarBg: '#D9EEF1F3', keyBg: '#D9FFFFFF', specialKeyBg: '#E6D8DCE0',
  funcKeyBg: '#E6CDD1D6', candidateBg: '#D9FFFFFF', accentBg: '#3B82F6',
  accentStrongBg: '#2563EB', keyText: '#1C1C1E', onAccentText: '#FFFFFF',
  previewText: '#1C1C1E', subText: '#8E8E93', borderColor: '#30B8BDC2',
  shadowColor: '#08000000',
};

export const GLASS_DARK: KbTheme = {
  panelBg: '#1C1C1E', previewBarBg: '#2C2C2E', composingBarBg: '#323234',
  selectingBarBg: '#3A3A3C', keyBg: '#505052', specialKeyBg: '#36363A',
  funcKeyBg: '#424246', candidateBg: '#505052', accentBg: '#3B82F6',
  accentStrongBg: '#2563EB', keyText: '#F5F5F5', onAccentText: '#FFFFFF',
  previewText: '#F0F0F0', subText: '#AEAEB2', borderColor: '#38383A',
  shadowColor: '#3A000000',
};

export function kbTheme(isDark: boolean, variant?: string): KbTheme {
  const v = variant ?? 'original';
  if (v === 'glass') return isDark ? GLASS_DARK : GLASS_LIGHT;
  return isDark ? ORIGINAL_DARK : ORIGINAL_LIGHT;
}
