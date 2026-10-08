// PCモードの画面 (言語バー・候補ウィンドウ・展開) の色と寸法。
//
// 色は Windows 11 の IME の候補ウィンドウに合わせる (明るい面に細い枠、
// 選んでいる行は薄く塗って左端にアクセント色の縦線)。ソフトキーボードの
// kbTheme は Huawei 純正キーボードに合わせた色なので、PC の画面には使わない。
//
// 寸法はパネル (窓) の大きさを決める PcModeController と、中身を描く
// PcCandidateWindow / LangBarPage の両方が使う。片方だけ変えると、窓より
// 中身が大きくて切れる・余白が余る、になるので必ずここで揃える。

export interface PcTheme {
  windowBg: ResourceColor;
  border: ResourceColor;
  textPrimary: ResourceColor;
  textSecondary: ResourceColor;
  hoverBg: ResourceColor;
  selectedBg: ResourceColor;
  accent: ResourceColor;
  shadow: ResourceColor;
  composingUnderline: ResourceColor;
}

export const PC_LIGHT: PcTheme = {
  windowBg: '#F9F9F9',
  border: '#E0E0E0',
  textPrimary: '#1A1A1A',
  textSecondary: '#5F5F5F',
  hoverBg: '#EDEDED',
  selectedBg: '#E3ECF7',
  accent: '#005FB8',
  shadow: '#24000000',
  composingUnderline: '#1A1A1A',
};

export const PC_DARK: PcTheme = {
  windowBg: '#2C2C2C',
  border: '#404040',
  textPrimary: '#FFFFFF',
  textSecondary: '#C5C5C5',
  hoverBg: '#383838',
  selectedBg: '#3B4350',
  accent: '#60CDFF',
  shadow: '#52000000',
  composingUnderline: '#FFFFFF',
};

export function pcTheme(isDark: boolean): PcTheme {
  return isDark ? PC_DARK : PC_LIGHT;
}

// ---------- 候補ウィンドウ (vp) ----------
// 1 ページの行数 (番号 1〜9 で選べる数)
export const CANDIDATE_PAGE_SIZE: number = 9;
// 窓の外側の余白。この内側に角丸の本体を描き、余白には影を落とす
// (窓の外には描けないので、影のぶんだけ窓を大きく取る)。
export const CAND_MARGIN_VP: number = 8;
export const CAND_PAD_VP: number = 4;
export const CAND_ROW_H_VP: number = 32;
// 入力欄が下線付きの表示に対応していないときだけ出す、読みの行
export const CAND_HEADER_H_VP: number = 30;
// ページ表示 (1/3 ◀ ▶)。候補が 1 ページに収まるときは出さない
export const CAND_FOOTER_H_VP: number = 24;
export const CAND_NUMBER_W_VP: number = 26;
export const CAND_FONT_FP: number = 16;
export const CAND_MIN_W_VP: number = 180;
export const CAND_MAX_W_VP: number = 520;
// 入力中 (まだ変換していない) に出す候補の数。Windows 11 の予測候補と同じく少なめ
export const CAND_LIVE_MAX: number = 5;

// 文字列の見た目の幅のおおよそ (vp)。全角 1 字 = フォントの大きさ、半角は約半分。
// 窓の幅を先に決める (中身の測定を待つと、窓の大きさが 1 打鍵遅れて追いかける)
// ための見積もりなので、多少大きめに出す。
export function estimateTextWidthVp(text: string, fontVp: number): number {
  let w = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    w += (c < 0x2E80 || (c >= 0xFF61 && c <= 0xFF9F)) ? fontVp * 0.6 : fontVp * 1.02;
  }
  return w;
}

// ---------- 言語バー (vp) ----------
export const LANGBAR_MARGIN_VP: number = 4;
export const LANGBAR_BODY_W_VP: number = 176;
export const LANGBAR_BODY_H_VP: number = 36;
export const LANGBAR_W_VP: number = LANGBAR_BODY_W_VP + LANGBAR_MARGIN_VP * 2;
export const LANGBAR_H_VP: number = LANGBAR_BODY_H_VP + LANGBAR_MARGIN_VP * 2;
// 画面の端・Dock から離す距離 (まだ動かしていないときの置き場所)
export const LANGBAR_EDGE_GAP_VP: number = 12;

// ---------- 展開 (絵文字・設定) (vp) ----------
export const POPUP_W_VP: number = 380;
export const POPUP_H_VP: number = 380;
export const POPUP_GAP_VP: number = 6;
