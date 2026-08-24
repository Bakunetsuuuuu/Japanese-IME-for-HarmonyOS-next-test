#!/usr/bin/env python3
"""tools/vocab_packs/*.pack を、アプリが読むバイナリ辞書 + manifest に変換する。

なぜ独自形式か
--------------
DICTIONARY (KanaKanjiConverter.ets 内の巨大オブジェクトリテラル) に直接
書き足す形だと、コードを読める人にしか語彙パックへの貢献ができない。
パック名・説明文までファイルの中に持たせることで、.ets を一切触らずに
「ファイルを1つ足す」だけで新しいパックが増えるようにしてある。

フォーマットの詳細は tools/vocab_packs/README.md を参照。要点だけ:

    name: 表示名
    description: 一行説明
    ---
    読み<TAB>単語<優先度>      優先度は 1(最優先) 〜 10(一番右でいい)、既定5
    -読み<TAB>単語             行頭 - はその候補を出さない指定

区切りはタブでも半角スペース2個以上でもよい (エディタがタブを空白に変換
しても壊れないように)。

Usage:
  python3 tools/build_vocab_packs.py            全パックをビルド
  python3 tools/build_vocab_packs.py --report   読み込んで内容を表示するだけ
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS_DIR = os.path.join(HERE, 'vocab_packs')
SRCDIR = os.path.join(HERE, 'dict_src')
RAWFILE = os.path.join(HERE, '..', 'entry', 'src', 'main', 'resources', 'rawfile')

sys.path.insert(0, HERE)
from pack_dicts import pack  # noqa: E402  (再利用: 同じバイナリ形式で書き出す)

DEFAULT_PRIORITY = 5
MIN_PRIORITY = 1
MAX_PRIORITY = 10

# タブ、または半角スペース2個以上。全角スペースは読み・単語に含まれうるので
# 区切りとして扱わない。
SPLIT_RE = re.compile(r'\t+| {2,}')


def parse_pack(path):
    """1ファイルを (meta, entries, suppress) に読む。

    entries : reading -> [word, ...] (優先度→ファイル順で整列済み)
    suppress: reading -> [word, ...]
    """
    name = None
    description = ''
    in_body = False
    rows = []      # (reading, word, priority, order)
    suppress = {}
    order = 0

    with open(path, encoding='utf-8') as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip('\n').rstrip('\r')
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            if not in_body:
                if stripped == '---':
                    in_body = True
                    continue
                if ':' not in stripped:
                    raise SystemExit(
                        f'{path}:{lineno}: ヘッダは「キー: 値」の形で書く: {line!r}')
                key, _, value = stripped.partition(':')
                key = key.strip()
                value = value.strip()
                if key == 'name':
                    name = value
                elif key == 'description':
                    description = value
                else:
                    raise SystemExit(f'{path}:{lineno}: 未知のヘッダキー: {key!r}')
                continue

            suppressed = stripped.startswith('-')
            body = stripped[1:].strip() if suppressed else stripped
            cols = [c.strip() for c in SPLIT_RE.split(body) if c.strip()]
            if len(cols) < 2:
                raise SystemExit(
                    f'{path}:{lineno}: 「読み(タブ|スペース2個以上)単語」が必要: {line!r}')
            reading, word = cols[0], cols[1]

            if suppressed:
                if len(cols) >= 3:
                    raise SystemExit(
                        f'{path}:{lineno}: 抑制指定 (行頭 -) に優先度は書けない: {line!r}')
                suppress.setdefault(reading, [])
                if word not in suppress[reading]:
                    suppress[reading].append(word)
                continue

            priority = DEFAULT_PRIORITY
            if len(cols) >= 3:
                try:
                    priority = int(cols[2])
                except ValueError:
                    raise SystemExit(
                        f'{path}:{lineno}: 優先度は整数で書く: {cols[2]!r}')
                if not (MIN_PRIORITY <= priority <= MAX_PRIORITY):
                    raise SystemExit(
                        f'{path}:{lineno}: 優先度は {MIN_PRIORITY}〜{MAX_PRIORITY} '
                        f'の範囲で書く (1=最優先, 10=一番右でいい): {priority}')
            rows.append((reading, word, priority, order))
            order += 1

    if not in_body:
        raise SystemExit(f'{path}: ヘッダと本体を区切る --- の行が無い')
    if not name:
        raise SystemExit(f'{path}: ヘッダに name: が無い')

    by_reading = {}
    for reading, word, priority, idx in rows:
        by_reading.setdefault(reading, []).append((priority, idx, word))
    entries = {}
    for reading, items in by_reading.items():
        # 優先度の小さい方が前。同じなら書いた順。
        items.sort(key=lambda t: (t[0], t[1]))
        words = []
        for _, _, w in items:
            if w not in words:
                words.append(w)
        entries[reading] = words

    meta = {'name': name, 'description': description}
    return meta, entries, suppress


def main():
    report_only = '--report' in sys.argv
    if not os.path.isdir(PACKS_DIR):
        raise SystemExit('missing ' + PACKS_DIR)
    if not report_only:
        os.makedirs(SRCDIR, exist_ok=True)

    manifest = []
    for fname in sorted(os.listdir(PACKS_DIR)):
        if not fname.endswith('.pack'):
            continue
        pack_id = fname[:-len('.pack')]
        meta, entries, suppress = parse_pack(os.path.join(PACKS_DIR, fname))

        n_words = sum(len(v) for v in entries.values())
        n_suppress = sum(len(v) for v in suppress.values())
        print(f'== {pack_id} ({meta["name"]}) ==')
        print(f'   {meta["description"]}')
        print(f'   読み {len(entries)} 件 / 表記 {n_words} 個 / 抑制 {n_suppress} 個')
        for reading, words in list(entries.items())[:5]:
            print(f'   {reading} -> {words}')
        if len(entries) > 5:
            print(f'   ... 他 {len(entries) - 5} 件')

        if report_only:
            continue

        json_path = os.path.join(SRCDIR, f'pack_{pack_id}.json')
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(entries, f, ensure_ascii=False, separators=(',', ':'))
        pack(f'pack_{pack_id}')
        manifest.append({
            'id': pack_id,
            'name': meta['name'],
            'description': meta['description'],
            'suppress': suppress,
        })

    if report_only:
        return

    # 端末側 (KeyboardController.loadVocabPackManifest) が読む一覧。
    # rawfile に直接置く -- 数百バイトなのでパックする意味がない。
    manifest_path = os.path.join(RAWFILE, 'pack_manifest.json')
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, separators=(',', ':'))
    print(f'pack_manifest.json: {[m["id"] for m in manifest]}')


if __name__ == '__main__':
    main()
