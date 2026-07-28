// 候補の削除 (candidate suppression): a per-reading list of surfaces the user
// has explicitly removed via long-press → 削除, filtered out of the candidate
// list before it is shown.
//
// A suppression list rather than a deletion from any one source, because a
// candidate can arrive from any of DICTIONARY, dict.json, global_dict.json, the
// mozc engine, the user dictionary, conversion learning or unknown-word
// learning -- most of which are read-only bundled data with nothing to delete
// from. Filtering at the point of display is the only mechanism that works
// uniformly for all of them, and it stays correct when the underlying
// dictionaries are updated later.
//
// Deleting a candidate is expected to be permanent-feeling but never
// destructive: the learned records for the pair are purged separately by the
// caller (so a boost can't resurrect it), while the bundled dictionaries are
// untouched and the whole list can be cleared again from the settings panel.

const MAX_READINGS = 500;
const MAX_PER_READING = 20;

export class SuppressedCandidates {
  // reading -> surfaces the user removed for that reading
  private static map: Record<string, string[]> = {};

  static setSuppressed(data: Record<string, string[]>): void {
    SuppressedCandidates.map = (data === undefined || data === null) ? {} : data;
  }

  static getSuppressed(): Record<string, string[]> {
    return SuppressedCandidates.map;
  }

  static clear(): void {
    SuppressedCandidates.map = {};
  }

  // How many readings currently have at least one removed candidate -- shown in
  // the settings panel so the reset entry can say whether there's anything to
  // reset.
  static count(): number {
    return Object.keys(SuppressedCandidates.map).length;
  }

  // Remove `surface` from `reading`'s candidates from now on. Returns false when
  // the request was refused: an empty pair, a list already at its cap, or an
  // attempt to suppress the reading's own kana -- that one is the guaranteed
  // fallback in filter(), so allowing it removed would let a reading end up with
  // nothing to commit at all.
  static suppress(reading: string, surface: string): boolean {
    if (reading.length === 0 || surface.length === 0) { return false; }
    if (surface === reading) { return false; }
    let list = SuppressedCandidates.map[reading];
    if (list === undefined) {
      if (Object.keys(SuppressedCandidates.map).length >= MAX_READINGS) { return false; }
      list = [];
      SuppressedCandidates.map[reading] = list;
    }
    if (list.indexOf(surface) >= 0) { return true; }
    if (list.length >= MAX_PER_READING) { return false; }
    list.push(surface);
    return true;
  }

  static isSuppressed(reading: string, surface: string): boolean {
    const list = SuppressedCandidates.map[reading];
    return list !== undefined && list.indexOf(surface) >= 0;
  }

  // Drop every suppressed surface from `cands`. If that would leave nothing to
  // show, the reading's own kana is returned instead of the original list --
  // committing what was typed is always possible, and a deleted candidate must
  // never reappear just because it happened to be the last one standing.
  static filter(reading: string, cands: string[]): string[] {
    const list = SuppressedCandidates.map[reading];
    if (list === undefined || list.length === 0) { return cands; }
    const kept = cands.filter((c: string) => list.indexOf(c) < 0);
    if (kept.length > 0) { return kept; }
    return [reading];
  }
}
