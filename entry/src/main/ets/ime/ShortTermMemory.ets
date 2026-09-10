// 短期記憶 (short-term memory): 今のセッション中に何度か選ばれた変換を、
// 長期学習 (KanaKanjiConverter の永続ストア) が追いつく前から予測変換に
// 反映させる。Gboard 等にある「直近よく使う語をすぐ拾う」の相当品。
//
// 永続化は一切しない -- プロセスが再起動すれば消える、文字どおり
// "短期" の記憶 (KanaKanjiConverter/NextWordPredictor/UnknownWordLearner は
// いずれも Preferences に保存する「長期」学習で、こちらとは別物)。
//
// 信頼度は低いところからスタートする:
//   - 1回だけ選ばれた語は「弱い」。予測変換の一覧には混ぜてよいが、
//     先頭(1番目)には絶対に出さない -- 1回のノイズだけでいきなり
//     一番目に出るのは煩わしい (呼び出し側 PredictiveConversion.predict
//     が「他に何か出ているときだけ足す」形でこれを保証する)。
//   - STRONG_MIN 回選ばれたら「強い」。ここまで来ればこのセッション内で
//     明らかに使っている語なので、先頭寄りに出してよく、決まり字
//     (prefix の続きが辞書上一意に絞られているかの判定) も無視してよい
//     -- 何度も選んでいる実績そのものが十分な確証になる。

const MAX_ENTRIES = 200;
export const STRONG_MIN = 2;

// reading/surface の区切り。通常の変換結果には出てこない制御文字なので、
// 連結だけのキーだと起きる「あ」+「いう」と「あい」+「う」の衝突を防げる
// (NextWordPredictor の BI_SEP と同じ考え方)。
const KEY_SEP = String.fromCharCode(0x1f);

export interface ShortTermHit {
  reading: string;
  surface: string;
  count: number;
}

interface Entry {
  reading: string;
  surface: string;
  count: number;
}

export class ShortTermMemory {
  // key = reading + KEY_SEP + surface。Record のキー列挙順は挿入順
  // (JS/ArkTS 仕様) なので、追い出しに「一番古い1件」を使える。
  private static entries: Record<string, Entry> = {};

  private static keyOf(reading: string, surface: string): string {
    return reading + KEY_SEP + surface;
  }

  static record(reading: string, surface: string): void {
    if (reading.length === 0 || surface.length === 0) { return; }
    const key = ShortTermMemory.keyOf(reading, surface);
    const existing = ShortTermMemory.entries[key];
    if (existing !== undefined) {
      existing.count += 1;
      return;
    }
    if (Object.keys(ShortTermMemory.entries).length >= MAX_ENTRIES) {
      ShortTermMemory.evictOldest();
    }
    ShortTermMemory.entries[key] = { reading, surface, count: 1 };
  }

  // delete は使わず作り直す (UnknownWordLearner.forget と同じ流儀)。
  private static evictOldest(): void {
    const keys = Object.keys(ShortTermMemory.entries);
    if (keys.length === 0) { return; }
    const dropKey = keys[0];
    const next: Record<string, Entry> = {};
    for (const k of keys) {
      if (k !== dropKey) { next[k] = ShortTermMemory.entries[k]; }
    }
    ShortTermMemory.entries = next;
  }

  // prefix を読みの先頭に持つ短期記憶のヒット、件数の多い順。
  static hitsForPrefix(prefix: string): ShortTermHit[] {
    if (prefix.length === 0) { return []; }
    const out: ShortTermHit[] = [];
    for (const key of Object.keys(ShortTermMemory.entries)) {
      const e = ShortTermMemory.entries[key];
      if (e.reading.length > prefix.length && e.reading.startsWith(prefix)) {
        out.push({ reading: e.reading, surface: e.surface, count: e.count });
      }
    }
    out.sort((a: ShortTermHit, b: ShortTermHit) => b.count - a.count);
    return out;
  }

  // フィールド切り替え等での明示的なクリアに使えるよう公開しておく
  // (現時点ではプロセス寿命そのものが十分に "短期" なので未使用でもよい)。
  static reset(): void {
    ShortTermMemory.entries = {};
  }
}
