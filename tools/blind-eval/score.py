import json, sys

def lev(a,b):
    m,n=len(a),len(b)
    if m==0: return n
    if n==0: return m
    prev=list(range(n+1))
    for i in range(1,m+1):
        cur=[i]+[0]*n
        for j in range(1,n+1):
            cur[j]=min(prev[j]+1,cur[j-1]+1,prev[j-1]+(a[i-1]!=b[j-1]))
        prev=cur
    return prev[n]
def charsim(got,gold):
    if not gold: return 1.0
    return 1 - lev(got,gold)/max(len(got),len(gold))

pairs=json.load(open('blind_corpus.json',encoding='utf-8'))
ours=json.load(open('ours_out.json',encoding='utf-8'))
gcache=json.load(open('google_cache.json',encoding='utf-8'))

engines={'TrackA (custom)':[], 'TrackB (mozc full)':[], 'Google Input Tools':[]}
strict={k:0 for k in engines}
gerr=0
rows=[]
for r,gold in pairs:
    a=ours[r]['a']; b=ours[r]['b']; g=gcache.get(r,'__FAIL__')
    if g in ('__ERR__','__FAIL__'): gerr+=1; g=None
    for name,got in [('TrackA (custom)',a),('TrackB (mozc full)',b),('Google Input Tools',g)]:
        if got is None: continue
        engines[name].append(charsim(got,gold))
        if got==gold: strict[name]+=1
    rows.append((r,gold,a,b,g))

N=len(pairs)
print(f'Blind test: {N} everyday sentences (Tatoeba, Janome-derived readings)')
print(f'Google API errors/skips: {gerr}\n')
print(f'{"engine":22} {"strict":>12} {"char-acc":>10}')
for name in engines:
    cnt=len(engines[name]); s=strict[name]
    ca=sum(engines[name])/cnt if cnt else 0
    denom = cnt if name=='Google Input Tools' else N
    print(f'{name:22} {s:4}/{denom:<4} ({100*s/denom:4.1f}%)  {100*ca:6.2f}%')
# sample disagreements
print('\n--- 15 sample rows ---')
for r,gold,a,b,g in rows[:15]:
    mark=lambda x: '✓' if x==gold else '✗'
    print(f'{r}\n  gold: {gold}\n  A:{mark(a)} {a}\n  B:{mark(b)} {b}\n  G:{mark(g)} {g}')
