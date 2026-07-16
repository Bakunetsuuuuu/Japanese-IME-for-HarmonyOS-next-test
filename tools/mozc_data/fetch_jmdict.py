#!/usr/bin/env python3
"""
Download and cache JMdict, the EDRDG's large curated Japanese
reading/kanji/gloss dictionary, used by build_jmdict_augment.py to broaden
track B's candidate-cycling vocabulary beyond mozc's own dictionary_oss
word list.

Source: https://www.edrdg.org/ (The Electronic Dictionary Research and
Development Group), distributed under CC BY-SA 4.0 -- see
../../THIRD_PARTY_NOTICES.md for the exact license terms and the
attribution/share-alike/update-mechanism obligations this data carries.

This script only downloads to a local cache -- it does not commit anything.
The cache directory (tools/mozc_data/cache_jmdict/) is gitignored; only
build_jmdict_augment.py's *output* (an in-place update to the already-built
entry/src/main/resources/rawfile/mozc_dict.json) is meant to be committed.

Usage:
    python3 tools/mozc_data/fetch_jmdict.py
"""
import gzip
import os
import urllib.request

URL = "http://ftp.edrdg.org/pub/Nihongo/JMdict.gz"
CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache_jmdict")
DEST = os.path.join(CACHE_DIR, "JMdict.xml")


def main() -> None:
    if os.path.exists(DEST):
        print(f"skip (cached): {DEST}")
        return
    print(f"fetching {URL} ...")
    with urllib.request.urlopen(URL, timeout=120) as resp:
        compressed = resp.read()
    print(f"  downloaded {len(compressed):,} bytes, decompressing...")
    data = gzip.decompress(compressed)
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = DEST + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, DEST)
    print(f"  wrote {len(data):,} bytes -> {DEST}")


if __name__ == "__main__":
    main()
