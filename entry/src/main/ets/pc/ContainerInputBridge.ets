// Android コンテナのアプリの入力欄で日本語を打つための力ずくの仕組み。
//
// Android コンテナの欄では物理キーが IME に届かず、アプリへ直接渡る (keyEvent も textChange も来ない)。
// そこで、欄のカーソルの前の文字を短い間隔で読み (getForwardSync)、打たれた英字を後から書き換える。
//
//   k     → 欄に「k」が入る (アプリがそのまま入れる)。何もしない
//   ka    → 「ka」を消して「か」を入れる
//   kaki␣ → 「かき」と空白を消して、1 位の候補「柿」を入れる。候補ウィンドウを出す
//   ␣     → 次の候補 (「柿」と空白を消して「牡蠣」を入れる)
//   BS    → 変換した語を読みに戻す (BackSpace で消えた 1 字のぶんも含めて「かき」に)
//   他の字 → 今の候補で確定。その字から次の読みを打ち始める
//
// 大文字で始めた語は英字のまま (空白か記号まで)。, . などは 、 。 に書き換える。
// 欄の中身はログに出さない。
import inputMethodEngine from '@ohos.inputMethodEngine';
import { InputState, InputMode } from '../ime/KeyboardController';
import { JapaneseConverter } from '../ime/JapaneseConverter';
import { AiConverter } from '../ime/AiConverter';
import { KanaKanjiConverter } from '../ime/KanaKanjiConverter';
import { toJapaneseInputChar, toFullWidth } from './KeyMap';

// 欄を読む間隔 (ms) と、1 回に読む文字数
const POLL_MS: number = 40;
const TAIL: number = 64;
// 1 回の読みの間に増えた・減ったと見なす最大の文字数 (これより大きく変わったら読み直しとして扱う)
const MAX_STEP: number = 8;

// 欄が変わったときに呼ぶ (候補ウィンドウの出し入れ)
export interface ContainerBridgeHost {
  onBridgeStateChanged(): void;
  // 書き換えてよいか (仮想キーを出している間は、ソフトキーボードがいつもどおり入力するので何もしない)
  bridgeEnabled(): boolean;
}

export class ContainerInputBridge {
  private static instance: ContainerInputBridge | undefined = undefined;

  static getInstance(): ContainerInputBridge {
    if (ContainerInputBridge.instance === undefined) {
      ContainerInputBridge.instance = new ContainerInputBridge();
    }
    return ContainerInputBridge.instance;
  }

  private host: ContainerBridgeHost | undefined = undefined;
  private client: inputMethodEngine.InputClient | undefined = undefined;
  private timer: number = -1;
  private readFailed: boolean = false;
  private loggedRead: boolean = false;

  // 最後に読んだカーソルの前の文字 (TAIL 字まで)
  private last: string = '';
  // 欄にある、まだ変換できる読み (自分で入れたかな) と、その後ろの打ちかけのローマ字 (アプリが入れた英字のまま)
  private reading: string = '';
  private raw: string = '';
  private romaji: JapaneseConverter = new JapaneseConverter();
  // 大文字で始めた英字の語の途中 (空白・記号まで書き換えない)
  private alphaRun: boolean = false;
  // 変換中: 欄にある候補と、その読み
  private converted: string = '';
  private convReading: string = '';
  private cands: string[] = [];
  private index: number = 0;

  setHost(host: ContainerBridgeHost | undefined): void {
    this.host = host;
  }

  isRunning(): boolean {
    return this.timer >= 0;
  }

  // 候補ウィンドウに候補を出しているか (クリックをこちらで受けるか)
  isConverting(): boolean {
    return this.isRunning() && this.converted.length > 0;
  }

  start(client: inputMethodEngine.InputClient): void {
    this.stop();
    this.client = client;
    this.readFailed = false;
    this.loggedRead = false;
    this.last = this.read() ?? '';
    this.forget();
    this.timer = setInterval(() => { this.poll(); }, POLL_MS);
    console.info('shuntiIME pc container bridge started');
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
      console.info('shuntiIME pc container bridge stopped');
    }
    const wasConverting = this.converted.length > 0;
    this.commitConversion();
    this.forget();
    this.client = undefined;
    if (wasConverting) { this.publish(); }
  }

  // ---------- 候補ウィンドウのクリック ----------

  pick(i: number): void {
    if (!this.isConverting() || i < 0 || i >= this.cands.length) { return; }
    this.choose(i);
    this.commitConversion();
    this.publish();
  }

  select(i: number): void {
    if (!this.isConverting() || i < 0 || i >= this.cands.length) { return; }
    this.choose(i);
    this.publish();
  }

  // ---------- 欄を読む ----------

  private read(): string | undefined {
    if (this.client === undefined) { return undefined; }
    try {
      const t = this.client.getForwardSync(TAIL);
      if (!this.loggedRead) {
        this.loggedRead = true;
        console.info(`shuntiIME pc container bridge can read the field (len=${t.length})`);
      }
      return t;
    } catch (e) {
      if (!this.readFailed) {
        this.readFailed = true;
        console.error(`shuntiIME pc container bridge cannot read the field: ${JSON.stringify(e)}`);
      }
      return undefined;
    }
  }

  private poll(): void {
    const tail = this.read();
    if (tail === undefined || tail === this.last) { return; }
    const prev = this.last;
    this.last = tail;
    if (!this.imeOn() || !(this.host?.bridgeEnabled() ?? false)) {
      this.resetAll();
      return;
    }
    const added = ContainerInputBridge.addedChars(prev, tail);
    if (added !== undefined) {
      for (const ch of added) {
        if (!this.onChar(ch)) { break; }
      }
      return;
    }
    const removed = ContainerInputBridge.removedCount(prev, tail);
    if (removed > 0) {
      this.onDeleted(removed);
      return;
    }
    // カーソルを動かした・範囲を選んで消した・アプリが中身を書き換えた: 打っていたものは確定扱い
    this.resetAll();
  }

  // prev の後ろに打ち足して tail になったなら、足された文字。TAIL 字で切れているときは前が押し出される
  static addedChars(prev: string, tail: string): string | undefined {
    for (let n = 1; n <= MAX_STEP && n <= tail.length; n++) {
      const before = tail.slice(0, tail.length - n);
      if (before === prev) { return tail.slice(tail.length - n); }
      if (prev.length === TAIL && tail.length === TAIL && prev.endsWith(before)) {
        return tail.slice(tail.length - n);
      }
    }
    return undefined;
  }

  // prev の末尾から消して tail になったなら、消えた文字数 (0 は違う)。TAIL 字で切れているときは前の字が入ってくる
  static removedCount(prev: string, tail: string): number {
    for (let n = 1; n <= MAX_STEP && n <= prev.length; n++) {
      const kept = prev.slice(0, prev.length - n);
      if (tail === kept) { return n; }
      if (prev.length === TAIL && tail.length > kept.length && tail.endsWith(kept)) { return n; }
    }
    return 0;
  }

  private imeOn(): boolean {
    return (AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA) !== InputMode.ALPHANUMERIC;
  }

  private katakanaMode(): boolean {
    return (AppStorage.get<string>('inputMode') ?? InputMode.HIRAGANA) === InputMode.KATAKANA;
  }

  // ---------- 打たれた 1 字 ----------

  // 続けて次の字を見てよければ true (欄を書き換えられなかったときは false で読み直しに任せる)
  private onChar(ch: string): boolean {
    if (this.converted.length > 0) {
      if (ch === ' ') {
        // 次の候補 (空白は消す)
        const next = this.nextCandidate();
        if (!this.replace(1 + this.converted.length, next)) { return false; }
        this.converted = next;
        this.publish();
        return true;
      }
      this.commitConversion();
      this.publish();
    }
    if (/^[A-Z]$/.test(ch) && !this.alphaRun) {
      // 大文字から後ろは英字のまま (打っていた読みはかなのまま確定)
      this.forget();
      this.alphaRun = true;
    }
    if (this.alphaRun) {
      if (/^[A-Za-z0-9\-']$/.test(ch)) { return true; }
      this.alphaRun = false;
      return true;            // 空白・記号はそのまま
    }
    if (/^[a-z\-]$/.test(ch)) {
      return this.onRomaji(ch);
    }
    if (ch === ' ') {
      if (this.reading.length === 0 && this.raw.length === 0) { return true; }
      return this.convert();
    }
    // 数字・記号・改行など: 打っていた読みはかなのまま確定
    this.forget();
    const jp = toJapaneseInputChar(ch);
    if (jp !== ch && ch !== '-') {
      return this.replace(1, jp);
    }
    return true;
  }

  private onRomaji(ch: string): boolean {
    const before = this.raw;
    const r = this.romaji.processKey(ch);
    if (r.committed.length === 0) {
      this.raw = r.pending;   // 英字のまま欄にある
      return true;
    }
    const kana = this.katakanaMode() ? KanaKanjiConverter.toKatakana(r.committed) : r.committed;
    // 打ちかけの英字と今の 1 字を消して、かなとまだ打ちかけの英字を入れる
    const ok = this.replace(before.length + 1, kana + r.pending);
    if (ok) {
      this.reading += kana;
      this.raw = r.pending;
    }
    return ok;
  }

  private onDeleted(n: number): void {
    if (this.converted.length > 0) {
      // BackSpace で変換した語を読みに戻す (Windows の IME と同じ)
      if (n === 1 && this.converted.length > 1) {
        const reading = this.convReading;
        const rest = this.converted.length - 1;
        this.converted = '';
        this.cands = [];
        this.publish();
        if (this.replace(rest, reading)) {
          this.reading = reading;
          this.raw = '';
          this.romaji.reset();
        }
        return;
      }
      this.forget();
      this.publish();
      return;
    }
    let left = n;
    const fromRaw = Math.min(left, this.raw.length);
    this.raw = this.raw.slice(0, this.raw.length - fromRaw);
    left -= fromRaw;
    if (left > 0) {
      this.reading = this.reading.slice(0, Math.max(0, this.reading.length - left));
    }
    // tk → BS のように、ローマ字にならずに読みへ英字のまま入った字が末尾に残ったら、打ちかけに戻す
    // (続けて a を打てば「た」になる)
    const m = /[a-z]+$/.exec(this.reading);
    if (m !== null && JapaneseConverter.isRomajiPrefix(m[0] + this.raw)) {
      this.reading = this.reading.slice(0, this.reading.length - m[0].length);
      this.raw = m[0] + this.raw;
    }
    this.romaji.setPending(this.raw);
    if (this.reading.length === 0 && this.raw.length === 0) { this.forget(); }
  }

  // ---------- 変換 ----------

  private convert(): boolean {
    let reading = this.reading;
    if (this.raw.length > 0) {
      reading += this.raw === 'n' ? (this.katakanaMode() ? 'ン' : 'ん') : this.raw;
    }
    const cands = this.candidatesFor(reading);
    const len = this.reading.length + this.raw.length + 1;   // 読み + 打ちかけ + 空白
    if (!this.replace(len, cands[0])) { return false; }
    this.reading = '';
    this.raw = '';
    this.romaji.reset();
    this.convReading = reading;
    this.cands = cands;
    this.index = 0;
    this.converted = cands[0];
    this.publish();
    return true;
  }

  private candidatesFor(reading: string): string[] {
    const out: string[] = [];
    const push = (c: string): void => {
      if (c.length > 0 && out.indexOf(c) < 0) { out.push(c); }
    };
    if (AiConverter.isReady()) {
      for (const c of AiConverter.convertNow(KanaKanjiConverter.recentContext(), reading, 30).cands) { push(c); }
    }
    push(reading);
    push(KanaKanjiConverter.toKatakana(reading));
    if (/^[\x21-\x7e]+$/.test(reading)) { push(toFullWidth(reading)); }
    return KanaKanjiConverter.applyLearnedOrder(reading, out);
  }

  private nextCandidate(): string {
    this.index = (this.index + 1) % this.cands.length;
    return this.cands[this.index];
  }

  // i 番目の候補を欄に入れる (今の候補と入れ替える)
  private choose(i: number): void {
    if (i === this.index) { return; }
    const prevText = this.converted;
    this.index = i;
    if (this.replaceNoFollow(prevText.length, this.cands[i])) {
      this.converted = this.cands[i];
    }
  }

  private commitConversion(): void {
    if (this.converted.length === 0) { return; }
    KanaKanjiConverter.recordChoice(this.convReading, this.converted);
    KanaKanjiConverter.addContext(this.converted);
    this.converted = '';
    this.convReading = '';
    this.cands = [];
    this.index = 0;
  }

  private forget(): void {
    this.converted = '';
    this.convReading = '';
    this.cands = [];
    this.index = 0;
    this.reading = '';
    this.raw = '';
    this.alphaRun = false;
    this.romaji.reset();
  }

  private resetAll(): void {
    const wasConverting = this.converted.length > 0;
    this.commitConversion();
    this.forget();
    if (wasConverting) { this.publish(); }
  }

  // ---------- 欄を書き換える ----------

  // カーソルの前の del 字を消して text を入れる。次の読みと比べる元 (last) も書き換えた後にする
  private replace(del: number, text: string): boolean {
    const before = this.last;
    if (!this.edit(del, text)) { return false; }
    const expected = before.slice(0, Math.max(0, before.length - del)) + text;
    const now = this.read();
    // 書き換えの間に打たれた字があれば、次の読みで打ち足されたものとして拾う
    this.last = (now !== undefined && now.endsWith(expected.slice(-Math.min(expected.length, 16))))
      ? now : expected.slice(-TAIL);
    return true;
  }

  // 候補のクリックから (読みの途中ではないので、今の欄を読み直すだけ)
  private replaceNoFollow(del: number, text: string): boolean {
    if (!this.edit(del, text)) { return false; }
    this.last = this.read() ?? this.last;
    return true;
  }

  private edit(del: number, text: string): boolean {
    if (this.client === undefined) { return false; }
    try {
      if (del > 0) { this.client.deleteForwardSync(del); }
      if (text.length > 0) { this.client.insertTextSync(text); }
      return true;
    } catch (e) {
      console.error(`shuntiIME pc container bridge edit failed: ${JSON.stringify(e)}`);
      this.forget();
      return false;
    }
  }

  // ---------- 候補ウィンドウ ----------

  // 候補ウィンドウ (PcCandidateWindow) は AppStorage を見て描く。この欄ではキーが InputHandler に
  // 届かないので、変換中だけここから書く
  private publish(): void {
    if (this.converted.length > 0) {
      AppStorage.setOrCreate('composingText', this.convReading);
      AppStorage.setOrCreate('pendingRomaji', '');
      AppStorage.setOrCreate('composingCaret', -1);
      AppStorage.setOrCreate('previewInField', true);
      AppStorage.setOrCreate('bunsetsuDisplay', '');
      AppStorage.setOrCreate('candidates', [...this.cands]);
      AppStorage.setOrCreate('selectedCandidateIndex', this.index);
      AppStorage.setOrCreate('inputState', InputState.SELECTING);
    } else {
      AppStorage.setOrCreate('inputState', InputState.IDLE);
      AppStorage.setOrCreate('candidates', [] as string[]);
      AppStorage.setOrCreate('selectedCandidateIndex', 0);
      AppStorage.setOrCreate('composingText', '');
    }
    this.host?.onBridgeStateChanged();
  }
}
