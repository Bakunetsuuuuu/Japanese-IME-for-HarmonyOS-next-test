#!/usr/bin/env python3
"""同梱する日本語フォント (rawfile/font/NotoSansJP-Regular.ttf) を作り直す。

元は Noto Sans JP の可変フォントから wght=400 で切り出した静的インスタンス。
そのままだと2つ問題があるので、ここで直してから同梱する。

  1. name テーブルが可変フォントの既定インスタンス (Thin) のまま残っている。
     字形と OS/2 は Regular (usWeightClass 400, 'I' のステム 92/1000) なのに、
     フォントの自己申告だけが "Noto Sans JP Thin"。registerFont は呼び出し側が
     渡すエイリアス (JP_FONT_FAMILY) で引くので今は実害が出ていないが、
     内部名で引く経路に当たった瞬間に「登録したのに効かない」に化ける。

  2. 縦書き用のメトリクス (vmtx/vhea) が入っている。このアプリは横書きしか
     描かないので丸ごと不要。約49KB。

■ 縮まない、という測定結果について

  「軽くするために字を減らす」は効かない。実測:

    フォントが持つ文字        11,058
      うちアプリが使う        11,057   ← 削れるのは 1 文字だけ
    アプリが出しうる文字      14,987   ← むしろフォント側が足りていない

  辞書 (dict.json / global_dict.json / mozc) が出せる漢字のうち 2,763 字は
  そもそもこのフォントに入っておらず、システムフォントに落ちている。
  つまりこの4MBは「盛りすぎ」ではなく、日本語の全文字を持つ最小に近い。

  glyf が 94.6% を占め、その中身は 12,331 グリフ / 1,227,142 点。
  ヒント命令は 0 バイト、複合グリフも 0 なので、削れる冗長分も無い。
  これ以上小さくするには字を捨てるしかなく、字を捨てると化ける。

  同じ理由で Bold の同梱はしない。太字1ウェイトで +4MB になる一方、
  得られるのは合成ボールドとの差だけ。IMEが払う額ではない。

Usage:
  python3 tools/build_jp_font.py <入力.ttf> [出力.ttf]
  引数なしなら同梱中のファイルをその場で作り直す。
"""
import sys
import os

from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLED = os.path.join(ROOT, 'entry/src/main/resources/rawfile/font/NotoSansJP-Regular.ttf')

FAMILY = 'Noto Sans JP'
SUBFAMILY = 'Regular'
FULL = 'Noto Sans JP'
POSTSCRIPT = 'NotoSansJP-Regular'

# 横書きしか描かないので不要。
DROP_TABLES = ['vmtx', 'vhea']


def build(src: str, dst: str) -> None:
    before = os.path.getsize(src)
    f = TTFont(src)

    # ---- name: 可変フォント既定インスタンス (Thin) の名残を消す ----
    # 1=Family, 2=Subfamily, 3=UniqueID, 4=FullName, 6=PostScriptName。
    # 16/17 (Typographic Family/Subfamily) は 1/2 と同じなら不要なので消す。
    name = f['name']
    for rec in list(name.names):
        if rec.nameID == 1:
            rec.string = FAMILY
        elif rec.nameID == 2:
            rec.string = SUBFAMILY
        elif rec.nameID == 4:
            rec.string = FULL
        elif rec.nameID == 6:
            rec.string = POSTSCRIPT
        elif rec.nameID == 3:
            rec.string = f'{FAMILY}; {POSTSCRIPT}'
    name.names = [r for r in name.names if r.nameID not in (16, 17)]

    # ---- 縦書きメトリクスを落とす ----
    dropped = []
    for tag in DROP_TABLES:
        if tag in f:
            del f[tag]
            dropped.append(tag)

    f.save(dst)
    after = os.path.getsize(dst)
    print(f'{os.path.relpath(dst, ROOT)}')
    print(f'  {before:,} -> {after:,} バイト ({after - before:+,})')
    print(f'  落としたテーブル: {", ".join(dropped) if dropped else "なし"}')


def verify(src: str, dst: str) -> int:
    """字形が1つも変わっていないことを確認する。ここが本体。"""
    a, b = TTFont(src), TTFont(dst)
    ga, gb = a.getGlyphOrder(), b.getGlyphOrder()
    ca, cb = a.getBestCmap(), b.getBestCmap()
    bad = 0

    if len(ga) != len(gb):
        print(f'  NG グリフ数 {len(ga)} -> {len(gb)}')
        bad += 1
    else:
        print(f'  OK グリフ数 {len(gb):,}')

    if ca.keys() != cb.keys():
        print(f'  NG cmap の文字数 {len(ca)} -> {len(cb)}')
        bad += 1
    else:
        print(f'  OK cmap {len(cb):,} 文字')

    # 全グリフの輪郭を突き合わせる (点1つでも動いていたら落とす)
    glyf_a, glyf_b = a['glyf'], b['glyf']
    diff = 0
    for n in ga:
        pa, pb = glyf_a[n], glyf_b[n]
        if pa.numberOfContours != pb.numberOfContours:
            diff += 1
            continue
        if pa.numberOfContours <= 0:
            continue
        if pa.getCoordinates(glyf_a)[0] != pb.getCoordinates(glyf_b)[0]:
            diff += 1
    if diff:
        print(f'  NG 輪郭が変わったグリフ {diff}')
        bad += 1
    else:
        print(f'  OK 輪郭は全 {len(ga):,} グリフ一致')

    if a['hmtx'].metrics != b['hmtx'].metrics:
        print('  NG 横メトリクスが変わった')
        bad += 1
    else:
        print('  OK 横メトリクス一致')

    w = b['OS/2'].usWeightClass
    print(f'  {"OK" if w == 400 else "NG"} usWeightClass {w}')
    if w != 400:
        bad += 1

    names = {r.nameID: str(r) for r in b['name'].names}
    for nid, want in ((1, FAMILY), (2, SUBFAMILY), (6, POSTSCRIPT)):
        got = names.get(nid)
        print(f'  {"OK" if got == want else "NG"} name {nid} = {got}')
        if got != want:
            bad += 1

    for tag in DROP_TABLES:
        print(f'  {"OK" if tag not in b else "NG"} {tag} 削除')
        if tag in b:
            bad += 1

    return bad


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else BUNDLED
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    tmp = dst + '.tmp'
    build(src, tmp)
    print('検証:')
    bad = verify(src, tmp)
    if bad:
        os.remove(tmp)
        print(f'\n{bad} 件の不一致。出力を破棄した。')
        sys.exit(1)
    os.replace(tmp, dst)
    print('\nOK')


if __name__ == '__main__':
    main()
