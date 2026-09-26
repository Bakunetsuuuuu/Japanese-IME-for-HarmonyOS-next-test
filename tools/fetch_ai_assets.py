"""
AI 変換 (shuntelligence) の辞書 kkc_lex.bin とモデル kkc_model.bin を GitHub Releases から取ってきて、
rawfile に置く。どちらも大きいので Git には入れていない (tools/ai_assets.json に置き場所と SHA-256)。

  python tools/fetch_ai_assets.py

既に同じもの (SHA-256 が一致) があれば何もしない。無くてもアプリはビルドでき、AI 変換を選んだときに
読み込みに失敗して独自辞書の変換に戻るだけ。
"""
import hashlib
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def main():
    m = json.load(open(os.path.join(ROOT, 'tools', 'ai_assets.json'), encoding='utf-8'))
    dest = os.path.join(ROOT, m['dest'])
    ok = True
    for name, info in m['files'].items():
        path = os.path.join(dest, name)
        if os.path.exists(path) and sha256(path) == info['sha256']:
            print(f'{name}: 最新')
            continue
        print(f'{name}: 取得中 ({info["size"] / 1e6:.0f}MB) ...', flush=True)
        tmp = path + '.part'
        urllib.request.urlretrieve(m['url'] + name, tmp)
        if sha256(tmp) != info['sha256']:
            os.remove(tmp)
            print(f'{name}: SHA-256 が合わない (取得失敗)', file=sys.stderr)
            ok = False
            continue
        os.replace(tmp, path)
        print(f'{name}: OK')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
