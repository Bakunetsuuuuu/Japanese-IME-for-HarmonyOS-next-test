// Predictive completion for long, extremely common set phrases (greetings,
// business-email boilerplate) — once enough of a phrase's reading has been
// typed to be unambiguous, offer the whole thing as a candidate instead of
// making the user type it all out. Different from the regular DICTIONARY:
// that only ever matches once the *entire* reading has been typed; this
// matches on a *prefix*.
//
// minPrefix is chosen per phrase so it never fires while the reading typed
// so far is still itself a complete, common standalone word (verified against
// dict.json/global_dict.json when this list was authored — see the commit
// that introduced it for the check). E.g. よろしくおねがいします waits until
// past よろしく (already a common word on its own); おつかれさまでした waits
// until past おつかれさま (also already a complete word — harmless overlap,
// since the short and long completions coexist as separate candidates).
interface PredictivePhrase {
  reading: string;
  text: string;
  minPrefix: number;
}

const PREDICTIVE_PHRASES: PredictivePhrase[] = [
  { reading: 'あけましておめでとうございます', text: 'あけましておめでとうございます', minPrefix: 4 },
  { reading: 'おめでとうございます', text: 'おめでとうございます', minPrefix: 6 },
  { reading: 'たんじょうびおめでとうございます', text: '誕生日おめでとうございます', minPrefix: 8 },
  { reading: 'よろしくおねがいします', text: 'よろしくお願いします', minPrefix: 5 },
  { reading: 'よろしくおねがいいたします', text: 'よろしくお願いいたします', minPrefix: 5 },
  { reading: 'どうぞよろしくおねがいします', text: 'どうぞよろしくお願いします', minPrefix: 5 },
  { reading: 'こんごともよろしくおねがいします', text: '今後ともよろしくお願いします', minPrefix: 6 },
  { reading: 'なにとぞよろしくおねがいもうしあげます', text: '何卒よろしくお願い申し上げます', minPrefix: 5 },
  { reading: 'おつかれさまでした', text: 'お疲れ様でした', minPrefix: 6 },
  { reading: 'おつかれさまです', text: 'お疲れ様です', minPrefix: 6 },
  { reading: 'ありがとうございます', text: 'ありがとうございます', minPrefix: 6 },
  { reading: 'ありがとうございました', text: 'ありがとうございました', minPrefix: 6 },
  { reading: 'いつもありがとうございます', text: 'いつもありがとうございます', minPrefix: 5 },
  { reading: 'おせわになっております', text: 'お世話になっております', minPrefix: 5 },
  { reading: 'おせわになりました', text: 'お世話になりました', minPrefix: 5 },
  { reading: 'たいへんおせわになりました', text: '大変お世話になりました', minPrefix: 6 },
  { reading: 'ごぶさたしております', text: 'ご無沙汰しております', minPrefix: 5 },
  { reading: 'しつれいします', text: '失礼します', minPrefix: 5 },
  { reading: 'しつれいいたします', text: '失礼いたします', minPrefix: 5 },
  { reading: 'かしこまりました', text: 'かしこまりました', minPrefix: 6 },
  { reading: 'しょうちいたしました', text: '承知いたしました', minPrefix: 6 },
  { reading: 'おまたせしました', text: 'お待たせしました', minPrefix: 5 },
  { reading: 'おげんきですか', text: 'お元気ですか', minPrefix: 5 },
  { reading: 'おはようございます', text: 'おはようございます', minPrefix: 6 },
  { reading: 'たいへんもうしわけございません', text: '大変申し訳ございません', minPrefix: 6 },
  { reading: 'おてすうをおかけしますが', text: 'お手数をおかけしますが', minPrefix: 5 },
  { reading: 'ごかくにんよろしくおねがいします', text: 'ご確認よろしくお願いします', minPrefix: 6 },
  { reading: 'よいおとしを', text: 'よいお年を', minPrefix: 4 },
];

// Returns the full phrase text if `composing` is a long-enough prefix of a
// known phrase's reading (and there's actually more left to complete), else
// null. When two phrases share a prefix at the current composing length
// (e.g. ありがとうございます/ありがとうございました both start あり…ありがとうご),
// list order breaks the tie — put the more common variant first.
export function findPredictiveCompletion(composing: string): string | null {
  for (const p of PREDICTIVE_PHRASES) {
    if (composing.length >= p.minPrefix &&
        composing.length < p.reading.length &&
        p.reading.startsWith(composing)) {
      return p.text;
    }
  }
  return null;
}
