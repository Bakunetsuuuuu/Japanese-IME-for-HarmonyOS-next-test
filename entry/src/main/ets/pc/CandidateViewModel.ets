// 候補ウィンドウに何を出すか。窓の大きさを決める PcModeController と、
// 中身を描く PcCandidateWindow の両方がこれを使う (別々に決めると、窓と
// 中身の行数がずれる)。
import { InputState } from '../ime/KeyboardController';
import {
  CANDIDATE_PAGE_SIZE, CAND_LIVE_MAX, CAND_MARGIN_VP, CAND_PAD_VP, CAND_ROW_H_VP, CAND_HEADER_H_VP, CAND_FOOTER_H_VP,
  CAND_NUMBER_W_VP, CAND_FONT_FP, CAND_MIN_W_VP, CAND_MAX_W_VP, estimateTextWidthVp
} from './PcStyle';

export interface CandidateViewModel {
  visible: boolean;
  // 読みの行 ('' = 出さない)。入力欄が下線付きの表示に対応していないときだけ
  header: string;
  // 読みの行の中のカーソルの位置 (header の何文字目の前か)。-1 = カーソルを出さない
  headerCaret: number;
  rows: string[];
  // rows[0] が candidates の何番目か
  firstIndex: number;
  // 選んでいる行 (-1 = 選んでいない。入力中は選ばずに見せるだけ)
  selectedRow: number;
  // 1〜9 の番号を出すか (変換中だけ。入力中に数字を打つと数字が入る)
  numbered: boolean;
  page: number;
  pageCount: number;
}

// reading は打ちかけのローマ字を含む読み、caret はその中のカーソルの位置 (-1 = 末尾)。
// 読みの途中にカーソルがあるときは、入力欄に下線付きで出せていても読みの行を出す
// (入力欄の表示は途中のカーソルの位置を指定できないので、ここで見せる)
export function buildCandidateView(state: string, candidates: string[], selectedIndex: number,
    previewInField: boolean, reading: string, bunsetsuDisplay: string, caret: number): CandidateViewModel {
  const empty: CandidateViewModel = {
    visible: false, header: '', headerCaret: -1, rows: [], firstIndex: 0, selectedRow: -1, numbered: false,
    page: 0, pageCount: 0,
  };
  if (state === InputState.IDLE) { return empty; }
  let header = '';
  let headerCaret = -1;
  if (state === InputState.COMPOSING && caret >= 0) {
    header = reading;
    headerCaret = caret;
  } else if (!previewInField) {
    header = (state === InputState.BUNSETSU && bunsetsuDisplay.length > 0) ? bunsetsuDisplay : reading;
  }
  if (state === InputState.COMPOSING) {
    const rows = candidates.slice(0, CAND_LIVE_MAX);
    return {
      visible: rows.length > 0 || header.length > 0,
      header: header, headerCaret: headerCaret, rows: rows, firstIndex: 0, selectedRow: -1, numbered: false,
      page: 0, pageCount: rows.length > 0 ? 1 : 0,
    };
  }
  // SELECTING / BUNSETSU
  const sel = Math.max(0, Math.min(candidates.length - 1, selectedIndex));
  const page = Math.floor(sel / CANDIDATE_PAGE_SIZE);
  const first = page * CANDIDATE_PAGE_SIZE;
  const rows = candidates.slice(first, first + CANDIDATE_PAGE_SIZE);
  return {
    visible: rows.length > 0 || header.length > 0,
    header: header,
    headerCaret: -1,
    rows: rows,
    firstIndex: first,
    selectedRow: rows.length > 0 ? sel - first : -1,
    numbered: true,
    page: page,
    pageCount: Math.ceil(candidates.length / CANDIDATE_PAGE_SIZE),
  };
}

export interface SizeVp {
  w: number;
  h: number;
}

// 窓 (影の余白込み) の大きさ。PcCandidateWindow の並べ方と同じ足し算。
export function candidateWindowSizeVp(vm: CandidateViewModel): SizeVp {
  let contentW = 0;
  for (const r of vm.rows) {
    contentW = Math.max(contentW, estimateTextWidthVp(r, CAND_FONT_FP));
  }
  contentW += CAND_NUMBER_W_VP + 24;
  if (vm.header.length > 0) {
    contentW = Math.max(contentW, estimateTextWidthVp(vm.header, CAND_FONT_FP) + 24);
  }
  // 枠線 (1vp) は中身の領域を内側へ削るので、そのぶん足す
  const bodyW = Math.max(CAND_MIN_W_VP, Math.min(CAND_MAX_W_VP, contentW)) + 2;
  let bodyH = CAND_PAD_VP * 2 + 2 + vm.rows.length * CAND_ROW_H_VP;
  if (vm.header.length > 0) { bodyH += CAND_HEADER_H_VP; }
  if (vm.pageCount > 1) { bodyH += CAND_FOOTER_H_VP; }
  return { w: bodyW + CAND_MARGIN_VP * 2, h: bodyH + CAND_MARGIN_VP * 2 };
}

// AppStorage の今の値から作る (PcModeController 用。画面側は @StorageLink の値を渡す)
export function currentCandidateView(): CandidateViewModel {
  const composing = AppStorage.get<string>('composingText') ?? '';
  const pending = AppStorage.get<string>('pendingRomaji') ?? '';
  const caret = AppStorage.get<number>('composingCaret') ?? -1;
  return buildCandidateView(
    AppStorage.get<string>('inputState') ?? InputState.IDLE,
    AppStorage.get<string[]>('candidates') ?? [],
    AppStorage.get<number>('selectedCandidateIndex') ?? 0,
    AppStorage.get<boolean>('previewInField') ?? false,
    readingWithCaret(composing, pending, caret),
    AppStorage.get<string>('bunsetsuDisplay') ?? '',
    caretInReading(composing, pending, caret));
}

// 読み + 打ちかけのローマ字 (カーソルの位置に)。InputHandler.readingWithPending と同じ並べ方
export function readingWithCaret(composing: string, pending: string, caret: number): string {
  const at = caret < 0 ? composing.length : Math.min(caret, composing.length);
  return composing.slice(0, at) + pending + composing.slice(at);
}

// その中のカーソルの位置 (打ちかけのローマ字の後ろ)。-1 = 末尾 (出さない)
export function caretInReading(composing: string, pending: string, caret: number): number {
  if (caret < 0 || caret >= composing.length) { return -1; }
  return caret + pending.length;
}
