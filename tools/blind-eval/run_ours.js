const fs=require('fs'),path=require('path'),os=require('os'),{execFileSync}=require('child_process');
const ROOT='/home/user/Japanese-IME-for-HarmonyOS-next';const RAW=path.join(ROOT,'entry/src/main/resources/rawfile');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'blind-'));
fs.writeFileSync(path.join(tmp,'KKC.ts'),'// @ts-nocheck\n'+fs.readFileSync(path.join(ROOT,'entry/src/main/ets/ime/KanaKanjiConverter.ets'),'utf-8'));
execFileSync('npx',['tsc','--target','ES2020','--module','CommonJS','--skipLibCheck',path.join(tmp,'KKC.ts')],{stdio:'inherit'});
const {KanaKanjiConverter}=require(path.join(tmp,'KKC.js'));
KanaKanjiConverter.loadDictionary(JSON.parse(fs.readFileSync(path.join(RAW,'dict.json'),'utf-8')));
KanaKanjiConverter.setGlobalDict(JSON.parse(fs.readFileSync(path.join(RAW,'global_dict.json'),'utf-8')));
KanaKanjiConverter.initConnectionMatrix();
KanaKanjiConverter.loadMozcEngine(
  JSON.parse(fs.readFileSync(path.join(RAW,'mozc_dict.json'),'utf-8')),
  JSON.parse(fs.readFileSync(path.join(RAW,'mozc_costs.json'),'utf-8')),
  JSON.parse(fs.readFileSync(path.join(RAW,'mozc_matrix.json'),'utf-8')));
const conv=new KanaKanjiConverter();
function convert(reading){
  if(!reading)return'';
  const fullKata=KanaKanjiConverter.toKatakana(reading);
  const segs=conv.segment(reading);
  if(segs.length<=1)return conv.lookup(reading)[0];
  const full=conv.lookup(reading);
  if((full[0]!==fullKata&&full[0]!==reading)||KanaKanjiConverter.isDictionaryWord(reading))return full[0];
  const prefixParts=segs.slice(0,-1).map((s,i)=>conv.autoConvert(s,segs[i+1],segs[i-1]));
  if(prefixParts.some((p)=>KanaKanjiConverter.isSymbolOnly(p)))return reading;
  return prefixParts.join('')+conv.lookup(segs[segs.length-1])[0];
}
const pairs=JSON.parse(fs.readFileSync(process.argv[2],'utf-8'));
const out={};
for(const [r,g] of pairs){
  KanaKanjiConverter.setEngine('custom'); const a=convert(r);
  KanaKanjiConverter.setEngine('mozc');   const b=convert(r);
  out[r]={a,b};
}
fs.writeFileSync(process.argv[3],JSON.stringify(out));
console.error('ours done:',Object.keys(out).length);
