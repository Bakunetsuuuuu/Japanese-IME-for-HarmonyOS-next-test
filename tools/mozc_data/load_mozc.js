// Shared Node-side loader for the mozc engine's pre-flattened rawfiles (see
// tools/mozc_data/convert_to_binary.py and pack_strings.py for the format, and
// KeyboardController.ets's loadMozcRawfiles for the on-device equivalent).
// Used by every eval/comparison script under tools/ so the file layout only
// has to be known in one place off-device.
const fs = require('fs');
const path = require('path');

function toTypedArray(ctor, buf, byteOffset, byteLength) {
  return new ctor(buf.buffer.slice(buf.byteOffset + byteOffset, buf.byteOffset + byteOffset + byteLength));
}

// rawDir defaults to the repo's shipped rawfile directory; pass an override
// for a build-output directory that hasn't been copied into rawfile yet.
function loadMozcArgs(rawDir) {
  const RAW = rawDir || path.join(__dirname, '..', '..', 'entry/src/main/resources/rawfile');
  const u8 = (name) => new Uint8Array(fs.readFileSync(path.join(RAW, name)));
  const u32 = (name) => {
    const b = fs.readFileSync(path.join(RAW, name));
    return toTypedArray(Uint32Array, b, 0, b.byteLength);
  };
  const costsIndex = u32('mozc_costs_index.bin');
  const nSenses = costsIndex[costsIndex.length - 1];
  const costsBinBuf = fs.readFileSync(path.join(RAW, 'mozc_costs.bin'));
  const tables = {
    readBlob: u8('mozc_readings.blob'),
    readLens: u8('mozc_readings.len'),
    readBase: u32('mozc_readings.base'),
    readSorted: u32('mozc_readings.srt'),
    dictSurfBlob: u8('mozc_dict_surfaces.blob'),
    dictSurfLens: u8('mozc_dict_surfaces.len'),
    dictSurfBase: u32('mozc_dict_surfaces.base'),
    dictIndex: u32('mozc_dict_index.bin'),
    costSurfBlob: u8('mozc_costs_surfaces.blob'),
    costSurfLens: u8('mozc_costs_surfaces.len'),
    costSurfBase: u32('mozc_costs_surfaces.base'),
    costsIndex,
    costsCost: toTypedArray(Int32Array, costsBinBuf, 0, nSenses * 4),
    costsLeft: toTypedArray(Uint16Array, costsBinBuf, nSenses * 4, nSenses * 2),
    costsRight: toTypedArray(Uint16Array, costsBinBuf, nSenses * 4 + nSenses * 2, nSenses * 2),
  };
  const matrixHeader = JSON.parse(fs.readFileSync(path.join(RAW, 'mozc_matrix.json'), 'utf-8'));
  const mbin = fs.readFileSync(path.join(RAW, 'mozc_matrix.bin'));
  const mcells = toTypedArray(Uint16Array, mbin, 0, mbin.byteLength);
  return [tables, matrixHeader, mcells];
}

module.exports = { loadMozcArgs, toTypedArray };
