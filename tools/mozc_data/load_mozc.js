// Shared Node-side loader for the mozc engine's pre-flattened rawfiles (see
// tools/mozc_data/convert_to_binary.py for the format, and
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
  const readings = JSON.parse(fs.readFileSync(path.join(RAW, 'mozc_readings.json'), 'utf-8'));
  const dictSurfaces = JSON.parse(fs.readFileSync(path.join(RAW, 'mozc_dict_surfaces.json'), 'utf-8'));
  const dictIndexBuf = fs.readFileSync(path.join(RAW, 'mozc_dict_index.bin'));
  const dictIndex = toTypedArray(Uint32Array, dictIndexBuf, 0, dictIndexBuf.byteLength);
  const costsSurfaces = JSON.parse(fs.readFileSync(path.join(RAW, 'mozc_costs_surfaces.json'), 'utf-8'));
  const costsIndexBuf = fs.readFileSync(path.join(RAW, 'mozc_costs_index.bin'));
  const costsIndex = toTypedArray(Uint32Array, costsIndexBuf, 0, costsIndexBuf.byteLength);
  const nSenses = costsIndex[costsIndex.length - 1];
  const costsBinBuf = fs.readFileSync(path.join(RAW, 'mozc_costs.bin'));
  const costsCost = toTypedArray(Int32Array, costsBinBuf, 0, nSenses * 4);
  const costsLeft = toTypedArray(Uint16Array, costsBinBuf, nSenses * 4, nSenses * 2);
  const costsRight = toTypedArray(Uint16Array, costsBinBuf, nSenses * 4 + nSenses * 2, nSenses * 2);
  const matrixHeader = JSON.parse(fs.readFileSync(path.join(RAW, 'mozc_matrix.json'), 'utf-8'));
  const mbin = fs.readFileSync(path.join(RAW, 'mozc_matrix.bin'));
  const mcells = toTypedArray(Uint16Array, mbin, 0, mbin.byteLength);
  return [readings, dictSurfaces, dictIndex, costsSurfaces, costsIndex,
    costsCost, costsLeft, costsRight, matrixHeader, mcells];
}

module.exports = { loadMozcArgs, toTypedArray };
