"""
文節の区切りに使う品詞の分類 (desktop/core/pos_classes.h) を、Mozc の品詞 ID の表 (id.def) から作る。

  python desktop/tools/gen_pos_classes.py

辞書 (shuntorge) の品詞 ID は Mozc と同じ。ID ごとに 1 字で:
  '1' = 付属語 (前の語につく: 助詞・助動詞・非自立の動詞と形容詞・接尾・句読点・閉じ括弧)
  '2' = 接頭 (次の語がつく: 接頭詞・開き括弧)
  '3' = サ変接続の名詞 (電話・勉強。後ろの「する」がつく)
  '4' = サ変・スルの動詞 (する・し・さ・せ。サ変接続の名詞の後ろならその文節につく)
  '0' = それ以外 (自立語。ここで文節が始まる)
id.def は tools/mozc_data/fetch_mozc.py で取ってくる (tools/mozc_data/cache/。リポジトリには入れない)。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'tools', 'mozc_data', 'cache', 'id.def')
OUT = os.path.join(ROOT, 'desktop', 'core', 'pos_classes.h')

ATTACH = ('助詞,', '助動詞,', '動詞,非自立', '動詞,接尾', '形容詞,非自立', '形容詞,接尾', '名詞,接尾',
          '記号,句点', '記号,読点', '記号,括弧閉')
PREFIX = ('接頭詞,', '記号,括弧開')
SAHEN_NOUN = ('名詞,サ変接続',)
SURU = ('動詞,自立,*,*,サ変・スル',)


def main():
    cls = {}
    for line in open(SRC, encoding='utf-8'):
        i, pos = line.rstrip('\n').split(' ', 1)
        c = ('1' if pos.startswith(ATTACH) else '2' if pos.startswith(PREFIX) else '3' if pos.startswith(SAHEN_NOUN)
             else '4' if pos.startswith(SURU) else '0')
        cls[int(i)] = c
    n = max(cls) + 1
    s = ''.join(cls.get(i, '0') for i in range(n))
    lines = [s[i:i + 100] for i in range(0, n, 100)]
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('// 生成物: desktop/tools/gen_pos_classes.py (Mozc の id.def から)。手で直さない\n')
        f.write('// 品詞 ID ごとの文節の分類: 1 = 付属語 (前につく)、2 = 接頭 (次がつく)、3 = サ変接続の名詞、\n')
        f.write('// 4 = サ変・スルの動詞 (3 の後ろならつく)、0 = 自立語\n')
        f.write('#pragma once\n\nnamespace shunti {\n')
        f.write('constexpr int POS_CLASS_COUNT = %d;\n' % n)
        f.write('constexpr const char POS_CLASSES[] =\n')
        for l in lines:
            f.write('    "%s"\n' % l)
        f.write('    ;\n}  // namespace shunti\n')
    print(OUT, n, 'attach', s.count('1'), 'prefix', s.count('2'), 'sahen', s.count('3'), 'suru', s.count('4'))


if __name__ == '__main__':
    main()
