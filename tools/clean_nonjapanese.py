#!/usr/bin/env python3
"""dict.json / global_dict.json から「日本語で使わない漢字」の項目を落とす。

見つかった経緯: 同梱フォント (Noto Sans JP) に無い文字を数えたら 2,777 字も
出てきた。Noto Sans JP は日本語をほぼ網羅しているので、それだけ足りないのは
おかしい ── 実際おかしかったのはフォントではなく辞書の方だった。

    「ほう」 → 㵗 䏾 䨻 䶌 乓 佨 僼 儤 凤 勽 匉 吥 哹 嗙 嘭 … (31件)
    「げち」 → 呚 嗐 堨 奊 尳 嵥 嵲 嶭 忦 捾 掜 搳 摰 擖 敌 … (30件)

Unihan の kJapaneseOn (全CJK文字に付いている「音読み」フィールド) を読みキーと
して取り込んだ跡。中国語専用字 (凤 敌 杀 尘 备 帅 术 阳 锄头 …) まで日本語の
音読みで引けてしまう。ユーザーが「ほう」と打つと、法/方/報/包… の後ろに読めない
字が31個ぶら下がる。

■ 判定基準

JIS X 0213:2004 (euc_jis_2004 で符号化できるか) に入らない CJK 統合漢字を
含む表記を落とす。日本語の文字集合の定義そのものなので、恣意的な線引きに
ならない。安全側に倒すため:

  - 対象は CJK 統合漢字/拡張/互換漢字のみ。絵文字・記号・ラテン等は触らない
    (JIS X 0213 に無い文字が他にもあるが、それらは正当に使う)
  - 候補の一部だけが対象文字を含む場合は、その候補だけを落として読みは残す
  - 候補が全部対象文字だった場合は、読みそのものを丸ごと削除する。中途半端に
    残すと「その読みでは読めない1文字だけが出る」という一番タチの悪い状態に
    なる (例: dict.json の「ねばつち」→堇 だけ、のような項目が30件あった)。
    読みごと消えれば hybrid エンジンの mozc 側や生のかな確定にフォールバック
    するだけなので、変換不能になるわけではない。

パッキング前の生JSON (tools/dict_src/) を対象にする -- rawfile/ 側は
pack_dicts.py が作るバイナリ形式のみで、平文JSONはもう置かれていない。
書き換えたら tools/pack_dicts.py で rawfile/ を作り直すこと。

Usage:
  python3 tools/clean_nonjapanese.py --report   何が落ちるかだけ出す
  python3 tools/clean_nonjapanese.py            実際に dict_src/ の両方を書き換える
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICTS = [
    os.path.join(ROOT, 'tools/dict_src/dict.json'),
    os.path.join(ROOT, 'tools/dict_src/global_dict.json'),
]


def is_cjk(ch: str) -> bool:
    o = ord(ch)
    return (0x3400 <= o <= 0x4DBF or 0x4E00 <= o <= 0x9FFF
            or 0xF900 <= o <= 0xFAFF or 0x20000 <= o <= 0x3FFFF)


def in_jis(ch: str) -> bool:
    """JIS X 0213:2004 で符号化できる = 日本語の標準文字集合に入っている"""
    try:
        ch.encode('euc_jis_2004')
        return True
    except Exception:
        return False


def is_foreign(surface: str) -> bool:
    return any(is_cjk(ch) and not in_jis(ch) for ch in surface)


def clean_one(path: str, report_only: bool) -> None:
    name = os.path.basename(path)
    with open(path, encoding='utf-8') as f:
        d = json.load(f)

    out = {}
    dropped = []           # (reading, surface) -- 候補の一部だけ落とした
    removed_readings = []  # (reading, surfaces) -- 候補が全部対象で読みごと削除
    for reading, v in d.items():
        surfaces = v if isinstance(v, list) else [v]
        keep = [s for s in surfaces if not is_foreign(s)]
        drop = [s for s in surfaces if is_foreign(s)]
        if drop and not keep:
            # この読みの候補が全部対象文字 -> 読みごと削除
            removed_readings.append((reading, drop))
            continue
        for s in drop:
            dropped.append((reading, s))
        out[reading] = keep if isinstance(v, list) else keep[0]

    print(f'== {name} ==')
    print(f'読み          {len(d):,} -> {len(out):,}')
    print(f'落とす表記    {len(dropped):,} (読みは残る)')
    print(f'削除する読み  {len(removed_readings):,} (候補が全部対象文字だった)')

    chars = set()
    for _, s in dropped:
        for ch in s:
            if is_cjk(ch) and not in_jis(ch):
                chars.add(ch)
    for _, ss in removed_readings:
        for s in ss:
            for ch in s:
                if is_cjk(ch) and not in_jis(ch):
                    chars.add(ch)
    print(f'消える文字種  {len(chars):,}')

    print('-- 候補だけ落とす例 --')
    for r, s in dropped[:15]:
        print(f'   {r:12s} {s}')
    if removed_readings:
        print('-- 読みごと削除する例 --')
        for r, ss in removed_readings[:10]:
            print(f'   {r:12s} {" ".join(ss)}')
    print()

    if report_only:
        return

    before = os.path.getsize(path)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    after = os.path.getsize(path)
    print(f'{name} {before:,} -> {after:,} バイト ({after - before:+,})\n')


def main() -> None:
    report_only = '--report' in sys.argv
    for path in DICTS:
        clean_one(path, report_only)


if __name__ == '__main__':
    main()
