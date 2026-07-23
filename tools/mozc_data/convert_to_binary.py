#!/usr/bin/env python3
"""
Convert mozc_dict.json / mozc_costs.json into a binary-heavy layout that
avoids the JSON.parse intermediate-object spike that caused the IME
extension's OOM crash when switching to the mozc engine (track B).

Root cause (see KanaKanjiConverter.ets's loadMozcEngine/buildColumnarCosts
comments): JSON.parse on mozc_costs.json builds a transient
Record<reading, [cost,left,right,surface][]> of ~906k sense arrays
(~286MB resident) before buildColumnarCosts() flattens it into columnar
typed arrays (~55MB) -- the flatten step doesn't help because the heap
already peaked holding both the raw parse tree AND the flattened output
at the same time, on top of mozc_dict.json's own ~183MB parse tree (which
was never flattened at all). Total observed heap at crash: ~456MB, against
the extension's ~464MB budget.

Fix: do ALL the flattening here, at build time, in Python (cheap, no
device memory budget). The device then only JSON.parses three plain
string[] arrays (which have no per-key object/hash overhead, unlike
Record<string, ...>) and reads the rest as typed-array binaries with zero
parse cost.

Outputs (entry/src/main/resources/rawfile/):
  - mozc_readings.json       string[]   reading list, shared index for both
                                         dict and costs (verified same order/
                                         set as of this conversion)
  - mozc_dict_surfaces.json  string[]   flattened surfaces, reading order
  - mozc_dict_index.bin      uint32 LE  N+1 cumulative start offsets into
                                         mozc_dict_surfaces (surface count
                                         for reading i = index[i+1]-index[i])
  - mozc_costs.bin           packed     N_SENSES * (int32 cost + uint16
                                         leftClass + uint16 rightClass),
                                         sense order matches costs surfaces
  - mozc_costs_surfaces.json string[]   flattened sense surfaces
  - mozc_costs_index.bin     uint32 LE  N+1 cumulative start offsets into
                                         the costs arrays (parallel to
                                         mozc_dict_index.bin's scheme)

mozc_dict.json / mozc_costs.json are left in place (regenerated from
scratch by build_mozc_engine.py) but no longer read on-device once
KeyboardController.ets/KanaKanjiConverter.ets switch to the files above.
"""
import json
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
RAWFILE_DIR = os.path.join(HERE, "..", "..", "entry", "src", "main", "resources", "rawfile")


def main():
    dict_path = os.path.join(RAWFILE_DIR, "mozc_dict.json")
    costs_path = os.path.join(RAWFILE_DIR, "mozc_costs.json")
    print(f"loading {dict_path} ...")
    with open(dict_path, encoding="utf-8") as f:
        mozc_dict = json.load(f)
    print(f"loading {costs_path} ...")
    with open(costs_path, encoding="utf-8") as f:
        mozc_costs = json.load(f)

    readings = list(mozc_dict.keys())
    assert readings == list(mozc_costs.keys()), (
        "mozc_dict.json and mozc_costs.json must have identical reading "
        "order/set -- convert_to_binary.py assumes a single shared index")
    print(f"{len(readings):,} readings")

    # -- dict: readings -> flattened surfaces + cumulative index --
    dict_surfaces = []
    dict_index = [0]
    for reading in readings:
        dict_surfaces.extend(mozc_dict[reading])
        dict_index.append(len(dict_surfaces))
    print(f"{len(dict_surfaces):,} total dict surfaces")

    # -- costs: readings -> flattened (cost, leftClass, rightClass, surface)
    #    senses, cost/classes packed binary + surfaces flattened separately --
    costs_surfaces = []
    costs_index = [0]
    cost_vals = []
    left_vals = []
    right_vals = []
    for reading in readings:
        senses = mozc_costs[reading]
        for cost, left, right, surface in senses:
            cost_vals.append(cost)
            left_vals.append(left)
            right_vals.append(right)
            costs_surfaces.append(surface)
        costs_index.append(len(costs_surfaces))
    n_senses = len(costs_surfaces)
    print(f"{n_senses:,} total senses")

    assert all(0 <= c <= 0x7FFFFFFF for c in cost_vals), "cost out of int32 range"
    assert all(0 <= v <= 0xFFFF for v in left_vals), "leftClass out of uint16 range"
    assert all(0 <= v <= 0xFFFF for v in right_vals), "rightClass out of uint16 range"

    os.makedirs(RAWFILE_DIR, exist_ok=True)

    with open(os.path.join(RAWFILE_DIR, "mozc_readings.json"), "w", encoding="utf-8") as f:
        json.dump(readings, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(RAWFILE_DIR, "mozc_dict_surfaces.json"), "w", encoding="utf-8") as f:
        json.dump(dict_surfaces, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(RAWFILE_DIR, "mozc_dict_index.bin"), "wb") as f:
        f.write(struct.pack(f"<{len(dict_index)}I", *dict_index))

    with open(os.path.join(RAWFILE_DIR, "mozc_costs_surfaces.json"), "w", encoding="utf-8") as f:
        json.dump(costs_surfaces, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(RAWFILE_DIR, "mozc_costs_index.bin"), "wb") as f:
        f.write(struct.pack(f"<{len(costs_index)}I", *costs_index))

    # mozc_costs.bin: int32 cost[n_senses] followed by uint16 left[n_senses]
    # followed by uint16 right[n_senses] -- three contiguous typed-array
    # regions in one file, sliced back out by byte offset on device.
    with open(os.path.join(RAWFILE_DIR, "mozc_costs.bin"), "wb") as f:
        f.write(struct.pack(f"<{n_senses}i", *cost_vals))
        f.write(struct.pack(f"<{n_senses}H", *left_vals))
        f.write(struct.pack(f"<{n_senses}H", *right_vals))

    for name in ("mozc_readings.json", "mozc_dict_surfaces.json", "mozc_dict_index.bin",
                 "mozc_costs_surfaces.json", "mozc_costs_index.bin", "mozc_costs.bin"):
        path = os.path.join(RAWFILE_DIR, name)
        print(f"  {name}: {os.path.getsize(path):,} bytes")


if __name__ == "__main__":
    main()
