#!/usr/bin/env python3
"""tools/vocab_packs/*.pack を、アプリが読む rawfile/pack_manifest.json にする。

なぜ独自形式か
--------------
DICTIONARY (KanaKanjiConverter.ets 内の巨大オブジェクトリテラル) に直接
書き足す形だと、コードを読める人にしか語彙パックへの貢献ができない。
パック名・説明文までファイルの中に持たせることで、.ets を一切触らずに
「ファイルを1つ足す」だけで新しいパックが増えるようにしてある。

なぜ他の辞書と違って JSON のままか
----------------------------------
dict/global_dict は10万〜28万読みあるのでバイナリにパックしないと
ArkTSヒープが持たない (pack_dicts.py の説明参照)。語彙パックは「界隈の
定番語彙」という性質上そこまで大きくならないうえ、動詞・形容詞の活用展開を
実行時に ConjugationEngine で行う (下記) 関係でどのみち JS オブジェクトに
展開する必要がある。1ファイルで済むほうが中身も確認しやすい。

フォーマットの詳細は tools/vocab_packs/README.md を参照。要点:

    name: 表示名
    description: 一行説明
    ---
    読み<TAB>単語[<TAB>オプション...]

オプションは**順不同**で、書き方から種類を判別する:

    1〜10        優先度 (1=最優先, 既定5)
    品詞名       名詞/五段/一段/形容詞/人名/地名/副詞/... (下の POS_TABLE)
    @12          接続行列のクラスIDを直接指定 (左右とも12)
    @0,10        左クラス0・右クラス10 を直接指定

行頭 - はその候補を出さない指定 (優先度・品詞は書けない)。

Usage:
  python3 tools/build_vocab_packs.py            ビルド
  python3 tools/build_vocab_packs.py --report   読み込んで内容を表示するだけ
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS_DIR = os.path.join(HERE, 'vocab_packs')
RAWFILE = os.path.join(HERE, '..', 'entry', 'src', 'main', 'resources', 'rawfile')

DEFAULT_PRIORITY = 5
MIN_PRIORITY = 1
MAX_PRIORITY = 10

# タブ、または半角スペース2個以上。全角スペースは読み・単語に含まれうるので
# 区切りとして扱わない。
SPLIT_RE = re.compile(r'\t+| {2,}')

# 品詞名 -> ('class', [左, 右]) か ('expand', pos, group)
#
# 'class'  : 接続行列のクラスIDを固定で与える。活用はしない。
# 'expand' : ConjugationEngine (端末側) に渡して活用形まで自動生成させる。
#            五段/一段/形容詞だけ。「がばる」1行で がばって/がばった/
#            がばらない … が全部生える。
#
# クラスIDの意味は tools/gen_matrix_default.py の冒頭表を参照。
POS_TABLE = {
    '名詞':       ('class', None),        # 既定。クラス上書きなし
    'サ変名詞':   ('class', [1, 1]),      # 勉強/運動 (→する に繋がる)
    'な形容詞':   ('class', [2, 2]),      # 静か/便利
    '形容動詞':   ('class', [2, 2]),      # な形容詞の別名
    '代名詞':     ('class', [3, 3]),
    '人名':       ('expand', 'person', None),
    '地名':       ('expand', 'place', None),
    '組織':       ('class', [6, 6]),
    '数':         ('class', [7, 7]),
    '助数詞':     ('class', [8, 8]),
    '非自立名詞': ('class', [9, 9]),      # こと/もの/とき
    '副詞可能':   ('class', [10, 10]),    # 今/前/後
    '外来語':     ('class', [12, 12]),
    '五段':       ('expand', 'verb', 'godan'),
    '一段':       ('expand', 'verb', 'ichidan'),
    '形容詞':     ('expand', 'adjective', None),
    '副詞':       ('class', [45, 45]),
    '感動詞':     ('class', [90, 90]),
    '接頭辞':     ('class', [95, 95]),
    '接尾辞':     ('class', [97, 97]),
    '記号':       ('class', [92, 92]),
}

MAX_CLASS_ID = 99


def _parse_class_spec(token, where):
    """@12 / @0,10 -> [左, 右]"""
    body = token[1:].strip()
    parts = [p.strip() for p in body.split(',')]
    if len(parts) not in (1, 2):
        raise SystemExit(f'{where}: @ の指定は @12 か @0,10 の形で書く: {token!r}')
    try:
        ids = [int(p) for p in parts]
    except ValueError:
        raise SystemExit(f'{where}: @ のクラスIDは整数で書く: {token!r}')
    for i in ids:
        if not (0 <= i <= MAX_CLASS_ID):
            raise SystemExit(
                f'{where}: クラスIDは 0〜{MAX_CLASS_ID} の範囲 '
                f'(tools/gen_matrix_default.py の表を参照): {i}')
    return ids if len(ids) == 2 else [ids[0], ids[0]]


def _strip_trailing_comment(cols):
    """3列目以降に現れた # からあとを行末コメントとして落とす。

    読み(0)・単語(1)は絶対に切らない -- 「しゃーぷ → #」のように記号そのものを
    登録したい場合があり、単語列の # をコメント開始と誤解すると登録できなく
    なるため。コメントとして扱うのはオプション列だけ。
    """
    for i in range(2, len(cols)):
        if cols[i].startswith('#'):
            return cols[:i]
    return cols


def _parse_options(tokens, where):
    """優先度・品詞・クラス指定を順不同で受ける。"""
    priority = None
    pos_name = None
    classes = None
    for tok in tokens:
        if tok.startswith('@'):
            if classes is not None:
                raise SystemExit(f'{where}: @ の指定が2つある')
            classes = _parse_class_spec(tok, where)
            continue
        if re.fullmatch(r'-?\d+', tok):
            if priority is not None:
                raise SystemExit(f'{where}: 優先度が2つある')
            priority = int(tok)
            if not (MIN_PRIORITY <= priority <= MAX_PRIORITY):
                raise SystemExit(
                    f'{where}: 優先度は {MIN_PRIORITY}〜{MAX_PRIORITY} の範囲で書く '
                    f'(1=最優先, 10=一番右でいい): {priority}')
            continue
        if tok not in POS_TABLE:
            known = ' / '.join(POS_TABLE.keys())
            raise SystemExit(
                f'{where}: 品詞名として解釈できない: {tok!r}\n'
                f'  使えるのは: {known}\n'
                f'  (クラスIDを直接指定したいときは @12 のように書く)')
        if pos_name is not None:
            raise SystemExit(f'{where}: 品詞指定が2つある')
        pos_name = tok
    return priority, pos_name, classes


def parse_pack(path):
    name = None
    description = ''
    in_body = False
    rows = []        # (reading, word, priority, order)
    pos_map = {}     # "読み\t単語" -> {"pos":..., "group":...}
    class_map = {}   # 読み -> [左, 右]
    suppress = {}
    order = 0

    with open(path, encoding='utf-8') as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip('\n').rstrip('\r')
            stripped = line.strip()
            where = f'{path}:{lineno}'
            if not stripped or stripped.startswith('#'):
                continue
            if not in_body:
                if stripped == '---':
                    in_body = True
                    continue
                if ':' not in stripped:
                    raise SystemExit(f'{where}: ヘッダは「キー: 値」の形で書く: {line!r}')
                key, _, value = stripped.partition(':')
                key, value = key.strip(), value.strip()
                if key == 'name':
                    name = value
                elif key == 'description':
                    description = value
                else:
                    raise SystemExit(f'{where}: 未知のヘッダキー: {key!r}')
                continue

            suppressed = stripped.startswith('-')
            body = stripped[1:].strip() if suppressed else stripped
            cols = [c.strip() for c in SPLIT_RE.split(body) if c.strip()]
            cols = _strip_trailing_comment(cols)
            if len(cols) < 2:
                raise SystemExit(
                    f'{where}: 「読み(タブ|スペース2個以上)単語」が必要: {line!r}')
            reading, word = cols[0], cols[1]

            if suppressed:
                if len(cols) >= 3:
                    raise SystemExit(
                        f'{where}: 抑制指定 (行頭 -) に優先度や品詞は書けない: {line!r}')
                suppress.setdefault(reading, [])
                if word not in suppress[reading]:
                    suppress[reading].append(word)
                continue

            priority, pos_name, classes = _parse_options(cols[2:], where)
            rows.append((reading, word, priority if priority is not None else DEFAULT_PRIORITY, order))
            order += 1

            if classes is not None:
                class_map[reading] = classes
            if pos_name is not None:
                kind = POS_TABLE[pos_name]
                if kind[0] == 'class':
                    if kind[1] is not None:
                        # @ の明示指定があるならそちらを優先する
                        class_map.setdefault(reading, kind[1])
                else:
                    entry = {'pos': kind[1]}
                    if kind[2] is not None:
                        entry['group'] = kind[2]
                    pos_map[reading + '\t' + word] = entry

    if not in_body:
        raise SystemExit(f'{path}: ヘッダと本体を区切る --- の行が無い')
    if not name:
        raise SystemExit(f'{path}: ヘッダに name: が無い')

    by_reading = {}
    for reading, word, priority, idx in rows:
        by_reading.setdefault(reading, []).append((priority, idx, word))
    entries = {}
    for reading, items in by_reading.items():
        items.sort(key=lambda t: (t[0], t[1]))   # 優先度が小さいほど前、同点なら書いた順
        words = []
        for _, _, w in items:
            if w not in words:
                words.append(w)
        entries[reading] = words

    return {
        'name': name,
        'description': description,
        'entries': entries,
        'pos': pos_map,
        'classes': class_map,
        'suppress': suppress,
    }


def main():
    report_only = '--report' in sys.argv
    if not os.path.isdir(PACKS_DIR):
        raise SystemExit('missing ' + PACKS_DIR)

    manifest = []
    for fname in sorted(os.listdir(PACKS_DIR)):
        if not fname.endswith('.pack'):
            continue
        pack_id = fname[:-len('.pack')]
        p = parse_pack(os.path.join(PACKS_DIR, fname))

        n_words = sum(len(v) for v in p['entries'].values())
        print(f'== {pack_id} ({p["name"]}) ==')
        print(f'   {p["description"]}')
        print(f'   読み {len(p["entries"])} / 表記 {n_words} / 活用展開 {len(p["pos"])} '
              f'/ クラス指定 {len(p["classes"])} / 抑制 {sum(len(v) for v in p["suppress"].values())}')
        for reading, words in list(p['entries'].items())[:5]:
            print(f'   {reading} -> {words}')
        if len(p['entries']) > 5:
            print(f'   ... 他 {len(p["entries"]) - 5} 件')

        manifest.append({
            'id': pack_id,
            'name': p['name'],
            'description': p['description'],
            'entries': p['entries'],
            'pos': p['pos'],
            'classes': p['classes'],
            'suppress': p['suppress'],
        })

    if report_only:
        return

    manifest_path = os.path.join(RAWFILE, 'pack_manifest.json')
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, separators=(',', ':'))
    size = os.path.getsize(manifest_path)
    print(f'pack_manifest.json: {[m["id"] for m in manifest]} ({size:,} バイト)')


if __name__ == '__main__':
    main()
