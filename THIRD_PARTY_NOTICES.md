# Third-Party Notices

This project ships derived data generated from the mozc project's
open-source dictionary and connection-cost data, augmented with
kanji-spelling vocabulary from JMdict and SudachiDict (see
`tools/mozc_data/build_mozc_engine.py`, `tools/mozc_data/
build_jmdict_augment.py`, and `tools/mozc_data/build_sudachi_augment.py`),
used to build the optional "統計データ" (mozc-derived) conversion engine,
which the user can enable alongside the app's own hand-built dictionary
via a settings toggle. The generated files
(`entry/src/main/resources/rawfile/mozc_dict.json`, `mozc_costs.json`,
`mozc_matrix.json`) are derived works of the data below and are covered by
the same license terms.

(An earlier round also fetched and merged in real mecab-ipadic's own
connection-cost matrix directly from https://github.com/taku910/mecab --
that merge was later superseded by using mozc's own matrix unreduced,
which measured better; see `tools/mozc_data/build_mozc_engine.py`'s module
docstring and git history. mozc's own bundled dictionary text is still
itself IPAdic-derived per mozc's own documentation, which is what the
"IPAdic-derived dictionary entries" section below covers -- that one is
unrelated to the now-removed direct fetch and still applies.)

Sources:
- https://github.com/google/mozc (branch: master, `src/data/dictionary_oss/`)
- https://www.edrdg.org/ (JMdict, via http://ftp.edrdg.org/pub/Nihongo/JMdict.gz)
  — used only to append extra kanji-spelling candidates to readings mozc's
  own dictionary already recognises (`tools/mozc_data/build_jmdict_augment.py`).
  See the "JMdict (CC BY-SA 4.0)" section below for the license text and
  the attribution/share-alike/update-mechanism terms this data carries.
- https://github.com/WorksApplications/SudachiDict (lexicon CSVs fetched
  from the project's own distribution bucket, see
  `tools/mozc_data/fetch_sudachi.py`) — used the same way as JMdict, only
  to append extra kanji-spelling candidates to readings mozc's own
  dictionary already recognises
  (`tools/mozc_data/build_sudachi_augment.py`). See the "SudachiDict
  (Apache License 2.0)" section below.

---

## mozc (connection cost data, POS definitions, and Google-authored
## dictionary additions) — BSD-3-Clause

```
Copyright 2010-2018, Google Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above
    copyright notice, this list of conditions and the following disclaimer
    in the documentation and/or other materials provided with the
    distribution.
  * Neither the name of Google Inc. nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## IPAdic-derived dictionary entries (files: `dictionary*.txt`) — NAIST /
## ICOT license (permissive)

```
Copyright 2000, 2001, 2002, 2003 Nara Institute of Science
and Technology.  All Rights Reserved.

Use, reproduction, and distribution of this software is permitted.
Any copy of this software, whether in its original form or modified,
must include both the above copyright notice and the following
paragraphs.

Nara Institute of Science and Technology (NAIST),
the copyright holders, disclaims all warranties with regard to this
software, including all implied warranties of merchantability and
fitness, in no event shall NAIST be liable for
any special, indirect or consequential damages or any damages
whatsoever resulting from loss of use, data or profits, whether in an
action of contract, negligence or other tortuous action, arising out
of or in connection with the use or performance of this software.

A large portion of the dictionary entries
originate from ICOT Free Software.  The following conditions for ICOT
Free Software applies to the current dictionary as well.

Each User may also freely distribute the Program, whether in its
original form or modified, to any third party or parties, PROVIDED
that the provisions of Section 3 ("NO WARRANTY") will ALWAYS appear
on, or be attached to, the Program, which is distributed substantially
in the same form as set out herein and that such intended
distribution, if actually made, will neither violate or otherwise
contravene any of the laws and regulations of the countries having
jurisdiction over the User or the intended distribution itself.

NO WARRANTY

The program was produced on an experimental basis in the course of the
research and development conducted during the project and is provided
to users as so produced on an experimental basis.  Accordingly, the
program is provided without any warranty whatsoever, whether express,
implied, statutory or otherwise.  The term "warranty" used herein
includes, but is not limited to, any warranty of the quality,
performance, merchantability and fitness for a particular purpose of
the program and the nonexistence of any infringement or violation of
any right of any third party.

Each user of the program will agree and understand, and be deemed to
have agreed and understood, that there is no warranty whatsoever for
the program and, accordingly, the entire risk arising from or
otherwise connected with the program is assumed by the user.

Therefore, neither ICOT, the copyright holder, or any other
organization that participated in or was otherwise related to the
development of the program and their respective officials, directors,
officers and other employees shall be held liable for any and all
damages, including, without limitation, general, special, incidental
and consequential damages, arising out of or otherwise in connection
with the use or inability to use the program or any product, material
or result produced or otherwise obtained by using the program,
regardless of whether they have been advised of, or otherwise had
knowledge of, the possibility of such damages at any time during the
project or thereafter.  Each user will be deemed to have agreed to the
foregoing by his or her commencement of use of the program.  The term
"use" as used herein includes, but is not limited to, the use,
modification, copying and distribution of the program and the
production of secondary products from the program.

In the case where the program, whether in its original form or
modified, was distributed or delivered to or received by a user from
any person, organization or entity other than ICOT, unless it makes or
grants independently of ICOT any specific warranty to the user in
writing, such person, organization or entity, will also be exempted
from and not be held liable to the user for any such damages as noted
above as far as the program is concerned.
```

## JMdict/EDICT (kanji-spelling candidate augmentation for the "統計データ"
## engine only, via `tools/mozc_data/build_jmdict_augment.py`) —
## CC BY-SA 4.0

Source: https://www.edrdg.org/ (The Electronic Dictionary Research and
Development Group), file fetched: http://ftp.edrdg.org/pub/Nihongo/JMdict.gz

License: Creative Commons Attribution-ShareAlike 4.0 International
(https://creativecommons.org/licenses/by-sa/4.0/). Full terms and the
EDRDG's own usage policy: https://www.edrdg.org/edrdg/licence.html

This project's use, and how it satisfies the license's conditions:
- **Attribution**: this notice, the in-app "ⓘ ライセンス" screen
  (`SymbolView.ets`), and `DATA_SOURCES.md` each credit JMdict/EDICT by
  name with a link to the EDRDG's project page, as required by both CC
  BY-SA 4.0 and the EDRDG's own stated policy for software/apps using
  these files.
- **ShareAlike**: only the derived, redistributed data
  (`entry/src/main/resources/rawfile/mozc_dict.json`'s appended candidate
  surfaces) is a JMdict-derived work; it is covered by this same CC BY-SA
  4.0 license, consistent with every other file in this repository being
  under a permissive/compatible license already (see the app code's own
  MIT license, noted in the in-app license screen).
- **"Regular updating" requirement**: the EDRDG's policy asks that
  software using JMdict data implement "a procedure for regular updating
  of the data from the most recent versions available." This project does
  not fetch JMdict at runtime (it is baked into a static shipped asset at
  build time, like every other data source here); the update procedure is
  to re-run `tools/mozc_data/fetch_jmdict.py` (which always re-downloads if
  the local cache is cleared) followed by
  `tools/mozc_data/build_jmdict_augment.py` before each release that
  touches track B's data, so the shipped snapshot doesn't go stale
  indefinitely.

Note: JMdict/EDICT was already used, separately, as one of several sources
for the hand-built `dict.json`/`global_dict.json` vocabulary (track A) --
see `DATA_SOURCES.md` and the in-app license screen's existing "変換辞書"
section. The usage documented here is a second, independent, later use of
the same source: appending extra kanji-spelling candidates to track B's
`mozc_dict.json` (see `tools/mozc_data/README.md`'s "JMdict vocabulary
augmentation" section for the mechanism and scope).

## SudachiDict (kanji-spelling candidate augmentation for the "統計データ"
## engine only, via `tools/mozc_data/build_sudachi_augment.py`) —
## Apache License 2.0

Source: https://github.com/WorksApplications/SudachiDict, copyright
2017-2023 Works Applications Co., Ltd. Lexicon CSVs fetched from the
project's own distribution host (see `tools/mozc_data/fetch_sudachi.py`
for the exact URLs, discovered via that host's public bucket listing).

License: Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0). SudachiDict's own README
states the project "incorporates UniDic and a part of NEologd" and
distributes the resulting lexicon as a whole under Apache-2.0, without
carving out separate terms for those incorporated components.

This project's use: only the "small" and "core" lexicon tiers (not the
much larger "notcore"/full tier of proper nouns) are scanned for entries
whose reading already exists as a key in `mozc_dict.json`; their kanji
surface is appended as an extra candidate for that reading, exactly like
the JMdict augmentation above (same "never adds a new reading key" safe
mode — see `build_sudachi_augment.py` and `build_jmdict_augment.py`'s
module docstrings, and `tools/mozc_data/README.md`, for why). Apache-2.0
is a permissive license (attribution required, no share-alike/copyleft
obligation on derivative data) — satisfied by this notice, the in-app "ⓘ
ライセンス" screen (`SymbolView.ets`), and `DATA_SOURCES.md`.

## Okinawa Dictionary entries (also within files: `dictionary*.txt`) —
## Public Domain

```
Public Domain Dataです。使用・変更・配布に関しては一切の制限をつけません。
商品などに組み込むことも自由に行なってください。すでにいくつかの辞書には沖縄辞書が採用されています。
勝手ながら、沖縄辞書に寄贈された辞書も in the Public Domain' 扱いとさせていただきます。
```

Source: http://sourceforge.jp/projects/o-dic/
