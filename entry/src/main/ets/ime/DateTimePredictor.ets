// Date/time predictive conversion (日付・時刻変換): typing きょう offers today's
// date, いま the current time, あした tomorrow's date, ことし this year — the
// "smart" reading→live-value expansion Japanese IMEs (ATOK, Google日本語入力)
// are expected to have and Gboard's generic engine does not do well. Includes
// the 和暦 (Reiwa era) form, which is distinctly useful for Japanese documents.
//
// Pure function of (reading, now): the current time is injected, never read
// inside, so the whole thing is deterministically unit-testable. Results are
// inserted as ALTERNATIVES (the normal conversion きょう→今日 stays candidate[0]);
// they are ephemeral values, so the caller must not feed them to conversion
// learning (see isNonLearningCandidate in KeyboardController).

const DOW: string[] = ['日', '月', '火', '水', '木', '金', '土'];

// Day-offset triggers: reading -> days from today.
const DAY_OFFSETS: Record<string, number> = {
  'きょう': 0, 'ほんじつ': 0,
  'あした': 1, 'あす': 1, 'みょうにち': 1,
  'きのう': -1, 'さくじつ': -1,
  'あさって': 2, 'みょうごにち': 2,
  'おととい': -2, 'いっさくじつ': -2,
};

// Year-offset triggers: reading -> years from this year.
const YEAR_OFFSETS: Record<string, number> = {
  'ことし': 0, 'こんねん': 0,
  'らいねん': 1, 'みょうねん': 1,
  'きょねん': -1, 'さくねん': -1,
  'さらいねん': 2,
};

// Current-time triggers.
const TIME_READINGS: Record<string, boolean> = {
  'いま': true, 'げんざい': true, 'ただいま': true,
};

export class DateTimePredictor {
  private static wareki(year: number, month: number, day: number): string | null {
    // Reiwa began 2019-05-01. Earlier eras are out of scope for a live-date
    // helper used in 2020s+; return null so no 和暦 variant is offered then.
    if (year > 2019 || (year === 2019 && (month > 5 || (month === 5 && day >= 1)))) {
      const r = year - 2018;
      return r === 1 ? '令和元年' : `令和${r}年`;
    }
    return null;
  }

  private static dateForms(d: Date): string[] {
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    const day = d.getDate();
    const dow = DOW[d.getDay()];
    const out: string[] = [
      `${y}年${m}月${day}日`,
      `${y}年${m}月${day}日(${dow})`,
      `${m}月${day}日`,
      `${y}/${m}/${day}`,
    ];
    const w = DateTimePredictor.wareki(y, m, day);
    if (w !== null) { out.push(`${w}${m}月${day}日`); }
    return out;
  }

  private static timeForms(d: Date): string[] {
    const h = d.getHours();
    const mm = d.getMinutes();
    const mm2 = mm < 10 ? `0${mm}` : `${mm}`;
    const ampm = h < 12 ? '午前' : '午後';
    let h12 = h % 12;
    if (h12 === 0) { h12 = 12; }
    return [
      `${h}:${mm2}`,
      `${h}時${mm}分`,
      `${ampm}${h12}時${mm}分`,
    ];
  }

  // Live date/time candidates for `reading` as of `now`, or [] if the reading
  // isn't a date/time trigger.
  static predict(reading: string, now: Date): string[] {
    const dayOff = DAY_OFFSETS[reading];
    if (dayOff !== undefined) {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + dayOff);
      return DateTimePredictor.dateForms(d);
    }
    const yearOff = YEAR_OFFSETS[reading];
    if (yearOff !== undefined) {
      const y = now.getFullYear() + yearOff;
      const w = DateTimePredictor.wareki(y, 6, 15); // mid-year: era is unambiguous
      const out: string[] = [`${y}年`];
      if (w !== null) { out.push(w); }
      return out;
    }
    if (TIME_READINGS[reading]) {
      return DateTimePredictor.timeForms(now);
    }
    return [];
  }
}
