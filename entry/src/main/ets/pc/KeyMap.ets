// PCモード (物理キーボード) のキー表と、文字の幅の書き換え。
//
// 物理キーボードから届くのはキーコード (KeyCode) だけで、そのキーが打つ字は
// 配列で決まる。HarmonyOS の物理キーボードは US 配列が基本なので、US 配列の
// 表だけを持つ (JIS 配列の @ [ : などの位置の違いは扱わない)。
// KeyEvent.unicodeChar は入力メソッド側に届いたときに値が入るか確かめられて
// いないので、表を主に使い、表に無いキーだけ unicodeChar に頼る (charFor)。
import { KeyCode } from '@kit.InputKit';
import { ROMAJI_TABLE } from '../ime/JapaneseConverter';

const CODE_A: number = KeyCode.KEYCODE_A;
const CODE_Z: number = KeyCode.KEYCODE_Z;
const CODE_0: number = KeyCode.KEYCODE_0;
const CODE_9: number = KeyCode.KEYCODE_9;
const CODE_NUMPAD_0: number = KeyCode.KEYCODE_NUMPAD_0;
const CODE_NUMPAD_9: number = KeyCode.KEYCODE_NUMPAD_9;

// 数字の段を Shift 付きで押したときの字 (US 配列)。添字が数字。
const SHIFTED_DIGITS: string = ')!@#$%^&*(';

// 記号キー: [Shift なし, Shift あり]
const US_SYMBOLS: Map<number, string[]> = buildSymbolTable();

function buildSymbolTable(): Map<number, string[]> {
  const m = new Map<number, string[]>();
  m.set(KeyCode.KEYCODE_GRAVE, ['`', '~']);
  m.set(KeyCode.KEYCODE_MINUS, ['-', '_']);
  m.set(KeyCode.KEYCODE_EQUALS, ['=', '+']);
  m.set(KeyCode.KEYCODE_LEFT_BRACKET, ['[', '{']);
  m.set(KeyCode.KEYCODE_RIGHT_BRACKET, [']', '}']);
  m.set(KeyCode.KEYCODE_BACKSLASH, ['\\', '|']);
  m.set(KeyCode.KEYCODE_SEMICOLON, [';', ':']);
  m.set(KeyCode.KEYCODE_APOSTROPHE, ['\'', '"']);
  m.set(KeyCode.KEYCODE_COMMA, [',', '<']);
  m.set(KeyCode.KEYCODE_PERIOD, ['.', '>']);
  m.set(KeyCode.KEYCODE_SLASH, ['/', '?']);
  // 単独のキーとして届く端末向け (US 配列の本体には無いが、表に無いと
  // unicodeChar 頼みになるので入れておく)
  m.set(KeyCode.KEYCODE_AT, ['@', '@']);
  m.set(KeyCode.KEYCODE_PLUS, ['+', '+']);
  m.set(KeyCode.KEYCODE_STAR, ['*', '*']);
  m.set(KeyCode.KEYCODE_POUND, ['#', '#']);
  return m;
}

// テンキーの記号 (NumLock に関係なく字を打つもの)
const NUMPAD_SYMBOLS: Map<number, string> = buildNumpadTable();

function buildNumpadTable(): Map<number, string> {
  const m = new Map<number, string>();
  m.set(KeyCode.KEYCODE_NUMPAD_DIVIDE, '/');
  m.set(KeyCode.KEYCODE_NUMPAD_MULTIPLY, '*');
  m.set(KeyCode.KEYCODE_NUMPAD_SUBTRACT, '-');
  m.set(KeyCode.KEYCODE_NUMPAD_ADD, '+');
  m.set(KeyCode.KEYCODE_NUMPAD_COMMA, ',');
  m.set(KeyCode.KEYCODE_NUMPAD_EQUALS, '=');
  m.set(KeyCode.KEYCODE_NUMPAD_LEFT_PAREN, '(');
  m.set(KeyCode.KEYCODE_NUMPAD_RIGHT_PAREN, ')');
  return m;
}

export class KeyMap {
  static isLetter(code: number): boolean {
    return code >= CODE_A && code <= CODE_Z;
  }

  static isNumpad(code: number): boolean {
    return (code >= CODE_NUMPAD_0 && code <= CODE_NUMPAD_9)
      || code === KeyCode.KEYCODE_NUMPAD_DOT
      || NUMPAD_SYMBOLS.has(code);
  }

  // 数字キー (上の段・テンキー) なら 0〜9、それ以外は -1。候補の番号選択に使う。
  // テンキーの数字は NumLock が切れていると矢印などの意味になるので、numLock を見る。
  static digitOf(code: number, numLock: boolean): number {
    if (code >= CODE_0 && code <= CODE_9) { return code - CODE_0; }
    if (numLock && code >= CODE_NUMPAD_0 && code <= CODE_NUMPAD_9) { return code - CODE_NUMPAD_0; }
    return -1;
  }

  // そのキーが打つ字 (US 配列)。字を打たないキーは ''。
  // unicodeChar は表に無いキーのときだけ使う (制御文字は捨てる)。
  static charFor(code: number, shift: boolean, capsLock: boolean, numLock: boolean,
      unicodeChar: number): string {
    if (KeyMap.isLetter(code)) {
      const lower = String.fromCharCode('a'.charCodeAt(0) + (code - CODE_A));
      // CapsLock は Shift と打ち消し合う (どちらか片方だけなら大文字)
      return (shift !== capsLock) ? lower.toUpperCase() : lower;
    }
    if (code >= CODE_0 && code <= CODE_9) {
      const d = code - CODE_0;
      return shift ? SHIFTED_DIGITS[d] : String(d);
    }
    if (code >= CODE_NUMPAD_0 && code <= CODE_NUMPAD_9) {
      return numLock ? String(code - CODE_NUMPAD_0) : '';
    }
    if (code === KeyCode.KEYCODE_NUMPAD_DOT) {
      return numLock ? '.' : '';
    }
    const numpadSym = NUMPAD_SYMBOLS.get(code);
    if (numpadSym !== undefined) { return numpadSym; }
    const sym = US_SYMBOLS.get(code);
    if (sym !== undefined) { return shift ? sym[1] : sym[0]; }
    if (unicodeChar >= 0x20 && unicodeChar !== 0x7F) {
      return String.fromCharCode(unicodeChar);
    }
    return '';
  }
}

// ---------- 文字の幅 ----------

// かな入力中に打った記号・数字を、Windows の IME の既定 (ひらがなモードでは
// 全角、句読点・かぎ括弧は和文の字) と同じ字に直す。英字は romaji なので
// そのまま返す (ローマ字の表を引く側が小文字にする)。'-' も ROMAJI_TABLE が
// 'ー' に直すので触らない。
const JAPANESE_PUNCT: Map<string, string> = buildJapanesePunct();

function buildJapanesePunct(): Map<string, string> {
  const m = new Map<string, string>();
  m.set(',', '、');
  m.set('.', '。');
  m.set('/', '・');
  m.set('[', '「');
  m.set(']', '」');
  m.set('~', '～');
  m.set('\'', '’');
  m.set('"', '”');
  m.set('`', '‘');
  m.set('\\', '＼');
  return m;
}

export function toJapaneseInputChar(ch: string): string {
  if (ch.length !== 1) { return ch; }
  if (/[a-zA-Z]/.test(ch) || ch === '-') { return ch; }
  const p = JAPANESE_PUNCT.get(ch);
  if (p !== undefined) { return p; }
  return toFullWidth(ch);
}

// ASCII の字を全角に (F9)。空白は全角空白。
export function toFullWidth(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 0x20) {
      out += '　';
    } else if (c >= 0x21 && c <= 0x7E) {
      out += String.fromCharCode(c + 0xFEE0);
    } else {
      out += s[i];
    }
  }
  return out;
}

// 全角の英数字を半角に (F10)。
export function toHalfWidthAscii(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 0x3000) {
      out += ' ';
    } else if (c >= 0xFF01 && c <= 0xFF5E) {
      out += String.fromCharCode(c - 0xFEE0);
    } else {
      out += s[i];
    }
  }
  return out;
}

// ひらがな → 全角カタカナ (F7) は JapaneseConverter.toKatakana をそのまま使う。

// 全角カタカナ (と、和文の記号) を半角カタカナに (F8)。先頭 1 字がもとの字、
// 残りが半角の字 (濁点・半濁点は 2 字になる)。
const HALF_KANA_PAIRS: string[] = [
  'ァｧ', 'アｱ', 'ィｨ', 'イｲ', 'ゥｩ', 'ウｳ', 'ェｪ', 'エｴ', 'ォｫ', 'オｵ',
  'カｶ', 'ガｶﾞ', 'キｷ', 'ギｷﾞ', 'クｸ', 'グｸﾞ', 'ケｹ', 'ゲｹﾞ', 'コｺ', 'ゴｺﾞ',
  'サｻ', 'ザｻﾞ', 'シｼ', 'ジｼﾞ', 'スｽ', 'ズｽﾞ', 'セｾ', 'ゼｾﾞ', 'ソｿ', 'ゾｿﾞ',
  'タﾀ', 'ダﾀﾞ', 'チﾁ', 'ヂﾁﾞ', 'ッｯ', 'ツﾂ', 'ヅﾂﾞ', 'テﾃ', 'デﾃﾞ', 'トﾄ', 'ドﾄﾞ',
  'ナﾅ', 'ニﾆ', 'ヌﾇ', 'ネﾈ', 'ノﾉ',
  'ハﾊ', 'バﾊﾞ', 'パﾊﾟ', 'ヒﾋ', 'ビﾋﾞ', 'ピﾋﾟ', 'フﾌ', 'ブﾌﾞ', 'プﾌﾟ',
  'ヘﾍ', 'ベﾍﾞ', 'ペﾍﾟ', 'ホﾎ', 'ボﾎﾞ', 'ポﾎﾟ',
  'マﾏ', 'ミﾐ', 'ムﾑ', 'メﾒ', 'モﾓ',
  'ャｬ', 'ヤﾔ', 'ュｭ', 'ユﾕ', 'ョｮ', 'ヨﾖ',
  'ラﾗ', 'リﾘ', 'ルﾙ', 'レﾚ', 'ロﾛ',
  'ヮﾜ', 'ワﾜ', 'ヰｲ', 'ヱｴ', 'ヲｦ', 'ンﾝ', 'ヴｳﾞ',
  'ーｰ', '、､', '。｡', '「｢', '」｣', '・･', '゛ﾞ', '゜ﾟ',
];

const HALF_KANA: Map<string, string> = buildHalfKana();

function buildHalfKana(): Map<string, string> {
  const m = new Map<string, string>();
  for (const p of HALF_KANA_PAIRS) {
    m.set(p[0], p.slice(1));
  }
  return m;
}

export function toHalfWidthKatakana(katakana: string): string {
  let out = '';
  for (let i = 0; i < katakana.length; i++) {
    const ch = katakana[i];
    const h = HALF_KANA.get(ch);
    if (h !== undefined) {
      out += h;
    } else {
      // 全角の英数字・記号も半角へ (F8 は半角の字で揃える)
      out += toHalfWidthAscii(ch);
    }
  }
  return out;
}

// 全角カタカナをひらがなに (F6)。ヴ はひらがなの ゔ にする。
export function toHiragana(s: string): string {
  return s.replace(/[ァ-ヶ]/g, (c: string) => String.fromCharCode(c.charCodeAt(0) - 0x60));
}

// ---------- かな → ローマ字 (F9・F10) ----------
//
// F9/F10 は本来「打ったキーそのもの」を出す (PhysicalKeyRouter が打鍵を
// 覚えている)。打鍵と今の読みが食い違ったとき (途中を消した・前の方だけ
// 確定した) だけ、読みからローマ字を作り直す。ROMAJI_TABLE を逆に引き、
// 同じかなに綴りが複数あれば短い方 (し → si) を使う。小書き用の x・l 始まりは
// ほかに綴りが無いときだけ。
// 逆引きの表に入れるかなの長さの上限 (きゃ・しゃ のような 2 字まで)。
// 表を作る前に決めておく必要がある (下の buildKanaToRomaji が使う)
const MAX_KANA_KEY: number = 2;
const KANA_TO_ROMAJI: Map<string, string> = buildKanaToRomaji();

function buildKanaToRomaji(): Map<string, string> {
  const m = new Map<string, string>();
  const keys = Object.keys(ROMAJI_TABLE);
  for (const romaji of keys) {
    const kana = ROMAJI_TABLE[romaji];
    if (kana === undefined || kana.length > MAX_KANA_KEY) { continue; }
    const small = romaji.startsWith('x') || romaji.startsWith('l');
    const prev = m.get(kana);
    if (prev === undefined) {
      m.set(kana, romaji);
      continue;
    }
    const prevSmall = prev.startsWith('x') || prev.startsWith('l');
    if ((prevSmall && !small) || (prevSmall === small && romaji.length < prev.length)) {
      m.set(kana, romaji);
    }
  }
  m.set('ん', 'nn');
  return m;
}

export function kanaToRomaji(reading: string): string {
  const s = toHiragana(reading);
  let out = '';
  let sokuon = false;
  let i = 0;
  while (i < s.length) {
    let romaji = '';
    let used = 1;
    for (let len = Math.min(MAX_KANA_KEY, s.length - i); len >= 1; len--) {
      const r = KANA_TO_ROMAJI.get(s.slice(i, i + len));
      if (r !== undefined) {
        romaji = r;
        used = len;
        break;
      }
    }
    const ch = s[i];
    if (ch === 'っ' && used === 1) {
      // 次の字の子音を重ねる。子音で始まらなければ (っあ・語末の っ) 小書きの綴り
      if (sokuon) { out += 'xtu'; }
      sokuon = true;
      i += 1;
      continue;
    }
    if (romaji.length === 0) {
      romaji = toHalfWidthAscii(ch);
    }
    if (sokuon) {
      out += /^[bcdfghjkmpqrstvwxyz]/.test(romaji) ? romaji[0] : 'xtu';
      sokuon = false;
    }
    out += romaji;
    i += used;
  }
  if (sokuon) { out += 'xtu'; }
  return out;
}
