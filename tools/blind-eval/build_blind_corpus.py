# Build the blind conversion-quality corpus from a random Tatoeba sample.
# Source: Tatoeba (https://tatoeba.org/), CC-BY 2.0 FR. Download the sentence
# file first:  curl -o jpn_sentences.tsv.bz2 \
#   https://downloads.tatoeba.org/exports/per_language/jpn/jpn_sentences.tsv.bz2
#   && bunzip2 jpn_sentences.tsv.bz2
# Readings via Janome (independent analyzer). See README.md.
import json, re, random, sys
from janome.tokenizer import Tokenizer

KATA2HIRA = {chr(c): chr(c-0x60) for c in range(0x30A1, 0x30F7)}
def k2h(s): return ''.join(KATA2HIRA.get(c, c) for c in s)
HIRA = re.compile(r'^[ぁ-ゖー]+$')
KATA = re.compile(r'^[ァ-ヶー・]+$')
KANJI = re.compile(r'[一-龯々]')
# allow kana, kanji, 々, ー, and drop sentences with anything else (digits/latin/punct beyond 、。)
CLEAN = re.compile(r'^[぀-ヿ一-龯々ー、。]+$')
PARTICLE_KANA = {'は','へ','を'}
t = Tokenizer()

def to_pair(sent):
    sent = sent.strip().rstrip('。').replace('、','').replace('。','')
    if not sent or not CLEAN.match(sent+'。'): return None
    toks = list(t.tokenize(sent))
    if len(toks) < 3 or len(toks) > 22: return None
    reading=''; propcount=0; contentcount=0
    for tok in toks:
        surf=tok.surface; rd=tok.reading; pos=tok.part_of_speech.split(',')
        if pos[0]=='名詞' and len(pos)>1 and pos[1]=='固有名詞': propcount+=1
        if pos[0] in ('名詞','動詞','形容詞'): contentcount+=1
        if surf in PARTICLE_KANA: reading+=surf
        elif HIRA.match(surf): reading+=surf
        elif KATA.match(surf): reading+=k2h(surf)
        elif KANJI.search(surf):
            if rd=='*' or not KATA.match(rd.replace('・','')): return None
            reading+=k2h(rd)
        else: return None
    if not HIRA.match(reading): return None
    if not (8 <= len(reading) <= 26): return None
    # drop proper-noun-heavy (encyclopedic/name) sentences: keep everyday
    if contentcount>0 and propcount/contentcount > 0.34: return None
    if propcount >= 2: return None
    return (reading, sent)

random.seed(20260718)
lines=[l.rstrip('\n').split('\t') for l in open('jpn_sentences.tsv',encoding='utf-8')]
sents=[x[2] for x in lines if len(x)==3]
random.shuffle(sents)
pairs={}; 
for s in sents:
    p=to_pair(s)
    if p and p[0] not in pairs:
        pairs[p[0]]=p[1]
    if len(pairs)>=350: break
pairs=list(pairs.items())
print(f'blind pairs: {len(pairs)}', file=sys.stderr)
json.dump(pairs, open('blind_corpus.json','w',encoding='utf-8'), ensure_ascii=False, indent=0)
for r,g in pairs[:12]: print(r,'->',g, file=sys.stderr)
