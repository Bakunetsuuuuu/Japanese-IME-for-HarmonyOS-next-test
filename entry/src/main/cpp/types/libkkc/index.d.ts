// libkkc.so (napi_kkc.cpp) の型。entry/src/main/cpp/types/libkkc/index.d.ts に置く
import resourceManager from '@ohos.resourceManager';

/** 初回だけ: rawfile の kkc_lex.bin / kkc_model.bin を dir へ写す (同じ大きさなら何もしない) */
export const prepare: (resMgr: resourceManager.ResourceManager, dir: string) => boolean;
/** 写す + 開くを裏のスレッドで (初回は 100MB 超を写す) */
export const loadAsync: (resMgr: resourceManager.ResourceManager, dir: string, threads: number) => Promise<boolean>;
/** dir の kkc_lex.bin / kkc_model.bin を mmap して開く */
export const open: (dir: string, threads: number) => boolean;
/** 変換 (呼んだスレッドで。候補の配列) */
export const convert: (ctx: string, kana: string, max: number) => string[];
/** 変換の結果: 候補と、1 位の候補の語の区切り (ends[i] = i 語目の読みの終わり、lens[i] = 表記の長さ) */
export interface KkcResult {
  cands: string[];
  ends: number[];
  lens: number[];
  /** 待ち時間の内訳 (ms): 裏のスレッドの順番待ち / 変換 / 変換が終わってから JS に届くまで */
  waitMs: number;
  runMs: number;
  deliverMs: number;
}
/** 変換 (裏のスレッドで。UI を止めない) */
export const convertAsync: (ctx: string, kana: string, max: number) => Promise<KkcResult>;
/** 直前の変換の時間の内訳 (ms): [網, 下書き, エンコーダ, 区間と語, 上位k] */
export const times: () => number[];
export const close: () => boolean;
