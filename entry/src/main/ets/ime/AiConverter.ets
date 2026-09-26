// AI 変換 (shuntelligence)。変換エンジンの 3 つ目の選択肢 (conversionEngine = 'ai')。
// 中身は C++ (entry/src/main/cpp, libkkc.so): 辞書 shuntorge の単語の網 + 文脈を読む小さな Transformer (約 630 万
// パラメータ) + 上位 k。学習のコードと教材は公開していない (モデルの重みと推論のコードだけを同梱)。
// 辞書とモデル (rawfile の kkc_lex.bin / kkc_model.bin、合わせて約 120MB) は初回だけ filesDir に写し、
// 以降は mmap して使う (ArkTS の heap には載せない)。
import kkc, { KkcResult } from 'libkkc.so';
import type common from '@ohos.app.ability.common';
import { DEBUG_INPUT_LOG } from './InputLog';

export class AiConverter {
  private static ready: boolean = false;
  private static loading: boolean = false;
  private static failed: boolean = false;
  static lastMs: number = 0;

  static isReady(): boolean {
    return AiConverter.ready;
  }

  static hasFailed(): boolean {
    return AiConverter.failed;
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
      }
    }).catch((e: Error) => {
      AiConverter.loading = false;
      AiConverter.failed = true;
      console.error('shuntiIME AiConverter load error', JSON.stringify(e));
      onFail();
    });
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
  // 1 位の候補の語の区切りのうち、末尾から KEEP 字より前にあって、2 回続けて同じ変換になったところ
  // (または「、」「。」の後ろ) までを固定する。固定した部分は文脈としてモデルに渡すので、後ろの変換の質は落ちない。
  // 固定した読みまで消して戻ったら・確定して文脈が変わったら、固定を解く。
  private static KEEP: number = 8;
  private static fCtx: string = '';      // 固定を始めたときの文脈
  private static fKana: string = '';     // 固定した読み
  private static fSurf: string = '';     // 固定した表記
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
      AiConverter.prevSegs.clear();
    }
    const tail = target.slice(AiConverter.fKana.length);
    if (tail.length === 0) {
      return [AiConverter.fSurf];
    }
    const ctx2 = (context + AiConverter.fSurf).slice(-40);
    const hit = AiConverter.cache.get(AiConverter.key(ctx2, tail));
    if (hit !== undefined && hit.cands.length > 0) {
      const out = hit.cands.map((c: string) => AiConverter.fSurf + c);
      AiConverter.lastTarget = target;
      AiConverter.lastTop = out[0];
      AiConverter.lastCands = out;
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

  // 固定した読みと表記 (呼ぶ側がこれを入力欄に確定して、残りだけを入力中に残す)
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
      if (end <= tail.length - AiConverter.KEEP && (stable || punct)) {
        freezeEnd = end;
        freezeLen = cum;
      }
    }
    AiConverter.prevSegs = segs;
    if (freezeEnd > 0) {
      AiConverter.fKana += tail.slice(0, freezeEnd);
      // 固定して確定する前の方にも、挨拶のかな書きを当てる (候補の並べ替えだけでは、ここで「今日は」が確定されてしまう)
      AiConverter.fSurf += AiConverter.greetingFix(tail.slice(0, freezeEnd), top.slice(0, freezeLen));
      AiConverter.prevSegs.clear();
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

  private static run(): void {
    AiConverter.inflight = true;
    const key = AiConverter.wantKey;
    const ctx = AiConverter.wantCtx;
    const kana = AiConverter.wantKana;
    const cb = AiConverter.wantCb;
    const t0 = Date.now();
    kkc.convertAsync(ctx, kana, 10).then((r: KkcResult) => {
      AiConverter.lastMs = Date.now() - t0;
      if (DEBUG_INPUT_LOG) {   // 変換 1 回の時間の内訳 (開発版のログだけ)
        const tt: number[] = kkc.times();
        console.info(`shuntiIME AiConverter ${kana.length}字 全体 ${AiConverter.lastMs}ms = 順番待ち ${r.waitMs.toFixed(0)} + 変換 ${r.runMs.toFixed(0)} + 受け取り ${r.deliverMs.toFixed(0)} [${tt.map((x: number) => x.toFixed(1)).join(' ')}]`);
      }
      if (AiConverter.cache.size > 256) {
        AiConverter.cache.clear();
      }
      const cands = r.cands.filter((c: string) => !AiConverter.SLURS.test(c));
      // 差別語で 1 位が落ちたら区切りは使えない (1 位の区切りなので)
      const ok = cands.length > 0 && cands[0] === r.cands[0];
      AiConverter.cache.set(key, { cands: cands, ends: ok ? r.ends : [], lens: ok ? r.lens : [] } as KkcResult);
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

  // 語をつないで差別語になった候補を出さない (学習側 kkc/content_filter.SLURS と同じ)
  private static SLURS: RegExp = new RegExp('ガイジ|害児|池沼|キチガイ|きちがい|気違い|気狂い|基地外|キチゲェ|チョン(?!マゲ|ボ|チョン|ガー)|' +
    'チャンコロ|支那人|シナ人|土人|ニガー|ニガ―|黒んぼ|クロンボ|エタ非人|めくら|メクラ|つんぼ|ツンボ|知恵遅れ|片輪|かたわ|' +
    '三国人|ジャップ|鮮人|ホモガキ');
}
