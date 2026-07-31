// ===========================================================================
//  ★ デバッグ専用・入力ログ収集 / DEBUG-ONLY INPUT LOG COLLECTION ★
//  ★ このファイルはリリースビルドに含めないこと。                          ★
// ===========================================================================
//
// 変換の精度を実際の入力から測るための収集機構。実文コーパス(Tatoeba)は
// 「どこかの誰かの日本語」であって、この端末の持ち主が実際に打つ文の分布とは
// 別物になる。何番目の候補を選んだか・どこで文節を切り直したか・何を消したかを
// 記録して初めて、直すべき対象がこの端末の実入力から出てくる。
//
// ---------------------------------------------------------------------------
//  取り外し方 (RELEASE 前に必ず実施)
// ---------------------------------------------------------------------------
//  収集コードは全てこのファイルに閉じてあり、外部から呼ぶ箇所は必ず行末に
//  `// [DEBUG-LOG]` を付けてある。よって手順は以下だけ:
//
//    1. node tools/check_debug_log.js     … 収集地点を全部列挙する
//    2. `// [DEBUG-LOG]` の付いた行を全て削除する
//    3. このファイルと pages/InputLogPage.ets を削除する
//    4. main_pages.json から "pages/InputLogPage" を削除する
//    5. node tools/check_debug_log.js     … 0 件になったことを確認する
//
//  とりあえず無効化だけしたい場合は下の DEBUG_INPUT_LOG を false にする。
//  全ての record*() が即 return し、ファイルへの書き込みも画面の入口も消える
//  (ただしコードは残るのでリリース前には上の手順で削除すること)。
//
// ---------------------------------------------------------------------------
//  記録されるもの / されないもの
// ---------------------------------------------------------------------------
//  記録する: 読み(打鍵したかな) / 確定した表記 / 選んだ候補の番号 / 候補総数 /
//            カタカナ・英数変換だったか / 文節の区切り位置と選択 / 変換範囲の
//            変更 / 候補削除 / 未知語学習 / 削除した文字
//  記録しない: パスワード等の secure field (下の SECURE_PATTERNS)。
//            クリップボードの中身も対象外(privacy policy 上メモリ内のみ)。
//
//  保存先は端末内のアプリサンドボックス 1ファイルのみ。送信は一切しない。
//  エクスポートはユーザーが明示的に押したときだけ行う。
//
//  ★ 収集したログを git に入れないこと。private リポジトリでも同じ。
//     clone/バックアップ/コラボレータに渡り、履歴からは消せない。
// ===========================================================================

import fs from '@ohos.file.fs';

// 収集機構全体のスイッチ。false にすると全ての record*() が即 return し、
// 設定画面の入口も出なくなる。リリースビルドでは false ではなく「削除」。
export const DEBUG_INPUT_LOG: boolean = true;

// アプリサンドボックス内のログ本体 (filesDir 直下)。1行1レコードの JSONL に
// しているのは、追記だけで書けて壊れにくく、途中で切れても前半が読めるため。
export const INPUT_LOG_FILE: string = 'debug_input_log.jsonl';

// レコード種別。エクスポートした JSON をあとから分類するためのキーなので、
// 一度決めたら変えない(古いログと混ざると集計できなくなる)。
export const LK_COMMIT: string = 'commit';      // 候補を確定した
export const LK_RAW: string = 'raw';            // 変換せずかなのまま確定した
export const LK_RANGE: string = 'range';        // 変換範囲(◀▶)を変えた
export const LK_BUNSETSU: string = 'bunsetsu';  // 文節モードに入った(区切り位置)
export const LK_BSEG: string = 'bseg';          // 文節ごとに候補を選んだ
export const LK_DELCAND: string = 'delcand';    // 候補を削除した(長押し→削除)
export const LK_UNKNOWN: string = 'unknown';    // 未知語として学習された
export const LK_DELCHAR: string = 'delchar';    // 文字を消した(⌫)
export const LK_UNDO: string = 'undo';          // 取消で消した文字を戻した
export const LK_FIELD: string = 'field';        // 入力欄が変わった(診断用・本文なし)
export const LK_DIAG: string = 'diag';          // 拡張プロセスの自己申告(診断用・本文なし)

// 確定の性質を表す補助タグ (entry.x に入る)。
export const LF_KATAKANA: string = 'kata';      // 読みのカタカナ形をそのまま確定
export const LF_ALNUM: string = 'alnum';        // 英数に変換して確定
export const LF_KANA: string = 'kana';          // 読みと同じ(かな)を候補から確定

// EditorAttribute.inputPattern のうち収集対象外にするもの。パスワード系は
// 変換の研究データとして何の価値もない一方、書き出せるファイルに平文で残ると
// 事故にしかならないので、ユーザーが「全記録」を選んでいても常に除外する。
// (値は ArkUI の InputType と同じ並び。未知の値なら通常フィールド扱い=記録する)
const SECURE_PATTERNS: number[] = [7, 8, 9, 11];

// メモリに溜めてからまとめて書く。確定のたびに open/write/close すると
// 打鍵の応答に乗ってくるため。どちらか早い方で flush する。
//
// 書き出しは「確定」単位で走るのであって打鍵単位ではない(1秒に1回あるかどうか)。
// 溜めすぎると拡張プロセスが onDestroy を経ずに落とされたときの取りこぼしが
// 増えるだけなので、間隔は短めに取る。
const FLUSH_AT: number = 4;
const FLUSH_MS: number = 800;

// 属性が届くまでの保留の上限。ここに溜まり続けるのは属性が来ていない異常時
// だけなので、小さくてよい。
const MAX_PENDING: number = 64;

// ログ本体の上限。超えたら古い方を半分捨てて書き直す(消えるのは古い行だけで、
// 収集が止まることはない)。1レコード ~90B なので 2MB でおよそ 2万件。
const MAX_BYTES: number = 2 * 1024 * 1024;

// 1レコード。キーを1文字にしてあるのは、同じ内容を JSONL で持つとキー名が
// レコード数ぶん繰り返されてファイルの大半がキー名になるため。
export interface InputLogEntry {
  t: number;   // Date.now()
  k: string;   // 種別 (LK_*)
  r: string;   // 読み / 対象のかな
  s: string;   // 確定した表記 / 対象の文字列
  i: number;   // 選んだ候補の番号 (0始まり, 該当なしは -1)
  n: number;   // そのとき出ていた候補の総数 (該当なしは 0)
  x: string;   // 補助情報 (LF_*, 文節の区切り, 変換範囲 など)
}

export class InputLog {
  private static buffer: InputLogEntry[] = [];
  private static filesDir: string = '';
  private static timer: number = -1;
  // 現在のテキストフィールドが secure か。
  private static secureField: boolean = false;
  // フィールドの属性がまだ届いていない。getEditorAttribute() は非同期なので、
  // onInputStart 直後から属性が返るまでの間はどちらとも言えない期間がある。
  private static fieldPending: boolean = false;
  // その期間の記録の置き場。ここが最初の実装のバグで、属性が届くまでの記録を
  // 単に捨てていた ⇒ getEditorAttribute() が解決しないフィールドでは
  // 「1件も記録されない」が、画面上は「ログが空」としか見えなかった。
  // 捨てずに保留し、属性が届いた時点で secure なら破棄・そうでなければ採用する。
  private static pending: InputLogEntry[] = [];
  private static pendingDropped: number = 0;

  // 収集先ディレクトリを直接指定する(閲覧側や試験用)。書き込み側は
  // setWritableDir を使うこと ── パスが取れることと書けることは別なので。
  static setFilesDir(dir: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.filesDir = (dir === undefined || dir === null) ? '' : dir;
  }

  // 候補を順に「実際に開いて書けるか」試し、最初に成功したものを使う。
  //
  // 最初はアプリ単位の filesDir (/data/storage/el2/base/files) を無条件に
  // 使っていた。パス文字列は取れるので一見成功するが、拡張プロセスの
  // サンドボックスがそこに書けるとは限らない。そして flush() の
  // fs.openSync 失敗は握り潰されるので、ファイルが1つも作られないまま
  // 「ログ0件」としか見えなかった。書けるかどうかは仮定せず、実際に開いて
  // 確かめる。
  //
  // 順番はモジュール単位を先にする。拡張が確実に自分のものとして持っている
  // ディレクトリだから。読み手 (findDir) は両方見るので、どちらに落ちても届く。
  static setWritableDir(dirs: string[]): string {
    if (!DEBUG_INPUT_LOG) { return ''; }
    for (const d of dirs) {
      if (d === undefined || d === null || d.length === 0) { continue; }
      try {
        const file = fs.openSync(d + '/' + INPUT_LOG_FILE,
          fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
        fs.closeSync(file);
        InputLog.filesDir = d;
        return d;
      } catch (_e) {
        // 次の候補へ
      }
    }
    InputLog.filesDir = '';
    return '';
  }

  static path(): string {
    return InputLog.filesDir + '/' + INPUT_LOG_FILE;
  }

  // フィールドが変わった。属性が届くまでの記録は保留にする。
  static beginField(): void {
    if (!DEBUG_INPUT_LOG) { return; }
    // 前のフィールドの属性が最後まで来なかった場合、保留分は判断できないので
    // 捨てる(secure かもしれないため)。ただし黙って捨てず、件数を記録に残す。
    // 「収集は動いているが属性が取れていない」が画面から分かるようにするため。
    if (InputLog.pending.length > 0) {
      InputLog.pendingDropped += InputLog.pending.length;
      InputLog.pending = [];
      InputLog.write(LK_FIELD, '', '', -1, 0, `属性が届かず破棄 ${InputLog.pendingDropped}件`);
    }
    InputLog.flush();
    InputLog.fieldPending = true;
    InputLog.secureField = false;
  }

  // フィールドの属性が届いた。保留分をここで採否する。
  static setFieldPattern(pattern: number): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.secureField = SECURE_PATTERNS.indexOf(pattern) >= 0;
    InputLog.fieldPending = false;
    const held = InputLog.pending;
    InputLog.pending = [];
    if (!InputLog.secureField) {
      for (const e of held) { InputLog.buffer.push(e); }
    }
    // フィールドが始まったこと自体を1件残す。本文は入れない(secure でも安全)。
    // これがあると「ログが空」のとき、パスが違うのか(=この記録も無い)、
    // 収集の条件で落ちているのか(=この記録だけある)が一目で切り分けられる。
    InputLog.write(LK_FIELD, '', '', -1, 0,
      `pattern=${pattern}${InputLog.secureField ? ' (secure: 記録しない)' : ''}`);
  }

  // IME拡張が起動した。拡張プロセスが「自分はどこに書いているつもりか」を
  // 1件残す。
  //
  // 「削除した候補」も「入力ログ」も、拡張が書いたものを本体アプリが読む構造で、
  // どちらの読み取りも例外を握り潰して空を返す。つまり
  //   (a) 拡張が書けていない / (b) 書き先と読み先が違う / (c) そもそも記録が
  //   作られていない
  // のどれであっても、画面上は同じ「空」にしかならない。
  // 書き手の実パスをログに残しておけば、読み手側の実パスと突き合わせるだけで
  // (b) が一発で分かり、この記録自体が読めなければ (a) だと分かる。
  static recordPaths(source: string, logDir: string, filesDir: string, prefsDir: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.write(LK_DIAG, '', '', -1, 0,
      `log=${logDir} 起動元=${source} files=${filesDir} prefs=${prefsDir}`);
  }

  // パネル(KeyboardPage)からの保険。
  //
  // 本来の初期化は KeyboardController.setContext -> setupInputLog だが、
  // 「起動0回」= その経路が最後まで走っていない、という状態が実機で出た。
  // パネルの aboutToAppear は描画されている以上必ず走るので、そこからも
  // 初期化できるようにしておく。既に初期化済みなら何もしない。
  // どちらの経路で立ったかは 起動元= として記録に残るので、次に見たときに
  // setContext が走っているかどうかがそのまま分かる。
  static ensureFromPanel(filesDir: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    if (InputLog.filesDir.length > 0) { return; }
    const used = InputLog.setWritableDir([filesDir]);
    InputLog.recordPaths('panel(setContext未到達)',
      used.length > 0 ? used : '書き込めるディレクトリ無し', filesDir, '');
  }

  // 拡張プロセスの初期化に失敗した。永続化ストアが1つでも開けないと、
  // saveLearning/saveSuppressed 等が `if (!prefs) return` で黙って何もしなく
  // なる ── キーボードは普通に動くのに保存だけが全部死ぬ。理由をここに残す。
  // (この経路は preferences に依存しないので、preferences 自体が壊れていても
  //  記録が残る。それがこの記録の存在理由)
  static recordInit(store: string, e: ESObject): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.write(LK_DIAG, '', store, -1, 0, '初期化に失敗: ' + JSON.stringify(e));
  }

  // ---- 記録 API (呼び出し側は必ず行末に // [DEBUG-LOG] を付ける) ----------

  // 候補を確定した。index はタップした候補の番号、total はそのとき出ていた数。
  static recordCommit(reading: string, surface: string, index: number, total: number): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_COMMIT, reading, surface, index, total, InputLog.classify(reading, surface));
  }

  // 変換せずかなのまま確定した(無変換キー / pending の吐き出し)。
  static recordRaw(reading: string, surface: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_RAW, reading, surface, -1, 0, '');
  }

  // 変換範囲を ◀▶ で伸縮した。x は "変換する長さ/全体の長さ"。
  static recordRange(reading: string, end: number): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_RANGE, reading, reading.slice(0, end), -1, 0,
      `${end}/${reading.length}`);
  }

  // 文節モードに入った。x は変換器が切った区切り位置("わたしは|がっこうへ")。
  // 自動の区切りが気に入らないから文節モードに入る、という因果があるので、
  // ここで切り位置を残しておくと後続の bseg と突き合わせられる。
  static recordBunsetsu(reading: string, segs: string[]): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_BUNSETSU, reading, '', -1, 0, segs.join('|'));
  }

  // 文節モードで1つの文節の候補を選んだ。
  static recordBunsetsuPick(seg: string, surface: string, index: number, total: number): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_BSEG, seg, surface, index, total, InputLog.classify(seg, surface));
  }

  // 候補を削除した(長押し→削除)。「出てはいけない候補」の直接の証拠になる。
  static recordDeleteCandidate(reading: string, surface: string, index: number): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_DELCAND, reading, surface, index, 0, '');
  }

  // 未知語として学習された(辞書に無い語を手で組み立てた)。
  // 辞書に足すべき語がそのまま並ぶ。
  static recordUnknownWord(reading: string, surface: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_UNKNOWN, reading, surface, -1, 0, '');
  }

  // 文字を消した。x は消した時の状態(composing / idle)。確定後すぐの idle 削除は
  // 「確定した変換が間違っていた」の合図になるので、状態を分けて残す。
  static recordDeleteChar(ch: string, state: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_DELCHAR, '', ch, -1, 0, state);
  }

  static recordUndo(ch: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.push(LK_UNDO, '', ch, -1, 0, '');
  }

  // ---- 書き込み ---------------------------------------------------------

  private static push(k: string, r: string, s: string, i: number, n: number, x: string): void {
    if (InputLog.secureField) { return; }
    if (InputLog.filesDir.length === 0) { return; }
    const e: InputLogEntry = { t: Date.now(), k: k, r: r, s: s, i: i, n: n, x: x };
    // 属性待ちの間は保留に積む(捨てない)。上限を超えたら古い方から落とす。
    if (InputLog.fieldPending) {
      InputLog.pending.push(e);
      if (InputLog.pending.length > MAX_PENDING) { InputLog.pending.shift(); }
      return;
    }
    InputLog.buffer.push(e);
    if (InputLog.buffer.length >= FLUSH_AT) {
      InputLog.flush();
      return;
    }
    clearTimeout(InputLog.timer);
    InputLog.timer = setTimeout(() => { InputLog.flush(); }, FLUSH_MS);
  }

  // 保留を経由せず必ず書く。フィールドの開始など、本文を含まない診断用の記録に
  // だけ使う(secure かどうかに関わらず残したいもの)。
  private static write(k: string, r: string, s: string, i: number, n: number, x: string): void {
    if (InputLog.filesDir.length === 0) { return; }
    InputLog.buffer.push({ t: Date.now(), k: k, r: r, s: s, i: i, n: n, x: x });
    InputLog.flush();
  }

  // 溜めた分を追記する。フィールドを離れるときにも呼ぶ(取りこぼし防止)。
  static flush(): void {
    if (!DEBUG_INPUT_LOG) { return; }
    clearTimeout(InputLog.timer);
    const rows = InputLog.buffer;
    if (rows.length === 0 || InputLog.filesDir.length === 0) { return; }
    InputLog.buffer = [];
    let text = '';
    for (const e of rows) { text += JSON.stringify(e) + '\n'; }
    try {
      const path = InputLog.path();
      const file = fs.openSync(path,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
      InputLog.trim(path);
    } catch (_e) {
      // 収集が失敗しても入力そのものは止めない。
    }
  }

  // 上限を超えたら古い行を捨てる。「半分に切る」ではなく「末尾から上限の半分
  // ぶんだけ残す」にしてあるのは、半分にするだけだと1回で上限を下回らず、
  // 以後 flush のたびに数MBを読み直すことになるため。
  // (残す量は文字数で測る。日本語は1文字3バイトなので実バイト数は必ず
  //  これより多いが、多い方向にずれるぶんには上限を割るだけで害がない)
  private static trim(path: string): void {
    try {
      if (fs.statSync(path).size <= MAX_BYTES) { return; }
      const lines = fs.readTextSync(path).split('\n');
      let kept = 0;
      let start = lines.length;
      while (start > 0 && kept < MAX_BYTES / 2) {
        start--;
        kept += lines[start].length + 1;
      }
      const text = lines.slice(start).join('\n');
      const file = fs.openSync(path,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
    } catch (_e) {}
  }

  // ---- 閲覧・書き出し (本体アプリ側) ------------------------------------

  // ログ全文。エクスポートはこれをそのままクリップボードに載せる。
  static readRaw(dir: string): string {
    if (!DEBUG_INPUT_LOG) { return ''; }
    try {
      const path = dir + '/' + INPUT_LOG_FILE;
      if (!fs.accessSync(path)) { return ''; }
      return fs.readTextSync(path);
    } catch (_e) {
      return '';
    }
  }

  // 候補のディレクトリを順に見て、最初に見つかったものを返す。
  // 拡張側は アプリ単位の filesDir を優先しつつ、取れなければモジュール単位に
  // 落ちる。読み手が片方しか見ないと、落ちた場合に「空」に見えてしまう。
  static findDir(dirs: string[]): string {
    if (!DEBUG_INPUT_LOG) { return dirs.length > 0 ? dirs[0] : ''; }
    for (const d of dirs) {
      if (d.length > 0 && InputLog.sizeBytes(d) > 0) { return d; }
    }
    return dirs.length > 0 ? dirs[0] : '';
  }

  // 新しい順に最大 limit 件。壊れた行(書き込み中に切れた末尾など)は捨てる。
  // 全文を引数に取るのは、画面が件数・サイズ・一覧を出すのに同じファイルを
  // 何度も読み直さないため(数MBになりうる)。
  static parse(raw: string, limit: number): InputLogEntry[] {
    if (!DEBUG_INPUT_LOG) { return []; }
    if (raw.length === 0) { return []; }
    const lines = raw.split('\n');
    const out: InputLogEntry[] = [];
    for (let i = lines.length - 1; i >= 0 && out.length < limit; i--) {
      const line = lines[i];
      if (line.length === 0) { continue; }
      try {
        const e = JSON.parse(line) as InputLogEntry;
        if (e !== null && typeof e.k === 'string') { out.push(e); }
      } catch (_e) {}
    }
    return out;
  }

  // 総行数(≒レコード数)。画面のヘッダに出す。
  static countLines(raw: string): number {
    let n = 0;
    for (let i = 0; i < raw.length; i++) {
      if (raw.charCodeAt(i) === 0x0a) { n++; }
    }
    return n;
  }

  static sizeBytes(dir: string): number {
    if (!DEBUG_INPUT_LOG) { return 0; }
    try {
      const path = dir + '/' + INPUT_LOG_FILE;
      if (!fs.accessSync(path)) { return 0; }
      return fs.statSync(path).size;
    } catch (_e) {
      return 0;
    }
  }

  static clear(dir: string): void {
    if (!DEBUG_INPUT_LOG) { return; }
    InputLog.buffer = [];
    try {
      const path = dir + '/' + INPUT_LOG_FILE;
      if (fs.accessSync(path)) { fs.unlinkSync(path); }
    } catch (_e) {}
  }

  // ---- 補助 -------------------------------------------------------------

  // 確定の性質。カタカナ変換・英数変換・かな確定は「候補の順番の問題」では
  // ないので、精度の集計から外せるように印を付けておく。
  private static classify(reading: string, surface: string): string {
    if (surface === reading) { return LF_KANA; }
    if (InputLog.isAllKatakana(surface) && InputLog.toKatakana(reading) === surface) {
      return LF_KATAKANA;
    }
    if (InputLog.isAllAscii(surface)) { return LF_ALNUM; }
    return '';
  }

  private static isAllKatakana(s: string): boolean {
    if (s.length === 0) { return false; }
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (!(c >= 0x30a1 && c <= 0x30fc)) { return false; }
    }
    return true;
  }

  private static isAllAscii(s: string): boolean {
    if (s.length === 0) { return false; }
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c > 0x7e || c < 0x20) { return false; }
    }
    return true;
  }

  private static toKatakana(s: string): string {
    let out = '';
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      out += (c >= 0x3041 && c <= 0x3096) ? String.fromCharCode(c + 0x60) : s.charAt(i);
    }
    return out;
  }
}
