import { bracketVariants } from './Brackets';
// AI 変換 (shuntelligence)。かな漢字変換はこれだけ (1.6.1 の次で、独自辞書・統計データ・ハイブリッドの旧エンジンを外した)。
// 中身は C++ (entry/src/main/cpp, libkkc.so): 辞書 shuntorge の単語の網 + 文脈を読む小さな Transformer (約 630 万
// パラメータ) + 上位 k。学習のコードと教材は公開していない (モデルの重みと推論のコードだけを同梱)。
// 辞書とモデル (rawfile の kkc_lex.bin / kkc_model.bin、合わせて約 115MB) は HAP の中のまま mmap して使う
// (端末に写さない。ArkTS の heap にも載せない)。
import kkc, { KkcResult } from 'libkkc.so';
import type common from '@ohos.app.ability.common';
import { DEBUG_INPUT_LOG } from './InputLog';
import type { UserPosEntry } from './ConjugationEngine';

// 長い入力で固定した前の方の 1 か所 (読みと、選び直せる候補。cands[0] が今の表記)
interface FrozenChunk {
  kana: string;
  cands: string[];
}

export class AiConverter {
  private static ready: boolean = false;
  private static loading: boolean = false;
  private static failed: boolean = false;
  static lastMs: number = 0;
  private static lastRunMs: number = 0;   // 直前の変換そのものにかかった時間 (順番待ち・受け渡しを除く)

  static isReady(): boolean {
    return AiConverter.ready;
  }

  // 何度呼んでもよい。読み込みは 1 回だけ (裏のスレッドで)
  // 読み込みに失敗したら onFail (呼ぶ側が別のエンジンに切り替える)
  static ensureLoaded(ctx: common.Context, onFail: () => void = () => {}): void {
    if (AiConverter.failed) {
      onFail();
      return;
    }
    if (AiConverter.ready || AiConverter.loading) {
      return;
    }
    AiConverter.loading = true;
    const t0 = Date.now();
    kkc.loadAsync(ctx.resourceManager, ctx.filesDir, 4).then((ok: boolean) => {
      AiConverter.ready = ok;
      AiConverter.failed = !ok;
      AiConverter.loading = false;
      console.info(`shuntiIME AiConverter load ${ok ? 'ok' : 'failed'} ${Date.now() - t0}ms`);
      if (!ok) {
        onFail();
      } else {
        AiConverter.applyUserWords();   // 読み込みより先に届いたユーザー辞書を入れる
      }
    }).catch((e: Error) => {
      AiConverter.loading = false;
      AiConverter.failed = true;
      console.error('shuntiIME AiConverter load error', JSON.stringify(e));
      onFail();
    });
  }

  // ---- 予測・ユーザー辞書・その場の変換 ----

  // 予測: 読みが prefix で始まる、より長い辞書の語を、よく使う順に最大 max 個 (辞書を読むだけ。変換中でも待たない)
  static complete(prefix: string, max: number): string[] {
    if (!AiConverter.ready || prefix.length === 0) {
      return [];
    }
    return kkc.complete(prefix, 6, max);
  }

  // その場で変換する (呼んだスレッドで。裏で変換中なら終わるまで待つ)。文節を選ぶとき・語を作れるかを確かめるときに
  static convertNow(context: string, kana: string, max: number): KkcResult {
    if (!AiConverter.ready || kana.length === 0) {
      return { cands: [], ends: [], lens: [], waitMs: 0, runMs: 0, deliverMs: 0 } as KkcResult;
    }
    const r = kkc.convert(context, kana, max);
    return { cands: r.cands, ends: r.ends, lens: r.lens, waitMs: 0, runMs: 0, deliverMs: 0 } as KkcResult;
  }

  // AI 変換がこの読みからこの表記を出せるか (文脈なしで上位 30 個に入るか)。未知語の学習 (UnknownWordLearner) が、
  // 単漢字を組み立てて作った語が「変換で出せない語」かを確かめるのに使う
  static canProduce(reading: string, surface: string): boolean {
    return AiConverter.convertNow('', reading, 30).cands.indexOf(surface) >= 0;
  }

  // ユーザー辞書。登録した語を辞書の語と同じく変換の網に入れ、モデルが文脈で採点する
  // (読みが文の途中に出てきても候補になる)。品詞の左右 ID とコストは、辞書にある同じ品詞・同じ活用の形の代表語から写す
  // (Android 版 UserDict.kt・PC 版と同じ決まり)。動詞と形容詞は、代表語の活用形と同じ語尾の形も作って入れる
  private static userForms: string[] = [];   // [読み, 表記, 代表語の読み, 代表語の表記] を 4 つずつ
  private static readonly USER_BONUS: number = 800;
  private static readonly NOUN_TMPL: Record<string, string[]> = {
    'noun': ['ねこ', '猫'], 'person': ['やまだ', '山田'], 'place': ['とうきょう', '東京'],
  };
  // 五段: 終止形の最後のかな -> [代表語の読み, 代表語の表記, 活用の語尾 (未然・連用・終止・仮定・意志・音便)]
  private static readonly GODAN: Record<string, string[]> = {
    'う': ['かう', '買う', 'わいうえおっ'], 'く': ['かく', '書く', 'かきくけこい'], 'ぐ': ['およぐ', '泳ぐ', 'がぎぐげごい'],
    'す': ['はなす', '話す', 'さしすせそ'], 'つ': ['まつ', '待つ', 'たちつてとっ'], 'ぬ': ['しぬ', '死ぬ', 'なにぬねのん'],
    'ぶ': ['あそぶ', '遊ぶ', 'ばびぶべぼん'], 'む': ['よむ', '読む', 'まみむめもん'], 'る': ['はしる', '走る', 'らりるれろっ'],
  };
  private static readonly ICHIDAN: string[] = ['', 'る', 'れ', 'ろ', 'よ'];   // 代表語 食べる
  private static readonly ADJ: string[] = ['い', 'く', 'かっ', 'けれ', 'かろ', 'き', 'さ', 'そう'];   // 代表語 高い

  // dict = 読み -> 表記 (UserDictStore)、pos = 「読み	表記」-> 品詞 (UserPosStore。無ければ名詞)
  static setUserDict(dict: Record<string, string[]>, pos: Record<string, UserPosEntry>): void {
    const out: string[] = [];
    const stem = (r: string, w: string, tr: string, ts: string, sufs: string[]): void => {
      for (const x of sufs) {
        out.push(r.slice(0, -1) + x, w.slice(0, -1) + x, tr.slice(0, -1) + x, ts.slice(0, -1) + x);
      }
    };
    if (!dict) {
      dict = {} as Record<string, string[]>;
    }
    for (const r of Object.keys(dict)) {
      const words = dict[r];
      if (!Array.isArray(words)) {
        continue;
      }
      for (const w of words) {
        if (typeof w !== 'string' || w.length === 0 || r.length === 0) {
          continue;
        }
        const e: UserPosEntry | undefined = pos ? pos[r + '	' + w] : undefined;
        const kind: string = e && typeof e === 'object' ? String(e.pos) : 'noun';
        const last = r.charAt(r.length - 1);
        if (kind === 'verb') {
          const group = e?.group ?? (last === 'る' ? undefined : 'godan');
          if (group === 'ichidan' && r.endsWith('る') && w.endsWith('る')) {
            stem(r, w, 'たべる', '食べる', AiConverter.ICHIDAN);
          } else if (group === 'godan' && AiConverter.GODAN[last] !== undefined && w.endsWith(last)) {
            const g = AiConverter.GODAN[last];
            stem(r, w, g[0], g[1], g[2].split(''));
          }
        } else if (kind === 'adjective') {
          if (r.endsWith('い') && w.endsWith('い')) {
            stem(r, w, 'たかい', '高い', AiConverter.ADJ);
          }
        } else {
          const t = AiConverter.NOUN_TMPL[kind] ?? AiConverter.NOUN_TMPL['noun'];
          out.push(r, w, t[0], t[1]);
        }
      }
    }
    AiConverter.userForms = out;
    AiConverter.applyUserWords();
  }

  private static applyUserWords(): void {
    if (!AiConverter.ready) {
      return;
    }
    const n = kkc.setUserWords(AiConverter.userForms, AiConverter.USER_BONUS);
    AiConverter.cache.clear();   // 前の辞書で変換した結果を使わない
    console.info(`shuntiIME AiConverter user words ${n}/${AiConverter.userForms.length / 4}`);
  }

  // 挨拶はかな書きを先に。モデルは文脈によって「こんにちは」を「今日は」と書く (教材の読みの入れ替え
  // 「今日 → こんにち」の副作用。次の学習で直す)。こんにちは は読みのどこにあっても (きょうは も打っていなければ)、
  // こんばんは は読みがそれだけのとき (今晩は寒い があるので)、1 位の「今日は」「今晩は」をかな書きに直した候補を 1 位に置く
  static preferGreetings(target: string, cands: string[]): string[] {
    if (cands.length === 0) {
      return cands;
    }
    const top = cands[0];
    const bare = target.replace(/[、。！？!?ー〜]+$/, '');
    let kanji = '';
    let kana = '';
    if (target.indexOf('こんにちは') >= 0 && target.indexOf('きょうは') < 0 && top.indexOf('今日は') >= 0) {
      kanji = '今日は';
      kana = 'こんにちは';
    } else if (bare === 'こんばんは' && top.indexOf('今晩は') >= 0) {
      kanji = '今晩は';
      kana = 'こんばんは';
    }
    if (kanji.length === 0) {
      return cands;
    }
    const fixed = top.split(kanji).join(kana);
    return [fixed, ...cands.filter((c: string) => c !== fixed)];
  }

  // 読み reading とその表記 surf の組で、挨拶の「今日は」をかな書きに直す (きょうは を打っていないときだけ)
  private static greetingFix(reading: string, surf: string): string {
    if (reading.indexOf('こんにちは') >= 0 && reading.indexOf('きょうは') < 0) {
      return surf.split('今日は').join('こんにちは');
    }
    return surf;
  }

  // ---- 長い入力: 前の方を固定して、後ろだけを変換する ----
  // 変換 1 回が BUDGET_MS を超えて遅れを感じる長さになったら、1 位の候補の語の区切りのうち、最後の KEEP_WORDS 語より前にあって、
  // 2 回続けて同じ変換になったところ (または「、」「。」の後ろ) までを固定する。それより短いうちは文全体に AI をかけ続ける。
  // 固定した部分は文脈としてモデルに渡すので、後ろの変換の質は落ちない。
  // 固定した読みまで消して戻ったら・確定して文脈が変わったら、固定を解く。
  //
  // 固定した部分は入力欄に確定しない (以前は確定していて、間違っていたら直せずストレスだった)。
  // 代わりに、固定した時点でその部分だけを 1 回変換して上位 ALT 個の候補を持たせ、以後は AI にかけない。
  // 候補の一覧には「後ろだけ AI の候補を替えた文」に加えて「前の方を持たせた候補に替えた文」も並べ、そこから確定できる。
  private static KEEP_WORDS: number = 4;     // 固定しても、最後のこの語数は必ず AI に残す
  private static BUDGET_MS: number = 80;     // 変換 1 回がこれより速いうちは固定しない (遅れを感じない限界)
  private static MAX_TAIL: number = 60;
  // 変換で受け取る候補の数。10 では短い読み (き・かん) の単漢字が足りない (期・季・記が 11 位より後ろにある)
  private static CANDIDATES: number = 30;
  private static ALT: number = 4;
  private static chunks: FrozenChunk[] = [];   // 固定した部分 (前から順に)。表記は cands[0]
  private static fCtx: string = '';      // 固定を始めたときの文脈
  private static fKana: string = '';     // 固定した読み (chunks の読みをつないだもの)
  private static fSurf: string = '';     // 固定した表記 (chunks の cands[0] をつないだもの)
  private static prevSegs: Map<number, string> = new Map<number, string>();   // 前回の結果の (区切りの位置 -> そこまでの表記)
  private static lastTarget: string = '';  // 最後に出した読みと、その候補 (結果を待つ間の表示に使う)
  private static lastTop: string = '';
  private static lastCands: string[] = [];

  // 読みの全体 target の候補 (固定した部分を前に付けた文)。変換がまだ届いていなければ、裏で変換を頼み、
  // 前回の 1 位 + 新しく打ったかな を仮に返す (届いたら onDone で出し直す)
  static candidates(context: string, target: string, onDone: () => void): string[] {
    if (AiConverter.fCtx !== context || !target.startsWith(AiConverter.fKana)) {
      AiConverter.fCtx = context;
      AiConverter.fKana = '';
      AiConverter.fSurf = '';
      AiConverter.chunks = [];
      AiConverter.prevSegs.clear();
    }
    const tail = target.slice(AiConverter.fKana.length);
    if (tail.length === 0) {
      return [AiConverter.fSurf];
    }
    const ctx2 = (context + AiConverter.fSurf).slice(-40);
    const hit = AiConverter.cache.get(AiConverter.key(ctx2, tail));
    if (hit !== undefined && hit.cands.length > 0) {
      const out = AiConverter.withFrozenAlternatives(hit.cands.map((c: string) => AiConverter.fSurf + c), hit.cands[0]);
      AiConverter.lastTarget = target;
      AiConverter.lastTop = out[0];
      AiConverter.lastCands = out;
      AiConverter.setSuggestion(hit, out.length > 0 ? out[0] : '');
      AiConverter.maybeFreeze(tail, hit);
      return out;
    }
    AiConverter.request(ctx2, tail, onDone);
    // 結果が届くまでは、前回の候補に新しく打ったかなをつないで出す (かなに戻ったり、候補の帯が縮んだりしない)
    if (AiConverter.lastTarget.length > 0 && target.startsWith(AiConverter.lastTarget) && AiConverter.lastCands.length > 0) {
      const extra = target.slice(AiConverter.lastTarget.length);
      return AiConverter.lastCands.map((c: string) => c + extra);
    }
    return [AiConverter.fSurf + tail];
  }

  // オート確定のとき: 固定した読みと表記 (呼ぶ側がこれを入力欄に確定して、残りだけを入力中に残す)
  static frozenKana(): string {
    return AiConverter.fKana;
  }

  static frozenSurf(): string {
    return AiConverter.fSurf;
  }

  // 固定した部分 (読み fk、表記 fs) を確定したあと。前回の候補も、確定した分だけ前を削って残す
  // (消してしまうと、次の結果が届くまで残りがかなで出てちらつく)
  static clearFrozen(fk: string = '', fs: string = ''): void {
    AiConverter.fKana = '';
    AiConverter.fSurf = '';
    AiConverter.chunks = [];
    AiConverter.prevSegs.clear();
    if (fk.length > 0 && AiConverter.lastTarget.startsWith(fk)) {
      AiConverter.lastTarget = AiConverter.lastTarget.slice(fk.length);
      AiConverter.lastCands = AiConverter.lastCands.filter((c: string) => c.startsWith(fs)).map((c: string) => c.slice(fs.length));
      AiConverter.lastTop = AiConverter.lastCands.length > 0 ? AiConverter.lastCands[0] : '';
    } else {
      AiConverter.lastTarget = '';
      AiConverter.lastTop = '';
      AiConverter.lastCands = [];
    }
  }

  // 候補の一覧: AI の上位 3 つ (前の方は固定したまま) → 前の方の 1 か所を持たせた候補に替えた文 (後ろは AI の 1 位)
  // → AI の残り。前の方を替えた文は、後ろの方の固定ほど先に (直したいのは、たいてい直前に固定された所)
  private static withFrozenAlternatives(full: string[], tailTop: string): string[] {
    const chunks = AiConverter.chunks;
    if (chunks.length === 0) {
      return full;
    }
    const variants: string[] = [];
    for (let i = chunks.length - 1; i >= 0 && variants.length < 8; i--) {
      for (let j = 1; j < chunks[i].cands.length; j++) {
        variants.push(chunks.map((c: FrozenChunk, idx: number) => idx === i ? c.cands[j] : c.cands[0]).join('') + tailTop);
      }
    }
    const out: string[] = [];
    for (const c of full.slice(0, 3).concat(variants, full.slice(3))) {
      if (out.indexOf(c) < 0) {
        out.push(c);
      }
    }
    return out;
  }

  private static maybeFreeze(tail: string, r: KkcResult): void {
    const top = r.cands[0];
    let cum = 0;
    let freezeEnd = 0;
    let freezeLen = 0;
    const segs = new Map<number, string>();
    for (let i = 0; i < r.ends.length - 1; i++) {   // 最後の語は固定しない
      cum += r.lens[i];
      const end = r.ends[i];
      const surf = top.slice(0, cum);
      segs.set(end, surf);
      const punct = '、。！？!?'.indexOf(tail.charAt(end - 1)) >= 0;
      const stable = AiConverter.prevSegs.get(end) === surf;
      const wordsAfter = r.ends.length - 1 - i;   // この語より後ろに残る語の数
      // 速くても、読みが長すぎるとモデルの入力の長さの上限に届いて変換できなくなるので、MAX_TAIL 字を超えたら固定する
      const slow = AiConverter.lastRunMs > AiConverter.BUDGET_MS || tail.length > AiConverter.MAX_TAIL;
      const ready = slow && wordsAfter >= AiConverter.KEEP_WORDS;
      if (ready && (stable || punct)) {
        freezeEnd = end;
        freezeLen = cum;
      }
    }
    AiConverter.prevSegs = segs;
    if (freezeEnd > 0) {
      const kana = tail.slice(0, freezeEnd);
      // 固定する前の方にも、挨拶のかな書きを当てる (候補の並べ替えだけでは、ここで「今日は」が固定されてしまう)
      const surf = AiConverter.greetingFix(kana, top.slice(0, freezeLen));
      const chunk: FrozenChunk = { kana: kana, cands: [surf] };
      const ctx = (AiConverter.fCtx + AiConverter.fSurf).slice(-40);
      AiConverter.chunks.push(chunk);
      AiConverter.fKana += kana;
      AiConverter.fSurf += surf;
      AiConverter.prevSegs.clear();
      // 固定した部分だけを 1 回変換して、選び直せる候補を持たせる (以後この部分は AI にかけない)
      kkc.convertAsync(ctx, kana, 8).then((r2: KkcResult) => {
        const alts = r2.cands.filter((c: string) => c !== surf);
        chunk.cands = [surf].concat(alts.slice(0, AiConverter.ALT - 1));
      }).catch((_e: Error) => {});
    }
  }

  // ---- 裏のスレッドでの変換 ----
  private static cache: Map<string, KkcResult> = new Map<string, KkcResult>();
  private static inflight: boolean = false;
  private static wantKey: string = '';
  private static wantCtx: string = '';
  private static wantKana: string = '';
  private static wantCb: () => void = () => {};

  private static key(context: string, kana: string): string {
    return context + '|' + kana;
  }

  // 変換中にまた頼まれたら、終わったあとで最新の 1 つだけを変換する (古い読みの変換を溜めない)
  private static request(context: string, kana: string, onDone: () => void): void {
    AiConverter.wantKey = AiConverter.key(context, kana);
    AiConverter.wantCtx = context;
    AiConverter.wantKana = kana;
    AiConverter.wantCb = onDone;
    if (!AiConverter.inflight) {
      AiConverter.run();
    }
  }

  // 設定「提案を分けて表示する」。前の結果は提案の有無が違うので捨てる
  static setSuggestMode(on: boolean): void {
    kkc.setSuggest(on);
    AiConverter.cache.clear();
  }

  // 提案 (候補の帯に出す。CandidateBar の suggestList): 固定した表記 + 提案。無ければ消す
  private static setSuggestion(r: KkcResult, top: string): void {
    if ((AppStorage.get<string>('composingText') ?? '').length === 0) {   // 確定した後に届いた結果
      AiConverter.clearSuggestion();
      return;
    }
    const s = r.sugg ?? [];
    const k = r.suggKinds ?? [];
    const list: string[] = [];
    const kinds: number[] = [];
    let typoTop = '';
    const after: string[] = [];
    for (let i = 0; i < s.length; i++) {
      if (i < k.length && k[i] === 8) { typoTop = AiConverter.fSurf + s[i]; continue; }   // 1 位にした打ち間違いの直し
      if (i < k.length && k[i] === 9) { after.push(s[i]); continue; }   // 確定の後に出す絵文字・顔文字
      // 気分の絵文字・顔文字 (6) は絵文字だけが来るので 1 位の後ろに (帯には足す分だけ見せる)
      const t = (i < k.length && k[i] === 6) ? top + s[i] : AiConverter.fSurf + s[i];
      if (t !== top && list.indexOf(t) < 0) {
        list.push(t);
        kinds.push(i < k.length ? k[i] : 0);
      }
    }
    // 括弧の組が提案に回っているとき (かっこ など)、エンジンの辞書に無い組 (【】・"" …、Brackets.ets) も提案に揃える。
    // 揃えないと、候補の側で足した組だけが候補の帯に残っていた (ユーザー 2026-10-13)
    if (kinds.indexOf(7) >= 0) {
      for (const b of bracketVariants(AiConverter.lastTarget)) {
        if (list.indexOf(b) < 0) { list.push(b); kinds.push(7); }
      }
    }
    // 選んだことのある提案を、同じ種類の中で前に (括弧は人によって使う組が違う。ユーザー 2026-10-13)
    const firstOfKind = (kd: number): number => kinds.indexOf(kd);
    const order: number[] = list.map((_t: string, i: number) => i);
    order.sort((x: number, y: number) => {
      const gx = firstOfKind(kinds[x]);
      const gy = firstOfKind(kinds[y]);
      if (gx !== gy) { return gx - gy; }
      const d = (AiConverter.suggUse[list[y]] ?? 0) - (AiConverter.suggUse[list[x]] ?? 0);
      return d !== 0 ? d : x - y;
    });
    const sl = order.map((i: number) => list[i]);
    const sk = order.map((i: number) => kinds[i]);
    list.splice(0, list.length, ...sl);
    kinds.splice(0, kinds.length, ...sk);
    AppStorage.setOrCreate('typoTop', typoTop);
    AiConverter.afterEmoji = after;   // 候補の帯でこの候補を “ ” で囲む
    // 候補の帯から外す判定 (suggestPending) と帯に出すのは同時
    AppStorage.setOrCreate('suggestPending', list);
    AppStorage.setOrCreate('suggestPendingKinds', kinds);
    const key = list.join('\u0001') + '\u0002' + top;
    if (key === AiConverter.suggestKey) { return; }
    AiConverter.suggestKey = key;
    clearTimeout(AiConverter.suggestTimer);
    const show = () => {
      AppStorage.setOrCreate('suggestList', list);
      AppStorage.setOrCreate('suggestKinds', kinds);
      AppStorage.setOrCreate('suggestFrom', top);
    };
    // 提案は候補の帯の中に出すようになったので、待たずにすぐ出す (ユーザー 2026-10-13「0.2 秒の遅延はもういらない」)
    show();
  }

  // 確定・取り消しで入力中の文字が無くなった: 待っている提案を捨てて帯を空にする。変換の結果が確定の後から届いたり、
  // 0.2 秒待ちの提案が確定の後に出たりして、提案が残った (ユーザー 2026-10-13「変換なしで確定した後も候補が消えない」)
  static clearSuggestion(): void {
    clearTimeout(AiConverter.suggestTimer);
    AiConverter.suggestKey = '';
    AppStorage.setOrCreate('suggestPending', [] as string[]);
    AppStorage.setOrCreate('suggestPendingKinds', [] as number[]);
    AppStorage.setOrCreate('suggestList', [] as string[]);
    AppStorage.setOrCreate('typoTop', '');
  }

  // 提案を選んだ回数 (表記 -> 回数)。端末の中だけに保存する (KeyboardController が shunti_flow の 'sugg' に)
  static suggUse: Record<string, number> = {};
  static onSuggUse: (() => void) | undefined = undefined;

  static recordSuggestUse(t: string): void {
    AiConverter.suggUse[t] = (AiConverter.suggUse[t] ?? 0) + 1;
    AiConverter.suggestKey = '';
    AiConverter.onSuggUse?.();
  }

  // 1 位の文の語に当たる絵文字・顔文字 (エンジンの種類 9)。確定の後の予測の帯に出す (takeAfterEmoji)
  private static afterEmoji: string[] = [];

  static takeAfterEmoji(): string[] {
    const a = AiConverter.afterEmoji;
    AiConverter.afterEmoji = [];
    return a;
  }

  private static suggestKey: string = '';
  private static suggestTimer: number = -1;

  private static run(): void {
    AiConverter.inflight = true;
    const key = AiConverter.wantKey;
    const ctx = AiConverter.wantCtx;
    const kana = AiConverter.wantKana;
    const cb = AiConverter.wantCb;
    const t0 = Date.now();
    kkc.convertAsync(ctx, kana, AiConverter.CANDIDATES).then((r: KkcResult) => {
      AiConverter.lastMs = Date.now() - t0;
      AiConverter.lastRunMs = r.runMs;
      if (DEBUG_INPUT_LOG) {   // 変換 1 回の時間の内訳 (開発版のログだけ)
        const tt: number[] = kkc.times();
        console.info(`shuntiIME AiConverter ${kana.length}字 全体 ${AiConverter.lastMs}ms = 順番待ち ${r.waitMs.toFixed(0)} + 変換 ${r.runMs.toFixed(0)} + 受け取り ${r.deliverMs.toFixed(0)} [${tt.map((x: number) => x.toFixed(1)).join(' ')}]`);
      }
      if (AiConverter.cache.size > 256) {
        AiConverter.cache.clear();
      }
      AiConverter.cache.set(key, { cands: r.cands, ends: r.ends, lens: r.lens,
        sugg: r.sugg ?? [], suggKinds: r.suggKinds ?? [] } as KkcResult);
      AiConverter.inflight = false;
      if (AiConverter.wantKey !== key) {
        AiConverter.run();      // 変換中に読みが変わった: 最新の読みを変換する
      } else {
        cb();
      }
    }).catch((e: Error) => {
      AiConverter.inflight = false;
      console.error('shuntiIME AiConverter convert error', JSON.stringify(e));
    });
  }
}
