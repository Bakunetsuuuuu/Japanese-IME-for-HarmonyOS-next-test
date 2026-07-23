import json, urllib.request, urllib.parse, time, sys, os
pairs = json.load(open('blind_corpus.json',encoding='utf-8'))
cache = {}
if os.path.exists('google_cache.json'):
    cache = json.load(open('google_cache.json',encoding='utf-8'))
def google(text):
    if text in cache: return cache[text]
    q = urllib.parse.urlencode({'text':text,'itc':'ja-t-i0-und','num':'3','cp':'0','cs':'1','ie':'utf-8','oe':'utf-8','app':'test'})
    url='https://inputtools.google.com/request?'+q
    for attempt in range(4):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
            d=json.load(urllib.request.urlopen(req,timeout=20))
            if d[0]=='SUCCESS':
                res=d[1][0][1][0]; cache[text]=res; return res
            else:
                cache[text]='__ERR__'; return '__ERR__'
        except Exception as e:
            time.sleep(1.5*(attempt+1))
    cache[text]='__FAIL__'; return '__FAIL__'
n=len(pairs); done=0
for r,g in pairs:
    google(r); done+=1
    if done%50==0:
        json.dump(cache,open('google_cache.json','w',encoding='utf-8'),ensure_ascii=False)
        print(f'{done}/{n}',file=sys.stderr)
    time.sleep(0.15)
json.dump(cache,open('google_cache.json','w',encoding='utf-8'),ensure_ascii=False)
print('google done', file=sys.stderr)
