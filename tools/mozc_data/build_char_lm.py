#!/usr/bin/env python3
"""Build a character n-gram language model over Japanese *output* text.

Why
---
With the segmentation track B already produces, the correct surface is
reachable by choosing among each segment's own candidates for 318 of the 350
blind-corpus sentences (90.9%), and among just each segment's top 3 for 286
(81.7%) -- against 200 (57.1%) actually produced. The gap is not
segmentation and not vocabulary: it is *which* homophone gets picked, and
mozc's POS bigram cannot see the difference between 髪を乾かす and 神を乾かす
because both are 名詞 + を + 動詞.

A character n-gram over finished Japanese text can, because 髪を乾 and 神を乾
are different strings. This builds that model.

Corpus choice
-------------
Japanese Wikipedia (CC BY-SA 4.0 -- see ../../THIRD_PARTY_NOTICES.md).
Specifically NOT Tatoeba, which is where `tools/blind-eval/blind_corpus.json`
comes from: training on the same source the held-out benchmark is drawn from
would make its numbers meaningless, even with the exact sentences excluded.
Wikipedia's register is a poor match for everyday typing, which costs the
model something on conversational text -- that is the price of keeping the
benchmark honest, and it is the right trade.

Model
-----
Orders 1..N (default 4) counted over extracted article text, pruned to the
most frequent `--max-ngrams` entries per order above a minimum count. Scoring
on device is stupid backoff: use the longest order present, otherwise fall
back one order and multiply by a fixed discount. Stupid backoff needs raw
counts rather than normalised probabilities, and is within noise of
Kneser-Ney at this scale while being far simpler to ship.

Output is `char_lm.tsv` (ngram \t count), which `pack_char_lm.py` turns into
the shipped binary. Kept as a separate text step so the counts can be
inspected and diffed.

Usage:
    python tools/mozc_data/build_char_lm.py <jawiki-*.bz2> [--budget-mb 300]
"""

import argparse
import bz2
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))

# Article text only: kanji, kana, the prolonged-sound mark, and the two
# punctuation marks that carry sentence structure. Everything else (latin,
# digits, brackets, wiki markup residue) is a boundary -- an n-gram must not
# straddle it, or the model learns junk contexts that never occur in IME
# output.
KEEP = re.compile(r'[぀-ヿ一-鿿々〆ヵヶ、。]+')

# MediaWiki markup that must go before the KEEP filter, or its inner text
# would be treated as running prose.
STRIP = [
    (re.compile(r'(?s)<ref.*?</ref>'), ''),
    (re.compile(r'(?s)<!--.*?-->'), ''),
    (re.compile(r'(?s)\{\{.*?\}\}'), ' '),      # templates
    (re.compile(r'(?s)\{\|.*?\|\}'), ' '),      # tables
    (re.compile(r'(?s)<[^>]+>'), ' '),          # any remaining tag
    (re.compile(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]'), r'\1'),   # [[link|text]]
    (re.compile(r'\[[^\] ]+ ([^\]]*)\]'), r'\1'),             # [url text]
    (re.compile(r"'{2,}"), ''),                 # bold/italic
    (re.compile(r'^[*#:;=]+', re.M), ' '),      # list/heading markers
]


def extract(path, budget_bytes):
    """Yield runs of plain Japanese text from a MediaWiki XML bz2 dump."""
    produced = 0
    buf = []
    in_text = False
    with bz2.open(path, 'rt', encoding='utf-8', errors='replace') as f:
        for line in f:
            if not in_text:
                i = line.find('<text')
                if i < 0:
                    continue
                j = line.find('>', i)
                if j < 0:
                    continue
                line = line[j + 1:]
                in_text = True
            end = line.find('</text>')
            if end >= 0:
                buf.append(line[:end])
                in_text = False
                chunk = ''.join(buf)
                buf = []
                for pat, rep in STRIP:
                    chunk = pat.sub(rep, chunk)
                for run in KEEP.findall(chunk):
                    produced += len(run)
                    yield run
                if produced >= budget_bytes:
                    return
            else:
                buf.append(line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dump')
    ap.add_argument('--order', type=int, default=4)
    ap.add_argument('--budget-mb', type=int, default=300,
                    help='stop after this many MB of extracted Japanese text')
    ap.add_argument('--max-ngrams', type=int, default=1500000,
                    help='keep at most this many n-grams per order')
    ap.add_argument('--min-count', type=int, default=3)
    ap.add_argument('--out', default=os.path.join(HERE, 'char_lm.tsv'))
    args = ap.parse_args()

    counters = [Counter() for _ in range(args.order + 1)]
    total_chars = 0
    runs = 0
    # Periodic pruning keeps peak memory bounded: singletons dominate and
    # cannot survive --min-count anyway, but they would otherwise all be held
    # at once.
    PRUNE_EVERY = 20 * 1024 * 1024
    next_prune = PRUNE_EVERY

    for run in extract(args.dump, args.budget_mb * 1024 * 1024):
        runs += 1
        total_chars += len(run)
        for order in range(1, args.order + 1):
            c = counters[order]
            for i in range(len(run) - order + 1):
                c[run[i:i + order]] += 1
        if total_chars >= next_prune:
            for order in range(2, args.order + 1):
                c = counters[order]
                if len(c) > args.max_ngrams * 4:
                    keep = dict(c.most_common(args.max_ngrams * 2))
                    counters[order] = Counter(keep)
            next_prune = total_chars + PRUNE_EVERY
            print('  %.1fMB, runs=%d, sizes=%s'
                  % (total_chars / 1048576, runs,
                     [len(x) for x in counters[1:]]), file=sys.stderr)

    with open(args.out, 'w', encoding='utf-8') as f:
        f.write('#chars\t%d\n' % total_chars)
        written = 0
        for order in range(1, args.order + 1):
            items = counters[order].most_common(args.max_ngrams)
            for ng, cnt in items:
                if cnt < args.min_count and order > 1:
                    break
                f.write('%s\t%d\n' % (ng, cnt))
                written += 1
    print('%.1fMB of text, %d n-grams written to %s'
          % (total_chars / 1048576, written, args.out))


if __name__ == '__main__':
    sys.exit(main())
