#!/usr/bin/env python3
"""
Download and cache SudachiDict's raw lexicon CSVs (the "small" and "core"
tiers -- see module docstring of build_sudachi_augment.py for why "notcore"
is deliberately skipped), used to broaden track B's candidate-cycling
vocabulary the same way build_jmdict_augment.py does with JMdict.

Source: https://github.com/WorksApplications/SudachiDict (Apache License
2.0, copyright Works Applications Co., Ltd.). The raw lexicon CSVs
themselves are hosted on the project's own S3 bucket (the project's README
notes they "were hosted on git lfs, but are hosted on S3 now"), discovered
via that bucket's public listing (http://sudachi.s3-ap-northeast-1
.amazonaws.com/?list-type=2):
  http://sudachi.s3-ap-northeast-1.amazonaws.com/sudachidict-raw/<date>/{small,core}_lex.zip

This script only downloads to a local cache -- it does not commit anything.
The cache directory (tools/mozc_data/cache_sudachi/) is gitignored; only
build_sudachi_augment.py's *output* (an in-place update to the already-built
entry/src/main/resources/rawfile/mozc_dict.json) is meant to be committed.

Usage:
    python3 tools/mozc_data/fetch_sudachi.py
"""
import io
import os
import urllib.request
import zipfile

BASE_URL = "http://sudachi.s3-ap-northeast-1.amazonaws.com/sudachidict-raw/20260428/"
CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache_sudachi")

# "small" = UniDic core vocabulary + conjugation paradigms, "core" = small's
# own additional general-vocabulary entries (Sudachi's "core" dictionary
# tier is built from BOTH files together, per the project's own docs, not
# from core_lex.csv alone). "notcore" (the third tier, "full") is
# deliberately not fetched here -- the project's own README describes it as
# "miscellaneous proper nouns", a much larger and noisier long tail with a
# higher risk of low-quality candidate surfaces for comparatively little
# value, the same reasoning JMdict's augmentation already applies by using
# the curated dictionary as-is rather than chasing every possible source.
LEX_FILES = ["small_lex.zip", "core_lex.zip"]


def fetch(name: str) -> None:
    csv_name = name.replace(".zip", ".csv")
    dest = os.path.join(CACHE_DIR, csv_name)
    if os.path.exists(dest):
        print(f"skip (cached): {csv_name}")
        return
    url = BASE_URL + name
    print(f"fetching {url} ...")
    with urllib.request.urlopen(url, timeout=120) as resp:
        data = resp.read()
    print(f"  downloaded {len(data):,} bytes, extracting...")
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        csv_bytes = zf.read(csv_name)
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = dest + ".tmp"
    with open(tmp, "wb") as f:
        f.write(csv_bytes)
    os.replace(tmp, dest)
    print(f"  wrote {len(csv_bytes):,} bytes -> {dest}")


def main() -> None:
    for name in LEX_FILES:
        fetch(name)
    print("done.")


if __name__ == "__main__":
    main()
