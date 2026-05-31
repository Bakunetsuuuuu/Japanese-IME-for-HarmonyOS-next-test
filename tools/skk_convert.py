#!/usr/bin/env python3
"""
Convert SKK-JISYO.L (EUC-JP) to dict.json for shunti IME.

Usage:
    python3 tools/skk_convert.py [input] [output]

Defaults:
    input  = /tmp/SKK-JISYO.L  (download from skk-dev/dict on GitHub)
    output = entry/src/main/resources/rawfile/dict.json

License note:
    SKK-JISYO is distributed under GPL v2 by the SKK Development Team.
    Source: https://github.com/skk-dev/dict
"""

import json
import re
import sys
import os

# For okuri-ari entries: consonant → kana suffix expansions.
# SKK stores verb/adjective stems with only the first consonant of okurigana.
# We expand to the most common conjugated forms so the full reading (stem+kana)
# can be typed in the IME and matched directly.
OKURI_EXPANSIONS: dict = {
    # Vowel okurigana (already the complete kana)
    'a': ['あ'],
    'i': ['い'],
    'u': ['う'],
    'e': ['え'],
    'o': ['お'],
    # Consonant rows — simple single-kana suffixes (always applied)
    'k': ['く', 'き', 'か'],
    'g': ['ぐ', 'ぎ', 'が'],
    's': ['す', 'し', 'さ'],
    'z': ['ず', 'じ'],
    'c': ['ち'],
    't': ['て', 'つ', 'た',           # 来た etc; 打て/打つ
          'った', 'って', 'てる'],    # godan-つ: 打った/打って/打てる
    'd': ['で', 'だ'],
    'n': ['ぬ', 'ん', 'に', 'んだ', 'んで'],
    'b': ['ぶ', 'び', 'ば', 'んだ', 'んで', 'べる'],
    'p': ['ぷ', 'ぴ'],
    'm': ['む', 'み', 'ま', 'んだ', 'んで', 'める'],
    'r': ['る', 'り', 'ら',
          'た', 'て', 'ます', 'たい',  # ichidan: 食べた/食べて/食べます/食べたい
          'ない', 'られる', 'れる',    # neg/potential/passive
          'った', 'って'],            # godan-る: 帰った/帰って
    'w': ['わ', 'い'],
    'h': ['ひ', 'は'],
    'y': ['よ', 'ゆ'],
    'j': ['じ'],
}

# Additional compound suffixes applied only when stem_kana length >= min_stem.
# This avoids false-positive entries from short/irregular stems (e.g. すs/酸/).
COMPOUND_OKURI: list = [
    # (consonant, min_stem_len, [compound_suffixes])
    ('k', 2, ['いた', 'いて', 'きたい']),   # 書く→書いた/書いて/書きたい
    ('g', 2, ['いだ', 'いで', 'ぎたい']),   # 泳ぐ→泳いだ/泳いで/泳ぎたい
    ('s', 2, ['した', 'して', 'したい', 'せる']),  # 話す→話した/話して/話したい/話せる
    ('k', 1, ['きたい']),    # 1-char stems too: 行きたい, 書きたい (godan-く desire)
    ('g', 1, ['ぎたい']),    # 泳ぎたい
]

HIRAGANA_RE = re.compile(r'^[ぁ-ん]+$')
MAX_CANDIDATES = 5


def strip_annotation(candidate: str) -> str:
    """Remove ;annotation and (注記) from SKK candidate string."""
    idx = candidate.find(';')
    if idx >= 0:
        candidate = candidate[:idx]
    # Also strip trailing parenthetical notes like (形)
    candidate = re.sub(r'\s*[\(（][^)）]*[\)）]\s*', '', candidate)
    return candidate.strip()


def parse_entry(line: str):
    """Parse one SKK dict line → (reading, [candidates]) or None."""
    sp = line.split(' ', 1)
    if len(sp) < 2:
        return None
    reading = sp[0].strip()
    rest = sp[1].strip()
    if not rest.startswith('/') or not rest.endswith('/'):
        return None
    raw_cands = rest[1:-1].split('/')
    candidates = []
    for c in raw_cands:
        c = strip_annotation(c)
        if c:
            candidates.append(c)
    return (reading, candidates[:MAX_CANDIDATES])


def convert(src: str) -> dict:
    with open(src, 'rb') as f:
        raw = f.read()
    text = raw.decode('euc-jp', errors='replace')

    result: dict = {}
    in_okuri_nasi = False

    for line in text.split('\n'):
        ls = line.strip()
        if not ls:
            continue
        if ls.startswith(';;'):
            if 'okuri-ari' in ls:
                in_okuri_nasi = False
            elif 'okuri-nasi' in ls:
                in_okuri_nasi = True
            continue

        parsed = parse_entry(ls)
        if not parsed:
            continue
        reading, candidates = parsed
        if not candidates:
            continue

        if in_okuri_nasi:
            # Keep only pure hiragana readings
            if not HIRAGANA_RE.match(reading):
                continue
            if reading not in result:
                result[reading] = []
            for c in candidates:
                if c not in result[reading]:
                    result[reading].append(c)
        else:
            # okuri-ari: reading = stem_kana + consonant_letter
            if not reading or not reading[-1].isascii() or reading[-1].isdigit():
                continue
            consonant = reading[-1].lower()
            stem_kana = reading[:-1]
            if not stem_kana or not HIRAGANA_RE.match(stem_kana):
                continue
            def add_expansion(stem: str, suf: str, cands: list) -> None:
                reading_key = stem + suf
                full_cands = [c + suf for c in cands]
                if reading_key not in result:
                    result[reading_key] = []
                for fc in full_cands:
                    if fc not in result[reading_key]:
                        result[reading_key].append(fc)
                result[reading_key] = result[reading_key][:MAX_CANDIDATES]

            expansions = OKURI_EXPANSIONS.get(consonant, [])
            for kana_suffix in expansions:
                add_expansion(stem_kana, kana_suffix, candidates)

            # Compound suffixes with optional minimum stem length
            stem_len = len(stem_kana)
            for (cons, min_stem, suffixes) in COMPOUND_OKURI:
                if consonant == cons and stem_len >= min_stem:
                    for kana_suffix in suffixes:
                        add_expansion(stem_kana, kana_suffix, candidates)

    return result


if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else '/tmp/SKK-JISYO.L'
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'entry/src/main/resources/rawfile/dict.json'
    )

    print(f'Input:  {src}')
    print(f'Output: {dst}')
    print('Converting ...')

    d = convert(src)
    print(f'Entries: {len(d):,}')

    out = json.dumps(d, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(out)
    size_kb = len(out.encode('utf-8')) / 1024
    print(f'Size:    {size_kb:.1f} KB')

    print('\nSpot-check:')
    checks = ['たべる', 'のむ', 'かく', 'はなす', 'よむ', 'かえる',
              'とうきょう', 'にほん', 'でんしゃ', 'きれい', 'あたらしい']
    for key in checks:
        val = d.get(key)
        if val:
            print(f'  {key}: {val[:4]}')
        else:
            print(f'  {key}: NOT FOUND')
