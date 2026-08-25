#!/usr/bin/env python3
"""同梱する日本語フォント (rawfile/font/*.ttf) を作り直す。

元の (可変または静的な) フォントを wght=400 の静的フォントとして切り出し、
このアプリが実際に描く文字だけに絞って同梱する。ソースフォント自身の
name テーブルからファミリ名を読むので、フォント自体の差し替えにも
そのまま使える (現在の同梱フォント → 新フォント の乗り換え時は、切り出し後に
JpFont.ets の JP_FONT_FAMILY / registerFont の呼び出し元と、rawfile 側の
ファイル名参照も合わせて直すこと)。

  現在のフォント: BIZ UDPGothic (Morisawa, SIL OFL 1.1)
    元データ: https://github.com/google/fonts
              ofl/bizudpgothic/BIZUDPGothic-Regular.ttf
    2026-08-25、Noto Sans JP から乗り換え (「若干ダサさがある」との指摘で
    丸み・ポップ系へ)。乗り換え時の文字カバレッジ確認: このアプリが実際に
    使う文字 4,088 字中、BIZ UDPGothic に無いもの 106 字 (☀⛄✅ 等の記号
    パネル用ピクトグラム系が大半、CJK は佫崈朢鿿𠮷 の5字のみ)。ピクトグラム
    系はシステムフォントへ落ちても字形が漢字のように国・地域で変わる文字
    ではないので実害は小さいと判断し許容した。

  过去のフォント: Noto Sans JP (Google, SIL OFL 1.1)
    元データ: ofl/notosansjp/NotoSansJP[wght].ttf (可変フォント)

■ なぜ絞るか

このアプリが自分で描く文字 (UI文字列・記号パネル・辞書の表記) だけに
絞らないと、必要な文字が同梱フォントから漏れてシステムフォントに落ちる。
記号や矢印は字形が変わるだけだが、漢字はシステムフォント = 地域によっては
簡体字の字形になるので、日本語フォントを同梱している目的そのものが崩れる。
逆に絞りすぎても同じ穴が開くので、「今の同梱フォントの収録字」と「アプリが
実際に描く字」の和集合を必ずカバーするようにしてある (乗り換え時は前者が
別フォントの収録字になるので、上のカバレッジ確認のような目視チェックが要る)。

絵文字はシステムの絵文字フォントが描くので入れない (入れると数MB増えて、
しかも大抵は白黒になる)。縦書き用の vmtx/vhea は横書きしか描かないので
落とす。

Usage:
  # 元のフォントを取ってくる (一度だけ)
  curl -sSLo /tmp/src.ttf '<Google FontsのRAWリンク>'
  python3 tools/build_jp_font.py /tmp/src.ttf rawfile/font/<出力ファイル名>.ttf

  # 今と同じフォントを再ビルドしたいだけなら (通常の再ビルド):
  python3 tools/build_jp_font.py /tmp/src.ttf
"""
import glob
import json
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAWFILE = os.path.join(ROOT, 'entry/src/main/resources/rawfile')
DEFAULT_BUNDLED = os.path.join(RAWFILE, 'font/BIZUDPGothic-Regular.ttf')

# 横書きしか描かないので不要。
DROP_TABLES = ['vmtx', 'vhea']

# 辞書ソース (表記だけ拾う。読みはかななので文字集合に足しても増えない)
DICT_FILES = ['dict.json', 'global_dict.json', 'mozc_dict_surfaces.json']


def is_emoji(cp: int) -> bool:
    """絵文字だけを外す。範囲を広く取りすぎないこと。

    ここを `cp >= 0x1F000` と `0x2600..0x27BF` にしていたら、CJK拡張B
    (𠮟 U+20B9F, 𩸽 U+29E3D …) と ★ ♪ ♭ ♯ ☆ ♂ ♀ まで巻き込んで落ちていた。
    前者は JIS X 0213 の日本語、後者は記号パネルが出す文字で、どちらも要る。
    """
    return 0x1F000 <= cp <= 0x1FAFF


def app_charset() -> set:
    """アプリが画面に出しうる文字。UI文字列 (記号パネルの中身を含む) と辞書の表記。"""
    out = set()
    for p in glob.glob(os.path.join(ROOT, 'entry/src/main/ets/**/*.ets'), recursive=True):
        with open(p, encoding='utf-8') as f:
            out |= set(ord(c) for c in f.read())
    for name in DICT_FILES:
        path = os.path.join(RAWFILE, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding='utf-8') as f:
            d = json.load(f)
        for v in (d.values() if isinstance(d, dict) else d):
            for s in (v if isinstance(v, list) else [v]):
                if isinstance(s, str):
                    out |= set(ord(c) for c in s)
    return {c for c in out if not is_emoji(c) and c > 0x20}


def read_names(f: TTFont):
    """ソースフォント自身の name テーブルから family/subfamily/postscript を読む。"""
    names = {r.nameID: str(r) for r in f['name'].names if r.platformID == 3}
    family = names.get(1, 'Unknown')
    subfamily = names.get(2, 'Regular')
    postscript = names.get(6, family.replace(' ', '') + '-' + subfamily)
    return family, subfamily, postscript


def fix_names(f: TTFont, family: str, subfamily: str, postscript: str) -> None:
    """可変フォントの既定インスタンス名の残骸や、機種依存の重複レコードを消す。"""
    name = f['name']
    for rec in list(name.names):
        if rec.nameID == 1:
            rec.string = family
        elif rec.nameID == 2:
            rec.string = subfamily
        elif rec.nameID == 3:
            rec.string = f'{family}; {postscript}'
        elif rec.nameID == 4:
            rec.string = family
        elif rec.nameID == 6:
            rec.string = postscript
    name.names = [r for r in name.names if r.nameID not in (16, 17, 25)]


def report_coverage(target: set, new_cmap: set) -> None:
    """target のうち新フォントに無い文字を一覧する (フォント乗り換え時の目視確認用)。

    無くても subset 自体は失敗しない (fontTools が黙って落とすだけ) ので、
    ここで明示的に出さないと気付かないまま欠落する。
    """
    missing = sorted(target - new_cmap)
    if not missing:
        print('  カバレッジ: 不足なし')
        return
    print(f'  カバレッジ: 新フォントに無い文字 {len(missing)} 字 (黙ってシステム'
          f'フォントへ落ちる。CJK漢字が混じっていないか要確認)')
    print('     ' + ''.join(chr(c) for c in missing[:120]))


def verify(new_path: str, family: str, subfamily: str, postscript: str) -> int:
    b = TTFont(new_path)
    bad = 0

    w = b['OS/2'].usWeightClass
    print(f'  {"OK" if w == 400 else "NG"} usWeightClass {w}')
    bad += (w != 400)

    names = {r.nameID: str(r) for r in b['name'].names}
    for nid, want in ((1, family), (2, subfamily), (6, postscript)):
        ok = names.get(nid) == want
        print(f'  {"OK" if ok else "NG"} name {nid} = {names.get(nid)}')
        bad += (not ok)

    for tag in DROP_TABLES:
        print(f'  {"OK" if tag not in b else "NG"} {tag} 削除')
        bad += (tag in b)

    for tag in ('cmap', 'glyf', 'loca', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post'):
        if tag not in b:
            print(f'  NG 必須テーブル {tag} が無い')
            bad += 1
    return bad


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    src = sys.argv[1]
    bundled = os.path.join(ROOT, sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_BUNDLED
    os.makedirs(os.path.dirname(bundled), exist_ok=True)

    tmp_static = bundled + '.static.tmp'
    tmp_out = bundled + '.tmp'
    charfile = bundled + '.chars.tmp'

    want = app_charset()
    have = set(TTFont(bundled).getBestCmap()) if os.path.exists(bundled) else set()
    # 今の同梱フォントの収録字を必ず含める -> 同じフォントの再ビルドなら
    # 出ている字が1つも消えない。フォント乗り換え直後 (bundled がまだ旧
    # フォントのまま) は「旧フォントで出ていた字」を足す形になり、新フォント
    # 側の不足を report_coverage で洗い出せる。
    target = want | have
    print(f'現在の同梱フォント {len(have):,} 字')
    print(f'アプリが描く字 (絵文字除く) {len(want):,} 字')
    print(f'subset 目標 {len(target):,} 字')

    with open(charfile, 'w', encoding='utf-8') as f:
        f.write(''.join(chr(c) for c in sorted(target)))

    src_font = TTFont(src)
    if 'fvar' in src_font:
        static = instancer.instantiateVariableFont(src_font, {'wght': 400}, inplace=False)
    else:
        static = src_font
    family, subfamily, postscript = read_names(static)
    static.save(tmp_static)

    subset.main([
        tmp_static, f'--output-file={tmp_out}', f'--text-file={charfile}',
        '--layout-features=*', '--drop-tables+=' + ','.join(DROP_TABLES),
        '--no-hinting', '--name-IDs=*', '--legacy-kern', '--notdef-outline',
    ])
    f = TTFont(tmp_out)
    fix_names(f, family, subfamily, postscript)
    f.save(tmp_out)

    out_font = TTFont(tmp_out)
    new_cmap = set(out_font.getBestCmap())

    before = os.path.getsize(bundled) if os.path.exists(bundled) else 0
    after = os.path.getsize(tmp_out)
    print(f'\n{family} ({subfamily})')
    print(f'{before:,} -> {after:,} バイト ({after - before:+,})')
    print('検証:')
    bad = verify(tmp_out, family, subfamily, postscript)
    report_coverage(target, new_cmap)
    for p in (tmp_static, charfile):
        if os.path.exists(p):
            os.remove(p)
    if bad:
        os.remove(tmp_out)
        print(f'\n{bad} 件の不一致。出力を破棄した。')
        sys.exit(1)
    os.replace(tmp_out, bundled)
    print(f'\nOK -> {os.path.relpath(bundled, ROOT)}')


if __name__ == '__main__':
    main()
