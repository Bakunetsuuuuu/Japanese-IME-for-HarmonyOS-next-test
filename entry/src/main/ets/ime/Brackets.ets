// 括弧の全種類 (開き, 閉じ)。どの括弧も必ず打てるように、変換の候補はここから出す。
// Android 版 Brackets.kt・Windows 版 desktop/core/composer.cpp の BRACKETS も同じ並び (変えるときは 3 つとも)。
export const ALL_BRACKETS: string[][] = [
  ['（', '）'], ['(', ')'], ['「', '」'], ['『', '』'], ['【', '】'], ['［', '］'], ['[', ']'],
  ['｛', '｝'], ['{', '}'], ['〔', '〕'], ['〈', '〉'], ['《', '》'], ['〖', '〗'], ['〘', '〙'],
  ['〚', '〛'], ['｢', '｣'], ['＜', '＞'], ['<', '>'], ['«', '»'], ['‹', '›'], ['“', '”'],
  ['‘', '’'], ['〝', '〟'], ['｟', '｠'],
];

// 読みに合う括弧の候補。
//   括弧 1 字 → 同じ側 (開き・閉じ) の全種類 (打った字が先頭)
//   かっこ → 全種類の組 / かっこひらき・かっことじ → 開き・閉じの全種類
// 括弧でない読みは空。
export function bracketVariants(reading: string): string[] {
  const opens: string[] = ALL_BRACKETS.map((p: string[]) => p[0]);
  const closes: string[] = ALL_BRACKETS.map((p: string[]) => p[1]);
  if (reading === 'かっこ') { return ALL_BRACKETS.map((p: string[]) => p[0] + p[1]); }
  if (reading === 'かっこひらき') { return opens; }
  if (reading === 'かっことじ') { return closes; }
  if (opens.includes(reading)) { return [reading, ...opens.filter((c: string) => c !== reading)]; }
  if (closes.includes(reading)) { return [reading, ...closes.filter((c: string) => c !== reading)]; }
  return [];
}
