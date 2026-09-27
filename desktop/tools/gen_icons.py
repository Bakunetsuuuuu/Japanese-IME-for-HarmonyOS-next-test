"""
Windows 版のアイコンを Zori-chan の絵 (desktop/windows/art/zori-chan.png、黒い形に白抜きの鼻緒と目) から作る。

  python desktop/tools/gen_icons.py      (Pillow と numpy が要る)

出来上がり (desktop/windows/):
  mode_on_white.ico / mode_on_black.ico   そのままの Zori-chan (箱なし・余白なし)。タスクバーがダークなら白、ライトなら黒。
                                          IME の登録アイコン (タスクバーの「あ」の隣に出る) にも使う
  mode_off_white.ico / mode_off_black.ico オフ (寝ている Zori-chan。art/zori-chan-off.png。無ければオンの絵の目を閉じて作る)
  shunti.ico                              設定画面の exe のアイコン (スタートメニュー用。白い角丸の上に黒い Zori-chan)
どれも 16〜256px を 1 つの .ico に入れる。
"""
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
WIN = os.path.join(HERE, '..', 'windows')
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def load_filled(name):
    im = Image.open(os.path.join(WIN, 'art', name)).convert('RGBA')
    a = np.asarray(im).astype(np.int32)
    lum = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
    return (a[..., 3] > 128) & (lum < 128)


def load_masks():
    """オンの絵 (zori-chan.png) と、あればオフの絵 (zori-chan-off.png)。同じ枠で切り出す (切り替えたときに形がずれないように)"""
    on = load_filled('zori-chan.png')
    off = load_filled('zori-chan-off.png') if os.path.exists(os.path.join(WIN, 'art', 'zori-chan-off.png')) else None
    both = on | off if off is not None else on
    ys, xs = np.nonzero(both)
    box = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
    return on[box], (off[box] if off is not None else None)


def components(mask):
    """白 (False) の部分の連結成分のうち、外側 (縁につながる) 以外 = 目"""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    comps = []
    for y in range(h):
        for x in range(w):
            if mask[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            pts, edge = [], False
            while q:
                cy, cx = q.popleft()
                pts.append((cy, cx))
                if cy in (0, h - 1) or cx in (0, w - 1):
                    edge = True
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and not mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            if not edge:
                comps.append(pts)
    return comps


def sleeping(mask):
    """目 (T の字) の上の横線だけを残して下を塗りつぶし、両目とも閉じた寝ている目にする"""
    out = mask.copy()
    eyes = [c for c in components(mask) if len(c) > 200]
    for pts in eyes:
        ys = [y for y, _ in pts]
        top, bottom = min(ys), max(ys)
        keep = top + (bottom - top) * 0.38          # 目の上から 4 割 = 横線
        for y, x in pts:
            if y > keep:
                out[y, x] = True
    return out, len(eyes)


def square(mask, stretch=1.1):
    """正方形のアイコンに置く。横長の絵なので縦に stretch 倍伸ばして (デフォルメ)、横いっぱいに置く。
    上下は形の外枠でなく重心で真ん中に置く (下が平らで上が丸い形は、外枠で真ん中に置くと上に寄って見える)"""
    h, w = mask.shape
    img = Image.fromarray((mask * 255).astype(np.uint8), 'L').resize((w, int(h * stretch)), Image.LANCZOS)
    a = np.asarray(img).astype(np.float64)
    h2 = a.shape[0]
    side = max(w, h2)
    cy = (a.sum(1) * np.arange(h2)).sum() / a.sum()        # 重心の高さ
    y0 = int(round(side / 2 - cy))
    y0 = max(0, min(side - h2, y0))
    sq = Image.new('L', (side, side), 0)
    sq.paste(img, ((side - w) // 2, y0))
    return sq


def mono_icon(alpha, rgb, path):
    imgs = []
    for s in SIZES:
        a = alpha.resize((s, s), Image.LANCZOS)
        im = Image.new('RGBA', (s, s), rgb + (0,))
        im.putalpha(a)
        imgs.append(im)
    imgs[-1].save(path, sizes=[(s, s) for s in SIZES], append_images=imgs[:-1])


def app_icon(alpha, path):
    imgs = []
    for s in SIZES:
        tile = Image.new('RGBA', (s, s), (0, 0, 0, 0))
        r = max(2, s // 5)
        ImageDraw.Draw(tile).rounded_rectangle((0, 0, s - 1, s - 1), radius=r, fill=(250, 250, 250, 255),
                                               outline=(205, 205, 205, 255) if s >= 32 else None)
        inner = int(s * 0.8)
        a = alpha.resize((inner, inner), Image.LANCZOS)
        shape = Image.new('RGBA', (inner, inner), (28, 28, 30, 255))
        shape.putalpha(a)
        tile.alpha_composite(shape, ((s - inner) // 2, (s - inner) // 2))
        imgs.append(tile)
    imgs[-1].save(path, sizes=[(s, s) for s in SIZES], append_images=imgs[:-1])


def main():
    on, off = load_masks()
    if off is None:   # オフの絵が無ければ、オンの絵の目を閉じて作る
        off, n_eyes = sleeping(on)
        assert n_eyes == 2, f'目が {n_eyes} 個見つかった (2 個のはず)'
    a_on, a_off = square(on), square(off)
    for name, alpha in (('on', a_on), ('off', a_off)):
        mono_icon(alpha, (255, 255, 255), os.path.join(WIN, f'mode_{name}_white.ico'))
        mono_icon(alpha, (28, 28, 30), os.path.join(WIN, f'mode_{name}_black.ico'))
    app_icon(a_on, os.path.join(WIN, 'shunti.ico'))
    # 確かめ用の見本 (タスクバーの実寸 16〜48px をダークとライトに置いたもの)
    prev = Image.new('RGB', (2 * (16 + 20 + 24 + 32 + 48 + 5 * 12) + 24, 2 * 72), (255, 255, 255))
    d = ImageDraw.Draw(prev)
    for row, (bg, rgb) in enumerate([((32, 32, 32), (255, 255, 255)), ((243, 243, 243), (28, 28, 30))]):
        d.rectangle((0, row * 72, prev.width, row * 72 + 71), fill=bg)
        x = 12
        for alpha in (a_on, a_off):
            for s in (16, 20, 24, 32, 48):
                im = Image.new('RGB', (s, s), bg)
                im.paste(Image.new('RGB', (s, s), rgb), (0, 0), alpha.resize((s, s), Image.LANCZOS))
                prev.paste(im, (x, row * 72 + (72 - s) // 2))
                x += s + 12
            x += 12
    prev.resize((prev.width * 3, prev.height * 3), Image.NEAREST).save(os.path.join(HERE, '..', 'build', 'icon_preview.png'))
    print('ok')


if __name__ == '__main__':
    main()
