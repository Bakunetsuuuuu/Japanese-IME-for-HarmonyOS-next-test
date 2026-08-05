#!/usr/bin/env node
// Prove that pack_dicts.py's output is entry-for-entry identical to the JSON
// it replaces. Conversion reads these dictionaries only through get() and
// has(), so if both agree with the JSON for every reading, no conversion
// result can differ -- which is a stronger statement than any corpus score.
//
//   bun tools/verify_dicts.js
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const RAW = path.join(ROOT, 'entry/src/main/resources/rawfile');
const SRCDIR = path.join(__dirname, 'dict_src');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'verifydicts-'));
const ts = path.join(tmp, 'KKC.ts');
fs.writeFileSync(ts, '// @ts-nocheck\n' +
  fs.readFileSync(path.join(ROOT, 'entry/src/main/ets/ime/KanaKanjiConverter.ets'), 'utf-8'));
const { PackedDict } = require(ts);

const u8 = (n) => new Uint8Array(fs.readFileSync(path.join(RAW, n)));
const u32 = (n) => {
  const b = fs.readFileSync(path.join(RAW, n));
  return new Uint32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));
};

let bad = 0;
for (const name of ['dict', 'global_dict']) {
  const json = JSON.parse(fs.readFileSync(path.join(SRCDIR, name + '.json'), 'utf-8'));
  const d = new PackedDict();
  d.setPacked(u8(name + '.keys.blob'), u8(name + '.keys.len'), u32(name + '.keys.base'),
    u8(name + '.vals.blob'), u8(name + '.vals.len'), u32(name + '.vals.base'),
    u32(name + '.idx.bin'));

  let n = 0;
  for (const k of Object.keys(json)) {
    n++;
    const want = Array.isArray(json[k]) ? json[k] : [json[k]];
    const got = d.get(k);
    if (!got || got.length !== want.length || got.some((x, i) => x !== want[i])) {
      if (bad < 5) console.error(`  ${name}[${JSON.stringify(k)}] got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
      bad++;
    }
    if (!d.has(k)) { if (bad < 5) console.error(`  ${name}.has(${JSON.stringify(k)}) false`); bad++; }
  }
  for (const miss of ['', 'ｘｘｘ存在しない読み', 'zzzzq', '𩸽𩸽𩸽']) {
    if (d.get(miss) !== undefined || d.has(miss)) {
      console.error(`  ${name} should not contain ${JSON.stringify(miss)}`);
      bad++;
    }
  }
  console.log(`${bad === 0 ? 'OK  ' : 'NG  '} ${name.padEnd(14)} ${n} readings`);
}
if (bad) { console.error(`\n${bad} mismatches -- NOT equivalent.`); process.exit(1); }
console.log('\nすべて一致。パック辞書は元の JSON と完全に等価。');
