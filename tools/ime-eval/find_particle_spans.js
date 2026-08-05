#!/usr/bin/env node
// 「よく使う語＋助詞」と読みが完全に一致してしまう複合語スパンを洗い出す。
//
// 猫派(ねこは) / 人生派(じんせいは) / 金賀(かねが) / 随(したが) のように、
// 実在の語ではあっても「猫は」「人生は」「金が」「〜したが」と打つ頻度の方が
// 桁違いに多いものは、DP のスパンとして残っていると文を壊す。
// 語幹が実文コーパスで10回以上出て、複合語の方は一度も出ていないものを候補と
// して並べる。
//
// 出てきたものをそのまま全部使ってはいけない。下に/動画/底が/紙に/生地を の
// ように、複合語の側が正しい例も同じ形で出てくる。目で選んでから
// KanaKanjiConverter の NEVER_SPAN に入れ、regress.js と run_real.js で測ること。
// NEVER_SPAN はスパン候補から外すだけなので、その読みを直接打てば候補には出る。
//
// Usage: node tools/ime-eval/find_particle_spans.js
const fs=require('fs'),path=require('path'),os=require('os'),{execFileSync}=require('child_process');
const ROOT=path.resolve(__dirname,'..','..');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'ps-'));
const ts=path.join(tmp,'KKC.ts');
fs.writeFileSync(ts,'// @ts-nocheck\n'+fs.readFileSync(path.join(ROOT,'entry/src/main/ets/ime/KanaKanjiConverter.ets'),'utf-8'));
execFileSync('npx',['tsc','--target','ES2020','--module','CommonJS','--skipLibCheck',ts],{stdio:'inherit'});
const {KanaKanjiConverter}=require(path.join(tmp,'KKC.js'));
const dict=JSON.parse(fs.readFileSync(path.join(ROOT,'tools/dict_src/dict.json'),'utf-8'));
const gdict=JSON.parse(fs.readFileSync(path.join(ROOT,'tools/dict_src/global_dict.json'),'utf-8'));
KanaKanjiConverter.loadDictionary(dict);
KanaKanjiConverter.setGlobalDict(gdict);
KanaKanjiConverter.initConnectionMatrix();
const conv=new KanaKanjiConverter();

const data=JSON.parse(fs.readFileSync(path.join(ROOT,'tools/ime-eval/cache_real/real_corpus.json'),'utf-8'));
// 実文で「語＋助詞」がどれだけ出るか
const nounFreq=new Map();
for(const row of data) for(const [r,w] of (row[2]||[])) nounFreq.set(r,(nounFreq.get(r)||0)+1);

const PARTICLES=['は','が','を','に','で','と','も','の','へ'];
const rows=[];
for(const reading of Object.keys(dict)){
  if(reading.length<3||reading.length>7) continue;
  if(!/^[ぁ-ん]+$/.test(reading)) continue;
  const p=reading.slice(-1);
  if(!PARTICLES.includes(p)) continue;
  const stem=reading.slice(0,-1);
  const nf=nounFreq.get(stem)||0;
  if(nf<10) continue;                    // 語幹が実文で十分よく出るものだけ
  const wf=nounFreq.get(reading)||0;     // 複合語そのものの出現
  if(wf>0) continue;                     // 実文で使われているなら残す
  const segs=conv.segment(reading);
  if(segs.length>1) continue;            // すでに割れているなら害はない
  rows.push([nf, reading, conv.lookup(reading)[0], stem, conv.lookup(stem)[0]]);
}
rows.sort((a,b)=>b[0]-a[0]);
console.log('候補:',rows.length,'件  (語幹の実文出現数 / 読み / 複合語 / 語幹 / 語幹の変換)');
for(const r of rows.slice(0,50)) console.log(String(r[0]).padStart(5),' ',r[1].padEnd(8),r[2].padEnd(8),r[3].padEnd(7),r[4]);
console.log('\n'+rows.slice(0,50).map(r=>"'"+r[1]+"'").join(','));
