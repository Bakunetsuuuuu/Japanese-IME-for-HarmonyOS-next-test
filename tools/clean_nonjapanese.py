#!/usr/bin/env python3
"""dict.json から「日本語で使わない漢字」の項目を落とす。

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
  - 読みの候補が全部消える場合はその項目を残す (打っても何も出ない読みを
    作らないため)

Usage:
  python3 tools/clean_nonjapanese.py --report   何が落ちるかだけ出す
  python3 tools/clean_nonjapanese.py            実際に dict.json を書き換える
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICT = os.path.join(ROOT, 'entry/src/main/resources/rawfile/dict.json')


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


def main() -> None:
    report_only = '--report' in sys.argv
    with open(DICT, encoding='utf-8') as f:
        d = json.load(f)

    out = {}
    dropped = []          # (reading, surface)
    kept_last = []        # 全消えを避けて残した項目
    for reading, v in d.items():
        surfaces = v if isinstance(v, list) else [v]
        keep = [s for s in surfaces if not is_foreign(s)]
        drop = [s for s in surfaces if is_foreign(s)]
        if drop and not keep:
            # この読みの候補が全部消える -> 打っても何も出なくなるので残す
            kept_last.append((reading, drop))
            out[reading] = v
            continue
        for s in drop:
            dropped.append((reading, s))
        out[reading] = keep if isinstance(v, list) else keep[0]

    empty_readings = sum(1 for r, v in out.items() if not v)
    print(f'読み          {len(d):,} -> {len(out):,}')
    print(f'落とす表記    {len(dropped):,}')
    print(f'全消え回避    {len(kept_last):,} 読み (候補が無くなるので残した)')
    print(f'空になった読み {empty_readings}')

    chars = set()
    for _, s in dropped:
        for ch in s:
            if is_cjk(ch) and not in_jis(ch):
                chars.add(ch)
    print(f'消える文字種  {len(chars):,}')

    print('\n-- 落とす例 --')
    for r, s in dropped[:15]:
        print(f'   {r:12s} {s}')
    if kept_last:
        print('\n-- 全消え回避で残した例 --')
        for r, ss in kept_last[:10]:
            print(f'   {r:12s} {" ".join(ss)}')

    if report_only:
        return

    before = os.path.getsize(DICT)
    with open(DICT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    after = os.path.getsize(DICT)
    print(f'\ndict.json {before:,} -> {after:,} バイト ({after - before:+,})')


if __name__ == '__main__':
    main()
