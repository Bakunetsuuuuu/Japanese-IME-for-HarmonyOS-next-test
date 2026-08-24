#!/usr/bin/env python3
"""tools/vocab_packs/*.tsv (誰でもPRで足せる素の読み/単語/優先度) を、
tools/dict_src/pack_<id>.json に変換し、pack_dicts.py と同じパック形式で
rawfile/ に書き出す。

なぜ TSV か
-----------
DICTIONARY (KanaKanjiConverter.ets 内の巨大オブジェクトリテラル) に直接
書き足す形だと、コードを読める人にしか語彙パックへの貢献ができない。
読み/単語/優先度だけの3列にすることで、TypeScript も辞書パッキングの
仕組みも知らない人でも1行足すだけで貢献できるようにしてある。

フォーマット (各 .tsv ファイル1つ = 1パック、ファイル名がパックID):

    読み<TAB>単語<TAB>優先度

  - # で始まる行、空行は無視する
  - 同じ読みが複数行あってよい。優先度が大きい方が候補の前に出る
    (同点なら書いた順)
  - 優先度は省略可 (省略時は 0 として扱う)

Usage:
  python3 tools/build_vocab_packs.py            全パックをビルド
  python3 tools/build_vocab_packs.py --report    読み込むだけで内容を表示
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS_DIR = os.path.join(HERE, 'vocab_packs')
SRCDIR = os.path.join(HERE, 'dict_src')

sys.path.insert(0, HERE)
from pack_dicts import pack  # noqa: E402  (再利用: 同じバイナリ形式で書き出す)


def parse_tsv(path):
    entries = {}  # reading -> [(priority, order, word), ...]
    order = 0
    with open(path, encoding='utf-8') as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            cols = line.split('\t')
            if len(cols) < 2:
                raise SystemExit(f'{path}:{lineno}: 読み<TAB>単語 が無い行: {line!r}')
            reading = cols[0].strip()
            word = cols[1].strip()
            priority = int(cols[2].strip()) if len(cols) >= 3 and cols[2].strip() else 0
            if not reading or not word:
                raise SystemExit(f'{path}:{lineno}: 読み/単語が空: {line!r}')
            entries.setdefault(reading, []).append((priority, order, word))
            order += 1
    out = {}
    for reading, words in entries.items():
        words.sort(key=lambda t: (-t[0], t[1]))
        seen = []
        for _, _, w in words:
            if w not in seen:
                seen.append(w)
        out[reading] = seen
    return out


def main():
    report_only = '--report' in sys.argv
    if not os.path.isdir(PACKS_DIR):
        raise SystemExit('missing ' + PACKS_DIR)
    if not report_only:
        os.makedirs(SRCDIR, exist_ok=True)

    pack_ids = []
    for fname in sorted(os.listdir(PACKS_DIR)):
        if not fname.endswith('.tsv'):
            continue
        pack_id = fname[:-4]
        entries = parse_tsv(os.path.join(PACKS_DIR, fname))
        print(f'== {pack_id} == {len(entries)} 読み')
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
        pack_ids.append(pack_id)

    if not report_only:
        manifest_path = os.path.join(SRCDIR, 'pack_manifest.json')
        with open(manifest_path, 'w', encoding='utf-8') as f:
            json.dump(sorted(pack_ids), f, ensure_ascii=False)
        print(f'pack_manifest.json: {sorted(pack_ids)}')


if __name__ == '__main__':
    main()
