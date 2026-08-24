#!/usr/bin/env python3
"""global_dict の町域名を地方別の語彙パックへ切り出す。

なぜ
----
global_dict の 27万読みのうち約 2.3万 (8%) が郵便番号データ由来の町域名で、
その大半は住んでいる地域以外では一生使わない。全員が全国分を常に抱える
必要は無いので、8地方のパックに分けて要らない地方を切れるようにする。

地名の判定を接尾辞 (町/村/丁目) だけでやると 拡張漢字・英数字・黒文字・
企業城下町 のような一般語を巻き込む。そこで日本郵便が公開している
都道府県別の郵便番号データと**表記・読みの両方**を突き合わせ、
一致したものだけを地名と確定する (実測で対象の 95.8% が一致した)。
都道府県はファイル名 (13tokyo.zip 等) ではなくレコード内の都道府県欄から
取るので、市区町村の再編があっても追随できる。

桜木町 のように複数の地方に実在する地名は、該当するすべての地方の
パックに入れる (どの地方を有効にしていても引ける)。

使い方
------
1. 郵便番号データ (都道府県別) を落として1つのディレクトリに展開する。
   https://www.post.japanpost.jp/service/search/zipcode/download/kogaki-zip.html
   ※ 全国一括 (ken_all.zip) は 2026-08 時点で 404 だったため県別を使う。

     python3 tools/build_place_packs.py --ken <展開先ディレクトリ> --report
     python3 tools/build_place_packs.py --ken <展開先ディレクトリ>

2. そのあと必ず以下を実行して、生成物を反映する:

     python3 tools/pack_dicts.py          # global_dict を詰め直す
     python3 tools/build_vocab_packs.py   # 地名パックをバイナリ化

--report は何が動くか見るだけで、ファイルは一切書き換えない。
"""
import argparse
import collections
import csv
import glob
import io
import json
import os
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS_DIR = os.path.join(HERE, 'vocab_packs')
GLOBAL_DICT = os.path.join(HERE, 'dict_src', 'global_dict.json')

# 8地方区分。パックIDと表示名。
REGIONS = [
    ('hokkaido', '北海道', ['北海道']),
    ('tohoku', '東北', ['青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県']),
    ('kanto', '関東', ['茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県']),
    ('chubu', '中部', ['新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県',
                       '岐阜県', '静岡県', '愛知県']),
    ('kinki', '近畿', ['三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県']),
    ('chugoku', '中国', ['鳥取県', '島根県', '岡山県', '広島県', '山口県']),
    ('shikoku', '四国', ['徳島県', '香川県', '愛媛県', '高知県']),
    ('kyushu', '九州・沖縄', ['福岡県', '佐賀県', '長崎県', '熊本県', '大分県',
                              '宮崎県', '鹿児島県', '沖縄県']),
]
PREF_TO_REGION = {p: rid for rid, _, prefs in REGIONS for p in prefs}
REGION_NAME = {rid: name for rid, name, _ in REGIONS}

# 町域名として扱う接尾辞。字 は 漢字/文字/数字/英数字 を巻き込むので入れない
# (郵便データ照合で弾けるが、そもそも候補に上げない方が安全)。
TOWN_SUFFIX = ('町', '村', '丁目')


def to_hiragana(s):
    """半角カナ (郵便データの読み欄) をひらがなに揃える。"""
    s = unicodedata.normalize('NFKC', s)
    return ''.join(chr(ord(c) - 0x60) if 'ァ' <= c <= 'ヶ' else c for c in s)


def load_postal(ken_dir):
    """町域名 -> {都道府県}, 読み -> {都道府県} を作る。"""
    files = sorted(glob.glob(os.path.join(ken_dir, '*.CSV')) +
                   glob.glob(os.path.join(ken_dir, '*.csv')))
    if not files:
        raise SystemExit(f'郵便番号データの CSV が見つからない: {ken_dir}')
    town, reading = {}, {}
    for path in files:
        with io.open(path, encoding='cp932', errors='replace') as f:
            for row in csv.reader(f):
                if len(row) < 9:
                    continue
                pref, name, yomi = row[6], row[8], to_hiragana(row[5])
                # 「以下に掲載がない場合」等は町域名ではない。
                if '掲載がない' in name or '次のビル' in name:
                    continue
                name = name.split('（')[0].strip()
                if not name:
                    continue
                town.setdefault(name, set()).add(pref)
                if yomi:
                    reading.setdefault(yomi, set()).add(pref)
    return town, reading, len(files)


def surfaces(v):
    return v if isinstance(v, list) else [v]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ken', required=True, help='郵便番号データ(県別CSV)を展開したディレクトリ')
    ap.add_argument('--report', action='store_true', help='何が動くか見るだけ (書き換えない)')
    args = ap.parse_args()

    town, reading, nfiles = load_postal(args.ken)
    print(f'郵便番号データ: {nfiles} ファイル / 町域名 {len(town):,} 種 / 読み {len(reading):,} 種')

    with open(GLOBAL_DICT, encoding='utf-8') as f:
        gd = json.load(f)
    before = len(gd)

    # 地方 -> 読み -> [表記]
    picked = {rid: {} for rid, _, _ in REGIONS}
    remove = []
    unmatched = 0
    for r, v in gd.items():
        ss = surfaces(v)
        # 候補が複数ある読みは一般語と衝突している可能性があるので触らない。
        if len(ss) != 1:
            continue
        s = ss[0]
        if len(s) < 3 or not s.endswith(TOWN_SUFFIX):
            continue
        prefs = town.get(s)
        # 表記・読みの両方が郵便データに無いものは地名と断定しない。
        if not prefs or r not in reading:
            unmatched += 1
            continue
        regions = {PREF_TO_REGION[p] for p in prefs if p in PREF_TO_REGION}
        if not regions:
            continue
        for rid in regions:
            picked[rid].setdefault(r, [])
            if s not in picked[rid][r]:
                picked[rid][r].append(s)
        remove.append(r)

    print(f'\nglobal_dict: {before:,} 読み')
    print(f'  町域名と確定して切り出す: {len(remove):,}')
    print(f'  接尾辞は合うが郵便データに無い (触らない): {unmatched:,}')
    print(f'  残る読み: {before - len(remove):,}')
    print('\n地方別:')
    for rid, name, _ in REGIONS:
        n = len(picked[rid])
        print(f'  {name:8} ({rid:9}) {n:6,} 読み')

    if args.report:
        print('\n--report なので何も書き換えていない。')
        return

    for rid, name, _ in REGIONS:
        entries = picked[rid]
        if not entries:
            continue
        path = os.path.join(PACKS_DIR, f'place_{rid}.pack')
        with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write('# tools/build_place_packs.py が生成。手で編集しない。\n')
            f.write('# 元データ: 日本郵便 郵便番号データ (町域名)。\n')
            f.write(f'name: 地名 - {name}\n')
            f.write(f'description: {name}の町域名 ({len(entries):,}語)。使わない地方は切れます\n')
            # 既定はONにする。今まで global_dict にあって普通に引けていたので、
            # 更新しただけで引けなくなるのは利用者から見れば機能の後退になる。
            f.write('default: on\n')
            # 全語が地名なので、パック全体の既定品詞として1回だけ指定する。
            # 1語ずつ書くと manifest が語数ぶん膨らむ (2万語で 1.6MB になった)。
            f.write('pos: 地名\n')
            f.write('---\n')
            for r in sorted(entries):
                for s in entries[r]:
                    # 町域名は一般語より前に出したくないので優先度は低め(8)。
                    f.write(f'{r}\t{s}\t8\n')
        print(f'  書き出し: {os.path.relpath(path, HERE)}')

    for r in remove:
        gd.pop(r, None)
    with open(GLOBAL_DICT, 'w', encoding='utf-8') as f:
        json.dump(gd, f, ensure_ascii=False, separators=(',', ':'))
    print(f'\nglobal_dict.json を書き換えた: {before:,} -> {len(gd):,} 読み')
    print('次に実行すること: python3 tools/pack_dicts.py && python3 tools/build_vocab_packs.py')


if __name__ == '__main__':
    main()
