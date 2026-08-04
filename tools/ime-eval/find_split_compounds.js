#!/usr/bin/env node
// 単独では正しく変換できるのに segment() が文の中で割ってしまう複合語を洗い出す。
//
// 原因はいつも同じで、前半(ほう/もの/ひと/なに/えき…)が COMMON_READINGS に
// あって +3000 を受けるのに、複合語全体は受けないため「前半＋後半」の方が
// 安くなる。単独の lookup は全体一致で正解を返すので単体テストでは見えず、
// 文の中でだけ壊れる — 一番見つけにくい型のバグ。
//
// 実文コーパスに3回以上出てくる語だけを対象にし、出現数の多い順に並べる。
// 最後に COMMON_READINGS へ貼れる形で候補を出す。ただし 運が/会が のように
// 助詞と完全に衝突する語もあるので、貼ったら必ず regress.js と run_real.js で
// 測ること(うんが/かいが は実際にそれで落とした)。
//
// Usage: node tools/ime-eval/find_split_compounds.js
const fs=require('fs'),path=require('path'),os=require('os'),{execFileSync}=require('child_process');
const ROOT=path.resolve(__dirname,'..','..');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'ss-'));
const ts=path.join(tmp,'KKC.ts');
fs.writeFileSync(ts,'// @ts-nocheck\n'+fs.readFileSync(path.join(ROOT,'entry/src/main/ets/ime/KanaKanjiConverter.ets'),'utf-8'));
execFileSync('npx',['tsc','--target','ES2020','--module','CommonJS','--skipLibCheck',ts],{stdio:'inherit'});
const {KanaKanjiConverter}=require(path.join(tmp,'KKC.js'));
KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(path.join(ROOT,'tools/dict_src/dict.json'),'utf-8')));
KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(path.join(ROOT,'tools/dict_src/global_dict.json'),'utf-8')));
KanaKanjiConverter.initConnectionMatrix();
const conv=new KanaKanjiConverter();

// 実文コーパスのトークンから 読み->表記->出現数
const data=JSON.parse(fs.readFileSync(path.join(ROOT,'tools/ime-eval/cache_real/real_corpus.json'),'utf-8'));
const use=new Map();
for(const row of data) for(const [r,w] of (row[2]||[])){
  if(r.length<3||r.length>8) continue;
  if(!/^[ぁ-んー]+$/.test(r)) continue;
  if(!/^[一-鿿]{2,}$/.test(w)) continue;   // 漢字だけの複合語に限る
  let m=use.get(r); if(!m){m=new Map();use.set(r,m);} m.set(w,(m.get(w)||0)+1);
}
const rows=[];
for(const [r,m] of use){
  const [w,n]=[...m.entries()].sort((a,b)=>b[1]-a[1])[0];
  if(n<3) continue;
  const segs=conv.segment(r);
  if(segs.length<2) continue;               // 割れていない
  const whole=conv.lookup(r)[0];
  if(whole!==w) continue;                   // 単独でも正解が出ないなら別問題
  rows.push([n,r,w,segs.join('|')]);
}
rows.sort((a,b)=>b[0]-a[0]);
console.log('割れる複合語:', rows.length, '件');
for(const [n,r,w,s] of rows.slice(0,60)) console.log(String(n).padStart(4),r.padEnd(10),w.padEnd(8),s);
console.log('\n--- 追加候補(COMMON_READINGS 用) ---');
console.log(rows.map(x=>"'"+x[1]+"'").join(','));
