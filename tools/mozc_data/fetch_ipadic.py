#!/usr/bin/env python3
"""
Download and cache the real mecab-ipadic source (not mozc's already-compiled
OSS re-export) used by build_mozc_engine.py to fill in a gap found in that
export: mozc's own dictionary text turned out to omit much of ipadic's full
verb/adjective CONJUGATION paradigm expansion, and -- more consequentially,
found by directly diffing the two matrices -- mozc's own re-trained
connection-cost matrix gives a markedly worse (higher) cost than stock
ipadic's for very basic, common grammar patterns (verified case: する's
連用形 -> た connects at cost 859 in mozc's matrix vs -7956, i.e. strongly
preferred, in real ipadic's matrix.def).

Source: https://github.com/taku910/mecab (mecab-ipadic/ subdirectory), the
original mecab author's own mirror of the NAIST/ICOT-licensed ipadic
release -- same license already documented in ../../THIRD_PARTY_NOTICES.md
(mozc's dictionary_oss is itself IPAdic-derived, same source lineage).

This script only downloads to a local cache -- it does not commit anything.
The cache directory (tools/mozc_data/cache_ipadic/) is gitignored; only
build_mozc_engine.py's *output* (the small derived JSON files under
entry/src/main/resources/rawfile/) is meant to be committed.

Usage:
    python3 tools/mozc_data/fetch_ipadic.py
"""
import os
import urllib.request

BASE_URL = "https://raw.githubusercontent.com/taku910/mecab/master/mecab-ipadic/"
CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache_ipadic")

# Every POS-category CSV file in the real ipadic source tree (verified to
# exist via HTTP HEAD before writing this list; Noun.demonstrative.csv does
# not exist under this name and is intentionally omitted).
CSV_FILES = [
    "Adj.csv", "Adnominal.csv", "Adverb.csv", "Auxil.csv", "Conjunction.csv",
    "Filler.csv", "Interjection.csv", "Noun.adjv.csv", "Noun.csv",
    "Noun.nai.csv", "Noun.name.csv", "Noun.number.csv", "Noun.org.csv",
    "Noun.others.csv", "Noun.place.csv", "Noun.proper.csv",
    "Noun.verbal.csv", "Others.csv", "Postp-col.csv", "Postp.csv",
    "Prefix.csv", "Suffix.csv", "Symbol.csv", "Verb.csv",
]
OTHER_FILES = ["matrix.def", "left-id.def", "COPYING"]
FILES = CSV_FILES + OTHER_FILES


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
