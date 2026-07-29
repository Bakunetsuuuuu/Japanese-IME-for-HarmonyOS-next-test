#!/usr/bin/env node
// Download the Tatoeba Japanese data used to build a large real-sentence test
// set (see build_real_corpus.js). Mirrors tools/mozc_data/fetch_*.py: this only
// downloads into a gitignored cache -- nothing here is committed or shipped.
//
// Source: https://tatoeba.org/ , exports released under CC BY 2.0 FR.
// The data is used ONLY as an offline accuracy fixture for this repo's
// converter; no Tatoeba text is bundled into the app.
//
// Two files are needed:
//   jpn_indices.csv    per-sentence morphological annotation (headword,
//                      reading, written form) -- this is what makes it possible
//                      to recover the KANA a user would actually type.
//   jpn_sentences.tsv  the official sentence text, used to verify that the
//                      reconstruction covers the whole sentence and not just
//                      the annotated part (5k+ sentences fail that check).
//
// Usage: node tools/ime-eval/fetch_real_corpus.js
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const CACHE = path.join(__dirname, 'cache_real');
const FILES = [
  { url: 'https://downloads.tatoeba.org/exports/jpn_indices.tar.bz2', out: 'jpn_indices.tar.bz2', extract: 'tar' },
  { url: 'https://downloads.tatoeba.org/exports/per_language/jpn/jpn_sentences.tsv.bz2', out: 'jpn_sentences.tsv.bz2', extract: 'bz2' },
];

function main() {
  fs.mkdirSync(CACHE, { recursive: true });
  for (const f of FILES) {
    const dest = path.join(CACHE, f.out);
    if (fs.existsSync(dest)) {
      console.log(`have   ${f.out}`);
    } else {
      console.log(`fetch  ${f.url}`);
      execFileSync('curl', ['-sSL', '--max-time', '600', '-o', dest, f.url], { stdio: 'inherit' });
    }
    if (f.extract === 'tar') {
      execFileSync('tar', ['xjf', dest, '-C', CACHE], { stdio: 'inherit' });
    } else {
      execFileSync('bunzip2', ['-kf', dest], { stdio: 'inherit' });
    }
  }
  for (const n of ['jpn_indices.csv', 'jpn_sentences.tsv']) {
    const p = path.join(CACHE, n);
    console.log(`${n}: ${fs.existsSync(p) ? (fs.statSync(p).size / 1e6).toFixed(1) + ' MB' : 'MISSING'}`);
  }
  console.log('\nnext: node tools/ime-eval/build_real_corpus.js');
}

main();
