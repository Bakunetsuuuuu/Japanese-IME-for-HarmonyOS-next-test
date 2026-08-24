#!/usr/bin/env python3
"""主要な地名 (現行自治体・駅名の基底) を地名パックから常時引ける側へ戻す。

なぜ
----
build_place_packs.py は郵便番号データの町域名を地方別パックへ切り出すが、
「その町域名が同時に自治体名でもある」「駅名の基底でもある」ことまでは
見ていない。結果として次の穴が開いていた:

  - 播磨町・小野町・清里町 のような**現行の自治体名**が、その地方の
    パックを切ると引けなくなる。
  - 小伝馬町 (東京メトロ) が中部・近畿のパックにしか無い、
    永福町 (京王) が中部・北海道にしか無い、といった具合に、
    **駅の所在地とは無関係な地方**のパックに入る。郵便データ上
    同じ町域名が他県にあると、そちらの地方に割り振られるため。
    関東の利用者が中部を切ると、東京の駅名が消える。

地方を切るのは「その地方の細かい町名は要らない」という意思表示であって、
「主要な自治体名や駅名も消していい」ではない。そこでこの2種類だけを
パックから抜いて global_dict へ戻す (＝常時引ける)。実測で137件しか
無いので、全員が常に持っていても負担にならない。

駅名そのもの (「米原駅」) は登録しない。基底の地名 (「米原」) さえ
引ければ 地名＋駅 で組めるし、駅名を単位で登録すると
「地名+駅でいいところを駅名で登録している」重複が大量に増える
(以前それで7,486件を消している)。

データ元
--------
Wikidata (CC0)。SPARQL は下の QUERY_* にそのまま置いてある。
  - 現行自治体: 廃止日 (P576) を持たない「日本の市町村」とその下位クラス
  - 駅: 日本の鉄道駅のうち、かな表記 (P1814) を持つもの

使い方
------
    python3 tools/build_place_core.py --report   何が動くか見るだけ
    python3 tools/build_place_core.py            実行

    そのあと必ず:
    python3 tools/pack_dicts.py          # global_dict を詰め直す
    python3 tools/build_vocab_packs.py   # 地名パックをバイナリ化

取得結果は --cache のディレクトリに残るので、2回目以降は通信しない。
"""
import argparse
import csv
import glob
import io
import json
import os
import re
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS_DIR = os.path.join(HERE, 'vocab_packs')
GLOBAL_DICT = os.path.join(HERE, 'dict_src', 'global_dict.json')
DEFAULT_CACHE = os.path.join(HERE, '.cache', 'wikidata')
ENDPOINT = 'https://query.wikidata.org/sparql'
UA = 'shunti-ime-dict/1.0 (https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next)'

# 現行の市区町村。P576 (廃止日) を持つものは明治期の廃止村などなので外す
# (付けないと1.7万件になり、「主要」の意味が消える)。
QUERY_MUNI = """
SELECT DISTINCT ?s ?kana WHERE {
  ?m wdt:P31/wdt:P279* wd:Q1054813 ; wdt:P17 wd:Q17 ; wdt:P1814 ?kana ; rdfs:label ?s .
  FILTER(LANG(?s)="ja")
  FILTER NOT EXISTS { ?m wdt:P576 ?d }
}
"""

# 日本の鉄道駅で、かな表記を持つもの。表記から「駅」、読みから「えき」を
# 落として基底の地名を取る。
QUERY_STATION = """
SELECT DISTINCT ?s ?kana WHERE {
  ?st wdt:P31/wdt:P279* wd:Q55488 ; wdt:P17 wd:Q17 ; wdt:P1814 ?kana ; rdfs:label ?s .
  FILTER(LANG(?s)="ja")
}
"""

HIRAGANA = re.compile(r'^[ぁ-んー]+$')


def fetch(query, cache_path):
    if os.path.exists(cache_path):
        return cache_path
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    url = ENDPOINT + '?' + urllib.parse.urlencode({'query': query})
    req = urllib.request.Request(url, headers={'Accept': 'text/csv', 'User-Agent': UA})
    print(f'  Wikidata へ問い合わせ: {os.path.basename(cache_path)}')
    with urllib.request.urlopen(req, timeout=300) as r:
        data = r.read()
    with open(cache_path, 'wb') as f:
        f.write(data)
    return cache_path


def read_pairs(path):
    with io.open(path, encoding='utf-8') as f:
        return [(r['kana'], r['s']) for r in csv.DictReader(f)]


def station_bases(pairs):
    """「米原駅 / まいばらえき」 -> ("まいばら", "米原")。"""
    out = set()
    for kana, surface in pairs:
        if not surface.endswith('駅') or not kana.endswith('えき'):
            continue
        base, base_kana = surface[:-1], kana[:-2]
        if len(base) < 2 or not HIRAGANA.match(base_kana):
            continue
        out.add((base_kana, base))
    return out


def surfaces(v):
    return v if isinstance(v, list) else [v]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cache', default=DEFAULT_CACHE, help='Wikidata の取得結果を置く場所')
    ap.add_argument('--report', action='store_true', help='何が動くか見るだけ (書き換えない)')
    args = ap.parse_args()

    muni = set(read_pairs(fetch(QUERY_MUNI, os.path.join(args.cache, 'municipalities.csv'))))
    stations = read_pairs(fetch(QUERY_STATION, os.path.join(args.cache, 'stations.csv')))
    bases = station_bases(stations)
    print(f'現行自治体 {len(muni):,} / 駅 {len(stations):,} → 基底の地名 {len(bases):,}')

    with io.open(GLOBAL_DICT, encoding='utf-8') as f:
        gd = json.load(f)

    packs = {}
    for path in sorted(glob.glob(os.path.join(PACKS_DIR, 'place_*.pack'))):
        header, body = [], []
        in_body = False
        for line in io.open(path, encoding='utf-8').read().split('\n'):
            if not in_body:
                header.append(line)
                if line.strip() == '---':
                    in_body = True
                continue
            if line.strip():
                body.append(line)
        packs[path] = (header, body)

    core = muni | bases
    moved, kept = {}, 0
    for path, (_header, body) in packs.items():
        for line in body:
            cols = line.split('\t')
            if len(cols) < 2:
                continue
            reading, surface = cols[0], cols[1]
            if (reading, surface) in core:
                moved.setdefault((reading, surface), set()).add(os.path.basename(path))
            else:
                kept += 1

    # global_dict に既にあるものは触らない (表記の並びを壊さないため)。
    new = {k: v for k, v in moved.items() if k[1] not in surfaces(gd.get(k[0], []))}
    print(f'\n地名パックの延べ語数 {kept + sum(len(v) for v in moved.values()):,}')
    print(f'  常時引けるべきもの   {len(moved):,} (自治体 {len(moved.keys() & muni):,} / '
          f'駅の基底 {len(moved.keys() & bases):,})')
    print(f'  うち global_dict へ新規に足すもの {len(new):,}')

    if args.report:
        for (r, s), where in sorted(new.items())[:30]:
            print(f'   {r:18} {s:10} {",".join(sorted(x[6:-5] for x in where))}')
        print('\n--report なので何も書き換えていない。')
        return

    for (reading, surface) in new:
        cur = surfaces(gd.get(reading, []))
        gd[reading] = list(cur) + [surface]
    with io.open(GLOBAL_DICT, 'w', encoding='utf-8') as f:
        json.dump(gd, f, ensure_ascii=False, separators=(',', ':'))
    print(f'global_dict.json: {len(gd):,} 読み')

    for path, (header, body) in packs.items():
        out = [l for l in body
               if len(l.split('\t')) < 2 or (l.split('\t')[0], l.split('\t')[1]) not in core]
        with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(header + out) + '\n')
        print(f'  {os.path.basename(path)}: {len(body):,} -> {len(out):,} 行')

    print('\n次に実行すること: python3 tools/pack_dicts.py && python3 tools/build_vocab_packs.py')


if __name__ == '__main__':
    main()
