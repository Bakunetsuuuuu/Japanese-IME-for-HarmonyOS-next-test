// Numeral formatting (数値変換): when the composing text is bare digits, offer
// the forms a Japanese writer actually wants — thousands-separated (1,000,000),
// the 万/億 mixed form (100万), and full 漢数字 (百万). Typing Arabic digits
// otherwise produced only the digits themselves, so amounts and counts had to
// be punctuated by hand.
//
// String-based throughout (no Number parsing) so arbitrarily large values keep
// full precision. Pure function of the digit string — unit-testable, no state.

const DIGIT_KANJI: string[] = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
const SMALL_UNITS: string[] = ['', '十', '百', '千'];      // positions within a 4-digit group
const BIG_UNITS: string[] = ['', '万', '億', '兆', '京'];  // per 4-digit group

// Longer than this and the 漢数字/万 forms stop being useful (and BIG_UNITS runs
// out past 京 = 10^16, i.e. 20 digits); comma form is still fine but we cap the
// whole feature to keep the candidate list sane.
const MAX_DIGITS = 20;

export class NumberFormatter {
  // Half-width the (possibly full-width) digit string, or null if `s` isn't a
  // pure run of digits.
  private static normalizeDigits(s: string): string | null {
    if (s.length === 0) { return null; }
    let out = '';
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c >= 0x30 && c <= 0x39) { out += s[i]; }            // ASCII 0-9
      else if (c >= 0xff10 && c <= 0xff19) { out += String.fromCharCode(c - 0xff10 + 0x30); } // full-width ０-９
      else { return null; }
    }
    return out;
  }

  private static addCommas(digits: string): string {
    let out = '';
    const n = digits.length;
    for (let i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 === 0) { out += ','; }
      out += digits[i];
    }
    return out;
  }

  // Convert a 1-4 digit group to 漢数字 using 千百十. `atGroupHead` true means
  // this group carries a 万/億/… unit after it, so a lone 1 stays 一 (一万) rather
  // than being dropped the way 千/百/十's leading 1 is (千 not 一千).
  private static groupToKanji(group: string): string {
    const g = group.padStart(4, '0');
    let out = '';
    for (let place = 3; place >= 0; place--) {
      const d = g.charCodeAt(3 - place) - 0x30; // high place first
      if (d === 0) { continue; }
      if (d === 1 && place > 0) {
        out += SMALL_UNITS[place];           // 千/百/十 (drop the leading 一)
      } else {
        out += DIGIT_KANJI[d] + SMALL_UNITS[place];
      }
    }
    return out;
  }

  private static toKanji(digits: string): string {
    // strip leading zeros for kanji rendering
    let s = digits.replace(/^0+/, '');
    if (s.length === 0) { return DIGIT_KANJI[0]; } // "0" -> 〇
    // split into 4-digit groups from the right
    const groups: string[] = [];
    for (let end = s.length; end > 0; end -= 4) {
      groups.push(s.slice(Math.max(0, end - 4), end));
    }
    // groups[0] is the lowest (万-less) group
    let out = '';
    for (let gi = groups.length - 1; gi >= 0; gi--) {
      const gk = NumberFormatter.groupToKanji(groups[gi]);
      if (gk.length === 0) { continue; } // all-zero group
      out += gk + BIG_UNITS[gi];
    }
    return out;
  }

  // The 万/億 "mixed" form: Arabic digits within each 4-group, kanji unit between
  // (12345678 -> 1234万5678). Zero groups are dropped (1000000 -> 100万).
  private static toManMixed(digits: string): string {
    let s = digits.replace(/^0+/, '');
    if (s.length === 0) { return '0'; }
    if (s.length <= 4) { return s; } // no 万 unit yet -> same as plain, caller dedups
    const groups: string[] = [];
    for (let end = s.length; end > 0; end -= 4) {
      groups.push(s.slice(Math.max(0, end - 4), end));
    }
    let out = '';
    for (let gi = groups.length - 1; gi >= 0; gi--) {
      const grp = groups[gi];
      if (parseInt(grp, 10) === 0) { continue; }
      // Only the highest present group keeps its natural width; lower groups are
      // zero-padded to 4 so 1234万0056 reads correctly (not 1234万56).
      const isHighest = out.length === 0;
      out += (isHighest ? String(parseInt(grp, 10)) : grp.padStart(4, '0')) + BIG_UNITS[gi];
    }
    return out;
  }

  // Formatted alternatives for a bare-digit composing string, or [] if it isn't
  // one / is too long / has a leading zero (likely an id, phone, zip — not a
  // quantity). candidate[0] stays the digits themselves; these follow.
  static predict(composing: string): string[] {
    const digits = NumberFormatter.normalizeDigits(composing);
    if (digits === null) { return []; }
    if (digits.length < 4 || digits.length > MAX_DIGITS) { return []; }
    if (digits[0] === '0') { return []; }
    const out: string[] = [];
    const push = (s: string): void => {
      if (s.length > 0 && s !== composing && out.indexOf(s) < 0) { out.push(s); }
    };
    push(NumberFormatter.addCommas(digits));
    push(NumberFormatter.toManMixed(digits));
    push(NumberFormatter.toKanji(digits));
    return out;
  }
}
