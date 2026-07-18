#!/usr/bin/env python3
"""
Download and cache the raw mozc OSS data files used by build_mozc_engine.py.

mozc (https://github.com/google/mozc) is BSD-3-Clause (Google). Its bundled
dictionary text (dictionary00.txt .. dictionary09.txt) is IPAdic-derived
(NAIST license, permissive) plus Okinawa Dictionary entries (public domain).
See ../../THIRD_PARTY_NOTICES.md for the full notices this project bundles
as a condition of redistributing data derived from these files.

This script only downloads to a local cache -- it does not commit anything.
The cache directory (tools/mozc_data/cache/) is gitignored; only
build_mozc_engine.py's *output* (the small derived JSON files under
entry/src/main/resources/rawfile/) is meant to be committed.

Usage:
    python3 tools/mozc_data/fetch_mozc.py
"""
import os
import urllib.request

BASE_URL = "https://raw.githubusercontent.com/google/mozc/master/src/data/dictionary_oss/"
CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache")

FILES = [f"dictionary{i:02d}.txt" for i in range(10)] + [
    "connection_single_column.txt",
    "id.def",
]


def fetch(name: str) -> None:
    dest = os.path.join(CACHE_DIR, name)
    if os.path.exists(dest):
        print(f"skip (cached): {name}")
        return
    url = BASE_URL + name
    print(f"fetching {url} ...")
    with urllib.request.urlopen(url, timeout=60) as resp:
        data = resp.read()
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = dest + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, dest)
    print(f"  wrote {len(data):,} bytes -> {dest}")


def main() -> None:
    for name in FILES:
        fetch(name)
    print("done.")


if __name__ == "__main__":
    main()
