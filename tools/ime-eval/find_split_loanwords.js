#!/usr/bin/env node
// ひらがなで打った外来語(カタカナ語)のうち、segment() が割ってしまうものを探す。
//
// 外来語は最後の1モーラが助詞に見えることが多く、そこで割られる:
//   ノート → のー＋と   トマト → とま＋と   パンダ → ぱん＋だ   メモ → め＋も
// 単独の lookup は全体一致で正しく返すので、文の中でだけ壊れる。
//
// 「辞書がカタカナ表記を持つ読みは一語として扱う」という一般規則も試したが、
// いくら→イクラ / あすも→アスモ / てると→テルト のように、たまたまカタカナ語と
// 読みが一致するだけの語まで巻き込んで悪化した(REGRESSED 9)。結局この一覧を
// 目で選んで COMMON_READINGS に入れる方が確実。
// 会うと/減ると/パンだ/待った と衝突するもの(あうと/べると/ぱんだ/まっと)は
// 入れないこと — 実測で -12文 になる。
//
// Usage: node tools/ime-eval/find_split_loanwords.js
const fs=require('fs'),path=require('path'),os=require('os'),{execFileSync}=require('child_process');
const ROOT=path.resolve(__dirname,'..','..');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'ls-'));
const ts=path.join(tmp,'KKC.ts');
fs.writeFileSync(ts,'// @ts-nocheck\n'+fs.readFileSync(path.join(ROOT,'entry/src/main/ets/ime/KanaKanjiConverter.ets'),'utf-8'));
execFileSync('npx',['tsc','--target','ES2020','--module','CommonJS','--skipLibCheck',ts],{stdio:'inherit'});
const {KanaKanjiConverter}=require(path.join(tmp,'KKC.js'));
const dict=JSON.parse(fs.readFileSync(path.join(ROOT,'tools/dict_src/dict.json'),'utf-8'));
KanaKanjiConverter.loadDictionary(dict);
KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(path.join(ROOT,'tools/dict_src/global_dict.json'),'utf-8')));
KanaKanjiConverter.initConnectionMatrix();
const conv=new KanaKanjiConverter();
const data=JSON.parse(fs.readFileSync(path.join(ROOT,'tools/ime-eval/cache_real/real_corpus.json'),'utf-8'));
const freq=new Map();
for(const row of data) for(const [r,w] of (row[2]||[])){
  if(!/^[ァ-ヶー]+$/.test(w)) continue;         // 正解がカタカナ語
  if(!/^[ぁ-んー]+$/.test(r)) continue;
  const k=r+'\t'+w; freq.set(k,(freq.get(k)||0)+1);
}
const rows=[];
for(const [k,n] of freq){
  const [r,w]=k.split('\t');
  if(n<2) continue;
  if(conv.segment(r).length<2) continue;
  if(conv.lookup(r)[0]!==w) continue;
  rows.push([n,r,w,conv.segment(r).join('|')]);
}
rows.sort((a,b)=>b[0]-a[0]);
console.log('割れるカタカナ語:',rows.length,'件');
for(const x of rows.slice(0,40)) console.log(String(x[0]).padStart(4),x[1].padEnd(12),x[2].padEnd(10),x[3]);
console.log('\n'+rows.map(x=>"'"+x[1]+"'").join(','));
