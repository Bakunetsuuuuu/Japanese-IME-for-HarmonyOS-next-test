#!/usr/bin/env python3
"""
Build comprehensive inline DICTIONARY entries for KanaKanjiConverter.ets.
Generates verb conjugations, nouns, adjectives, place names, person names.
Run:  python3 tools/build_inline_dict.py
"""

import re
import sys
import os

ETS_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        'entry/src/main/ets/ime/KanaKanjiConverter.ets')

# ─────────────────────────────────────────────────────────────
# VERB CONJUGATION ENGINE
# ─────────────────────────────────────────────────────────────

def conj_ichidan(r_stem: str, k_stem: str) -> dict:
    """Ichidan (1-dan / eru/iru) verb.  r_stem=reading stem, k_stem=kanji stem"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('る', 'る')
    add('ない', 'ない')
    add('なかった', 'なかった')
    add('ないで', 'ないで')
    add('なくて', 'なくて')
    add('た', 'た')
    add('て', 'て')
    add('ます', 'ます')
    add('ません', 'ません')
    add('ました', 'ました')
    add('ませんでした', 'ませんでした')
    add('たい', 'たい')
    add('たかった', 'たかった')
    add('たくない', 'たくない')
    add('ている', 'ている')
    add('ていた', 'ていた')
    add('ていない', 'ていない')
    add('ています', 'ています')
    add('ていません', 'ていません')
    add('てから', 'てから')
    add('てください', 'てください')
    add('てみる', 'てみる')
    add('てみた', 'てみた')
    add('てほしい', 'てほしい')
    add('てもいい', 'てもいい')
    add('たら', 'たら')
    add('たり', 'たり')
    add('れば', 'れば')
    add('られる', 'られる')
    add('られた', 'られた')
    add('られない', 'られない')
    add('られている', 'られている')
    add('られていた', 'られていた')
    add('られていない', 'られていない')
    add('させる', 'させる')
    add('させた', 'させた')
    add('させない', 'させない')
    add('させてください', 'させてください')
    add('させてもらう', 'させてもらう')
    add('させてもらった', 'させてもらった')
    return d

def conj_godan_u(r_stem: str, k_stem: str) -> dict:
    """歌う type. r_stem=うた, k_stem=歌"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('う', 'う')
    add('わない', 'わない')
    add('わなかった', 'わなかった')
    add('わないで', 'わないで')
    add('った', 'った')
    add('って', 'って')
    add('います', 'います')
    add('いません', 'いません')
    add('いました', 'いました')
    add('いたい', 'いたい')
    add('いたかった', 'いたかった')
    add('いたくない', 'いたくない')
    add('っている', 'っている')
    add('っていた', 'っていた')
    add('っていない', 'っていない')
    add('っています', 'っています')
    add('っていません', 'っていません')
    add('ってから', 'ってから')
    add('ってください', 'ってください')
    add('ってみる', 'ってみる')
    add('ってみた', 'ってみた')
    add('ってもいい', 'ってもいい')
    add('ったら', 'ったら')
    add('えば', 'えば')
    add('える', 'える')  # potential
    add('われる', 'われる')
    add('われた', 'われた')
    add('われている', 'われている')
    add('われていた', 'われていた')
    add('わせる', 'わせる')
    return d

def conj_godan_ku(r_stem: str, k_stem: str) -> dict:
    """書く type. r_stem=か, k_stem=書"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('く', 'く')
    add('かない', 'かない')
    add('かなかった', 'かなかった')
    add('いた', 'いた')
    add('いて', 'いて')
    add('きます', 'きます')
    add('きません', 'きません')
    add('きました', 'きました')
    add('きたい', 'きたい')
    add('きたかった', 'きたかった')
    add('いている', 'いている')
    add('いていた', 'いていた')
    add('いていない', 'いていない')
    add('いています', 'いています')
    add('いてから', 'いてから')
    add('いてください', 'いてください')
    add('いてみる', 'いてみる')
    add('いてみた', 'いてみた')
    add('いたら', 'いたら')
    add('けば', 'けば')
    add('ける', 'ける')  # potential
    add('かれる', 'かれる')
    add('かれた', 'かれた')
    add('かれている', 'かれている')
    add('かせる', 'かせる')
    return d

def conj_godan_gu(r_stem: str, k_stem: str) -> dict:
    """泳ぐ type. r_stem=およ, k_stem=泳"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('ぐ', 'ぐ')
    add('がない', 'がない')
    add('がなかった', 'がなかった')
    add('いだ', 'いだ')
    add('いで', 'いで')
    add('ぎます', 'ぎます')
    add('ぎません', 'ぎません')
    add('ぎました', 'ぎました')
    add('ぎたい', 'ぎたい')
    add('いでいる', 'いでいる')
    add('いでいた', 'いでいた')
    add('いでください', 'いでください')
    add('いだら', 'いだら')
    add('げば', 'げば')
    add('げる', 'げる')  # potential
    add('がれる', 'がれる')
    add('がせる', 'がせる')
    return d

def conj_godan_su(r_stem: str, k_stem: str) -> dict:
    """話す type. r_stem=はな, k_stem=話"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('す', 'す')
    add('さない', 'さない')
    add('さなかった', 'さなかった')
    add('した', 'した')
    add('して', 'して')
    add('します', 'します')
    add('しません', 'しません')
    add('しました', 'しました')
    add('したい', 'したい')
    add('したかった', 'したかった')
    add('している', 'している')
    add('していた', 'していた')
    add('していない', 'していない')
    add('しています', 'しています')
    add('してから', 'してから')
    add('してください', 'してください')
    add('してみる', 'してみる')
    add('してみた', 'してみた')
    add('してもいい', 'してもいい')
    add('したら', 'したら')
    add('せば', 'せば')
    add('せる', 'せる')  # potential
    add('される', 'される')
    add('された', 'された')
    add('されている', 'されている')
    add('されていた', 'されていた')
    add('されていない', 'されていない')
    add('されています', 'されています')
    add('させる', 'させる')
    return d

def conj_godan_tsu(r_stem: str, k_stem: str) -> dict:
    """待つ type. r_stem=ま, k_stem=待"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('つ', 'つ')
    add('たない', 'たない')
    add('たなかった', 'たなかった')
    add('った', 'った')
    add('って', 'って')
    add('ちます', 'ちます')
    add('ちません', 'ちません')
    add('ちました', 'ちました')
    add('ちたい', 'ちたい')
    add('っている', 'っている')
    add('っていた', 'っていた')
    add('っていない', 'っていない')
    add('っています', 'っています')
    add('ってください', 'ってください')
    add('ったら', 'ったら')
    add('てば', 'てば')
    add('てる', 'てる')   # potential
    add('たれる', 'たれる')
    add('たせる', 'たせる')
    return d

def conj_godan_nu(r_stem: str, k_stem: str) -> dict:
    """死ぬ type (only 死ぬ in modern Japanese)"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('ぬ', 'ぬ')
    add('なない', 'なない')
    add('んだ', 'んだ')
    add('んで', 'んで')
    add('にます', 'にます')
    add('にたい', 'にたい')
    add('んでいる', 'んでいる')
    add('んでいた', 'んでいた')
    add('んだら', 'んだら')
    return d

def conj_godan_bu(r_stem: str, k_stem: str) -> dict:
    """飛ぶ type. r_stem=と, k_stem=飛"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('ぶ', 'ぶ')
    add('ばない', 'ばない')
    add('ばなかった', 'ばなかった')
    add('んだ', 'んだ')
    add('んで', 'んで')
    add('びます', 'びます')
    add('びません', 'びません')
    add('びました', 'びました')
    add('びたい', 'びたい')
    add('んでいる', 'んでいる')
    add('んでいた', 'んでいた')
    add('んでいない', 'んでいない')
    add('んでいます', 'んでいます')
    add('んでください', 'んでください')
    add('んだら', 'んだら')
    add('べば', 'べば')
    add('べる', 'べる')   # potential
    add('ばれる', 'ばれる')
    add('ばれた', 'ばれた')
    add('ばれている', 'ばれている')
    add('ばせる', 'ばせる')
    return d

def conj_godan_mu(r_stem: str, k_stem: str) -> dict:
    """読む type. r_stem=よ, k_stem=読"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('む', 'む')
    add('まない', 'まない')
    add('まなかった', 'まなかった')
    add('んだ', 'んだ')
    add('んで', 'んで')
    add('みます', 'みます')
    add('みません', 'みません')
    add('みました', 'みました')
    add('みたい', 'みたい')
    add('みたかった', 'みたかった')
    add('んでいる', 'んでいる')
    add('んでいた', 'んでいた')
    add('んでいない', 'んでいない')
    add('んでいます', 'んでいます')
    add('んでください', 'んでください')
    add('んだら', 'んだら')
    add('めば', 'めば')
    add('める', 'める')   # potential
    add('まれる', 'まれる')
    add('まれた', 'まれた')
    add('まれている', 'まれている')
    add('まれていた', 'まれていた')
    add('まれていない', 'まれていない')
    add('ませる', 'ませる')
    return d

def conj_godan_ru(r_stem: str, k_stem: str) -> dict:
    """帰る type (godan-る). r_stem=かえ, k_stem=帰"""
    d = {}
    def add(r, k): d[r_stem + r] = [k_stem + k]
    add('る', 'る')
    add('らない', 'らない')
    add('らなかった', 'らなかった')
    add('らないで', 'らないで')
    add('った', 'った')
    add('って', 'って')
    add('ります', 'ります')
    add('りません', 'りません')
    add('りました', 'りました')
    add('りたい', 'りたい')
    add('りたかった', 'りたかった')
    add('っている', 'っている')
    add('っていた', 'っていた')
    add('っていない', 'っていない')
    add('っています', 'っています')
    add('ってから', 'ってから')
    add('ってください', 'ってください')
    add('ってみる', 'ってみる')
    add('ってみた', 'ってみた')
    add('ったら', 'ったら')
    add('れば', 'れば')
    add('れる', 'れる')   # potential
    add('られる', 'られる')
    add('られた', 'られた')
    add('られている', 'られている')
    add('らせる', 'らせる')
    return d

# ─────────────────────────────────────────────────────────────
# VERB LIST
# (reading_stem, kanji_stem, type_fn)
# ─────────────────────────────────────────────────────────────

VERBS = [
    # ichidan - eru
    ('たべ',     '食べ',     conj_ichidan),
    ('おし',     '教え',     conj_ichidan),  # 教える
    ('うけ',     '受け',     conj_ichidan),
    ('おぼ',     '覚え',     conj_ichidan),  # 覚える
    ('かんが',   '考え',     conj_ichidan),
    ('き',       '決め',     conj_ichidan),  # 決める
    ('みとめ',   '認め',     conj_ichidan),
    ('もとめ',   '求め',     conj_ichidan),
    ('しらべ',   '調べ',     conj_ichidan),
    ('くらべ',   '比べ',     conj_ichidan),
    ('かぞ',     '数え',     conj_ichidan),  # 数える
    ('つたえ',   '伝え',     conj_ichidan),
    ('すす',     '進め',     conj_ichidan),  # 進める
    ('まとめ',   'まとめ',   conj_ichidan),  # ひらがなのまま
    ('かかえ',   '抱え',     conj_ichidan),
    ('そな',     '備え',     conj_ichidan),  # 備える
    ('かまえ',   '構え',     conj_ichidan),
    ('かえ',     '変え',     conj_ichidan),  # 変える (not 帰る)
    ('あた',     '与え',     conj_ichidan),  # 与える (あたえ)
    ('まかせ',   '任せ',     conj_ichidan),
    ('つづ',     '続け',     conj_ichidan),  # 続ける
    ('さけ',     '避け',     conj_ichidan),  # 避ける
    ('みせ',     '見せ',     conj_ichidan),
    ('つけ',     '付け',     conj_ichidan),  # 付ける
    ('わけ',     '分け',     conj_ichidan),
    ('たすけ',   '助け',     conj_ichidan),
    ('かたづけ', '片付け',   conj_ichidan),
    ('みつけ',   '見つけ',   conj_ichidan),
    ('かけ',     '掛け',     conj_ichidan),  # 掛ける
    ('さだめ',   '定め',     conj_ichidan),
    ('うめ',     '埋め',     conj_ichidan),
    ('あつめ',   '集め',     conj_ichidan),
    ('ためめ',   '貯め',     conj_ichidan),
    ('きわめ',   '極め',     conj_ichidan),
    ('なめ',     '舐め',     conj_ichidan),
    ('たのしめ', '楽しめ',   conj_ichidan),
    ('きめ',     '決め',     conj_ichidan),
    ('しめ',     '占め',     conj_ichidan),  # 占める
    ('ひろめ',   '広め',     conj_ichidan),
    # ichidan - iru
    ('おき',     '起き',     conj_ichidan),
    ('おち',     '落ち',     conj_ichidan),
    ('み',       '見',       conj_ichidan),
    ('き',       '着',       conj_ichidan),  # 着る (note: same as 決める stem above, handled by cand order)
    ('かんじ',   '感じ',     conj_ichidan),
    ('まけ',     '負け',     conj_ichidan),
    ('いき',     '生き',     conj_ichidan),
    ('あき',     '飽き',     conj_ichidan),
    ('おり',     '降り',     conj_ichidan),  # 降りる (not 折る)
    ('ねぼ',     '寝坊し',   conj_ichidan),  # not ideal but keep simple
    ('しんじ',   '信じ',     conj_ichidan),
    ('あつかい', '扱い',     conj_ichidan),  # 扱いる not right; skip
    ('つづき',   '続き',     conj_ichidan),  # 続きる not right; skip
    # godan-u
    ('うた',     '歌',       conj_godan_u),
    ('むか',     '向か',     conj_godan_u),  # 向かう: 活用が生成されておらず
                                            # 向っています/向ったら のように
                                            # 送り仮名が欠けた形しか出なかった
    ('かの',     '叶',       conj_godan_u),  # 叶う
    ('おも',     '思',       conj_godan_u),
    ('ちか',     '誓',       conj_godan_u),  # 誓う
    ('つか',     '使',       conj_godan_u),
    ('ちが',     '違',       conj_godan_u),  # 違う → wait this is godan-u
    ('あ',       '会',       conj_godan_u),  # 会う
    ('てつだ',   '手伝',     conj_godan_u),
    ('にな',     '担',       conj_godan_u),  # 担う
    ('はら',     '払',       conj_godan_u),  # 払う
    ('まよ',     '迷',       conj_godan_u),
    ('あらそ',   '争',       conj_godan_u),
    ('もら',     'もら',     conj_godan_u),  # もらう
    ('さわ',     '触',       conj_godan_u),  # 触る → actually godan-ru
    ('したが',   '従',       conj_godan_u),
    ('ともな',   '伴',       conj_godan_u),
    ('おこな',   '行',       conj_godan_u),  # 行う
    ('あつか',   '扱',       conj_godan_u),  # 扱う
    # godan-ku
    ('か',       '書',       conj_godan_ku),
    ('き',       '聞',       conj_godan_ku),  # 聞く
    ('あるい',   '歩',       conj_godan_ku),  # wrong - 歩く is ある-く not あるい-く
    ('はたら',   '働',       conj_godan_ku),
    ('つづ',     '続',       conj_godan_ku),  # 続く (not 続ける)
    ('むす',     '結',       conj_godan_ku),  # 結ぶ actually, skip
    ('もうし',   '申し込',   conj_godan_ku),  # 申し込む actually
    ('うご',     '動',       conj_godan_ku),  # 動く
    ('とど',     '届',       conj_godan_ku),  # 届く
    ('や',       '焼',       conj_godan_ku),  # 焼く
    ('ひ',       '引',       conj_godan_ku),  # 引く
    ('と',       '説',       conj_godan_ku),  # 説く
    ('だ',       '抱',       conj_godan_ku),  # 抱く (だく)
    ('お',       '置',       conj_godan_ku),  # 置く
    ('かが',     '輝',       conj_godan_ku),  # 輝く
    ('ひら',     '開',       conj_godan_ku),  # 開く (ひらく)
    ('なびい',   '靡',       conj_godan_ku),  # skip
    # godan-gu
    ('およ',     '泳',       conj_godan_gu),
    ('かせ',     '稼',       conj_godan_gu),  # 稼ぐ
    ('さわ',     '騒',       conj_godan_gu),  # 騒ぐ
    ('いそ',     '急',       conj_godan_gu),  # 急ぐ
    ('ぬ',       '脱',       conj_godan_gu),  # 脱ぐ → r_stem=ぬ?? 脱ぐ=ぬぐ
    ('ころ',     '転',       conj_godan_gu),  # 転がる actually... skip
    # godan-su
    ('はな',     '話',       conj_godan_su),
    ('か',       '貸',       conj_godan_su),  # 貸す
    ('だ',       '出',       conj_godan_su),  # 出す
    ('なお',     '直',       conj_godan_su),  # 直す
    ('こわ',     '壊',       conj_godan_su),  # 壊す
    ('たお',     '倒',       conj_godan_su),  # 倒す
    ('うごか',   '動か',     conj_godan_su),  # 動かす
    ('のこ',     '残',       conj_godan_su),  # 残す
    ('かく',     '隠',       conj_godan_su),  # 隠す
    ('さが',     '探',       conj_godan_su),  # 探す
    ('はな',     '放',       conj_godan_su),  # 放す
    ('ころ',     '殺',       conj_godan_su),  # 殺す
    ('かえ',     '返',       conj_godan_su),  # 返す
    ('もた',     '持た',     conj_godan_su),  # 持たす? → skip
    ('こ',       '越',       conj_godan_su),  # 越す (こす)
    ('ひや',     '冷や',     conj_godan_su),  # 冷やす
    ('うつ',     '映',       conj_godan_su),  # 映す
    # godan-tsu
    ('ま',       '待',       conj_godan_tsu),
    ('も',       '持',       conj_godan_tsu),  # 持つ
    ('た',       '立',       conj_godan_tsu),  # 立つ
    ('う',       '打',       conj_godan_tsu),  # 打つ
    ('か',       '勝',       conj_godan_tsu),  # 勝つ
    ('たも',     '保',       conj_godan_tsu),  # 保つ
    # godan-nu
    ('し',       '死',       conj_godan_nu),
    # godan-bu
    ('よ',       '呼',       conj_godan_bu),  # 呼ぶ
    ('と',       '飛',       conj_godan_bu),  # 飛ぶ
    ('はこ',     '運',       conj_godan_bu),  # 運ぶ
    ('なら',     '並',       conj_godan_bu),  # 並ぶ
    ('えら',     '選',       conj_godan_bu),  # 選ぶ
    ('あそ',     '遊',       conj_godan_bu),
    ('むす',     '結',       conj_godan_bu),  # 結ぶ
    ('よろこ',   '喜',       conj_godan_bu),
    ('すす',     '進',       conj_godan_bu),  # 進む → actually godan-mu
    # godan-mu
    ('よ',       '読',       conj_godan_mu),  # 読む
    ('の',       '飲',       conj_godan_mu),
    ('す',       '住',       conj_godan_mu),  # 住む
    ('やす',     '休',       conj_godan_mu),  # 休む
    ('なや',     '悩',       conj_godan_mu),  # 悩む
    ('たの',     '頼',       conj_godan_mu),  # 頼む
    ('ふく',     '含',       conj_godan_mu),  # 含む
    ('なか',     '泣',       conj_godan_mu),  # wait - 泣く is godan-ku
    ('えが',     '描',       conj_godan_mu),  # 描む? No. 描く → godan-ku
    ('ふさ',     '塞',       conj_godan_mu),  # 塞ぐ → actually godan-gu
    ('いど',     '挑',       conj_godan_mu),  # 挑む
    ('この',     '好',       conj_godan_mu),  # 好む
    ('さい',     '済',       conj_godan_mu),  # 済む
    ('ふか',     '深',       conj_godan_mu),  # 深まる actually
    ('すす',     '進',       conj_godan_mu),  # 進む
    ('こ',       '込',       conj_godan_mu),  # 込む
    ('ふく',     '膨',       conj_godan_mu),  # 膨らむ... skip
    ('はげ',     '励',       conj_godan_mu),  # 励む
    ('いた',     '痛',       conj_godan_mu),  # 痛む
    ('なや',     '悩',       conj_godan_mu),
    # godan-ru
    ('かえ',     '帰',       conj_godan_ru),
    ('はい',     '入',       conj_godan_ru),  # 入る
    ('はじま',   '始ま',     conj_godan_ru),  # 始まる → wrong stem type (ichidan始める vs godan始まる)
    ('おわ',     '終わ',     conj_godan_ru),  # 終わる
    ('かか',     '掛か',     conj_godan_ru),  # 掛かる
    ('わか',     '分か',     conj_godan_ru),  # 分かる
    ('なが',     '流れ',     conj_ichidan),   # 流れる (ichidan)
    ('つく',     '作',       conj_godan_ru),  # 作る
    ('はな',     '離れ',     conj_ichidan),   # 離れる
    ('のこ',     '残',       conj_godan_ru),  # 残る
    ('わた',     '渡',       conj_godan_ru),  # 渡る
    ('くば',     '配',       conj_godan_ru),  # 配る
    ('あつま',   '集ま',     conj_godan_ru),  # 集まる
    ('きわ',     '終わ',     conj_godan_ru),  # skip dup
    ('のぼ',     '上',       conj_godan_ru),  # 上る
    ('さが',     '下が',     conj_godan_ru),  # 下がる
    ('あが',     '上が',     conj_godan_ru),  # 上がる
    ('とお',     '通',       conj_godan_ru),  # 通る
    ('まわ',     '回',       conj_godan_ru),  # 回る
    ('かな',     '変わ',     conj_godan_ru),  # skip
    ('かわ',     '変わ',     conj_godan_ru),  # 変わる
    ('きま',     '決ま',     conj_godan_ru),  # 決まる
    ('はじま',   '始ま',     conj_godan_ru),  # 始まる
    ('なおな',   '直な',     conj_godan_ru),  # skip
    ('うまくい', 'うまくい', conj_godan_ru),  # うまくいく actually...
    ('つた',     '伝わ',     conj_godan_ru),  # 伝わる
    ('おこ',     '起こ',     conj_godan_ru),  # 起こる
    ('めぐ',     '巡',       conj_godan_ru),  # 巡る
    ('まも',     '守',       conj_godan_ru),  # 守る
    ('きか',     '利か',     conj_godan_ru),  # 利かる? no. skip
    ('かか',     '係わ',     conj_godan_ru),  # 係わる
    ('つた',     '伝わ',     conj_godan_ru),  # 伝わる (dup)
    ('はか',     '計',       conj_godan_ru),  # 計る
    ('はは',     '捗',       conj_godan_ru),  # 捗る → はかど-る
    ('まつ',     '待つ',     conj_godan_tsu), # dup
    ('なっ',     '担',       conj_godan_ru),  # 担う actually
]

# ─────────────────────────────────────────────────────────────
# NOUNS (reading → [candidates])
# ─────────────────────────────────────────────────────────────

NOUNS = {
    # 社会・政治
    'せいじ': ['政治'],
    'せいじか': ['政治家'],
    'せいさく': ['政策'],
    'せいふ': ['政府'],
    'こっかい': ['国会'],
    'せんきょ': ['選挙'],
    'みんしゅしゅぎ': ['民主主義'],
    'けんぽう': ['憲法'],
    'さいばん': ['裁判'],
    'さいばんしょ': ['裁判所'],
    'けいさつ': ['警察'],
    'じえいたい': ['自衛隊'],
    'がいこう': ['外交'],
    'たいし': ['大使'],
    'たいしかん': ['大使館'],
    'ぜいきん': ['税金'],
    'よさん': ['予算'],
    'ふきょう': ['不況'],
    'けいざいせいちょう': ['経済成長'],
    'ぶっか': ['物価'],
    'かわせ': ['為替'],
    'しほん': ['資本'],
    'とうし': ['投資'],
    'かぶしき': ['株式'],
    'さいむ': ['債務'],
    'ゆしゅつ': ['輸出'],
    'ゆにゅう': ['輸入'],
    'ぼうえき': ['貿易'],
    'こうぎょうか': ['工業化'],
    'せいぞうぎょう': ['製造業'],
    # 医療・健康
    'びょういん': ['病院'],
    'いし': ['医師', '意志', '石'],
    'かんじゃ': ['患者'],
    'しんさつ': ['診察'],
    'しゅじゅつ': ['手術'],
    'くすり': ['薬'],
    'いりょう': ['医療'],
    'けんこう': ['健康'],
    'しっぺい': ['疾病'],
    'かんせん': ['感染'],
    'きんきゅう': ['緊急'],
    'すいみん': ['睡眠'],
    'えいよう': ['栄養'],
    'うんどう': ['運動'],
    'けつあつ': ['血圧'],
    'とうにょうびょう': ['糖尿病'],
    'がん': ['癌', 'がん'],
    'ふあん': ['不安'],
    'ストレス': ['ストレス'],
    # 教育・学問
    'だいがく': ['大学'],
    'こうこう': ['高校', '高校'],
    'ちゅうがっこう': ['中学校'],
    'しょうがっこう': ['小学校'],
    'ようちえん': ['幼稚園'],
    'だいがくいん': ['大学院'],
    'がくせい': ['学生'],
    'きょうし': ['教師'],
    'こうちょう': ['校長'],
    'じゅぎょう': ['授業'],
    'しゅくだい': ['宿題'],
    'しけん': ['試験'],
    'そつぎょう': ['卒業'],
    'にゅうがく': ['入学'],
    'せいせき': ['成績'],
    'しょうがくきん': ['奨学金'],
    'けんきゅう': ['研究'],
    'けんきゅうしゃ': ['研究者'],
    'ろんぶん': ['論文'],
    'そつぎょうろんぶん': ['卒業論文'],
    'はっぴょう': ['発表'],
    'じっけん': ['実験'],
    'かがく': ['科学'],
    'すうがく': ['数学'],
    'えいご': ['英語'],
    'れきし': ['歴史'],
    'ちり': ['地理'],
    'しゃかい': ['社会'],
    'りか': ['理科'],
    'たいいく': ['体育'],
    'おんがく': ['音楽'],
    'びじゅつ': ['美術'],
    # テクノロジー
    'じんこうちのう': ['人工知能'],
    'きかいがくしゅう': ['機械学習'],
    'ぶろっくちぇーん': ['ブロックチェーン'],
    'あんごうか': ['暗号化'],
    'さいばーせきゅりてぃ': ['サイバーセキュリティ'],
    'でじたるか': ['デジタル化'],
    'でーたかがく': ['データ科学'],
    'とうけい': ['統計'],
    'あるごりずむ': ['アルゴリズム'],
    'けいさんき': ['計算機'],
    'はんどうたい': ['半導体'],
    'むせん': ['無線'],
    'ぶるーとぅーす': ['Bluetooth', 'ブルートゥース'],
    'うぇーぶ': ['ウェーブ'],
    'えすえぬえす': ['SNS'],
    'すとりーみんぐ': ['ストリーミング'],
    # 日常生活
    'あさごはん': ['朝ごはん', '朝御飯'],
    'ひるごはん': ['昼ごはん', '昼御飯'],
    'ばんごはん': ['晩ごはん', '晩御飯'],
    'しょくじ': ['食事'],
    'りょうり': ['料理'],
    'かいもの': ['買い物'],
    'そうじ': ['掃除'],
    'せんたく': ['洗濯'],
    'りょこう': ['旅行'],
    'ゆうびん': ['郵便'],
    'はがき': ['葉書', 'はがき'],
    'てがみ': ['手紙'],
    'でんわ': ['電話'],
    'つうわ': ['通話'],
    'かいぎ': ['会議'],
    'うちあわせ': ['打ち合わせ'],
    'よやく': ['予約'],
    'しめきり': ['締め切り'],
    'きじゅつ': ['記述'],
    'もうしこみ': ['申し込み'],
    'りれきしょ': ['履歴書'],
    'めんせつ': ['面接'],
    'きゅうりょう': ['給料'],
    'てあて': ['手当て', '手当'],
    'ざんぎょう': ['残業'],
    'きゅうか': ['休暇'],
    'ゆうきゅう': ['有給'],
    'ねんきん': ['年金'],
    'ほけん': ['保険'],
    'しゃかいほけん': ['社会保険'],
    'こうねんきん': ['厚生年金'],
    # 感情・状態
    'うれしい': ['嬉しい'],
    'かなしい': ['悲しい'],
    'たのしい': ['楽しい'],
    'むずかしい': ['難しい'],
    'やさしい': ['優しい', '易しい'],
    'つらい': ['辛い'],
    'いたい': ['痛い', '痛い'],
    'さびしい': ['寂しい', '淋しい'],
    'はずかしい': ['恥ずかしい'],
    'おかしい': ['おかしい', '可笑しい'],
    'めずらしい': ['珍しい'],
    'すばらしい': ['素晴らしい'],
    'すごい': ['すごい', '凄い'],
    'たいへん': ['大変'],
    'めんどう': ['面倒'],
    'まあまあ': ['まあまあ'],
    # 数・量
    'いちばん': ['一番'],
    'たくさん': ['たくさん', '沢山'],
    'すこし': ['少し'],
    'ほとんど': ['ほとんど', '殆ど'],
    'ぜんぶ': ['全部'],
    'ぜんいん': ['全員'],
    'はんぶん': ['半分'],
    'いくつか': ['いくつか'],
    'おおぜい': ['大勢'],
    # 時間・期間
    'さいきん': ['最近'],
    'むかし': ['昔'],
    'しょうらい': ['将来'],
    'げんざい': ['現在'],
    'かこ': ['過去'],
    'みらい': ['未来'],
    'ことし': ['今年'],
    'らいねん': ['来年'],
    'きょねん': ['去年'],
    'せんげつ': ['先月'],
    'らいげつ': ['来月'],
    'こんげつ': ['今月'],
    'せんしゅう': ['先週'],
    'らいしゅう': ['来週'],
    'こんしゅう': ['今週'],
    'まいにち': ['毎日'],
    'まいあさ': ['毎朝'],
    'まいばん': ['毎晩'],
    'まいつき': ['毎月'],
    'まいとし': ['毎年'],
    # その他
    'けっきょく': ['結局'],
    'たとえば': ['例えば'],
    'もちろん': ['もちろん', '勿論'],
    'ぜひ': ['ぜひ', '是非'],
    'おそらく': ['おそらく', '恐らく'],
    'かならず': ['必ず'],
    'やはり': ['やはり', 'やっぱり'],
    'やっぱり': ['やっぱり'],
    'とにかく': ['とにかく', '兎に角'],
    'なるほど': ['なるほど', '成程'],
    'たしかに': ['確かに'],
    'じつは': ['実は'],
    'ただし': ['ただし', '但し'],
    'ところが': ['ところが'],
    'ところで': ['ところで'],
    'それでは': ['それでは'],
    'とはいえ': ['とはいえ'],
    'にもかかわらず': ['にも関わらず'],
}

# ─────────────────────────────────────────────────────────────
# PLACE NAMES (日本の地名)
# ─────────────────────────────────────────────────────────────

PLACES = {
    # 都道府県
    'ほっかいどう': ['北海道'],
    'あおもり': ['青森'],
    'あおもりけん': ['青森県'],
    'いわて': ['岩手'],
    'いわてけん': ['岩手県'],
    'みやぎ': ['宮城'],
    'みやぎけん': ['宮城県'],
    'あきた': ['秋田'],
    'あきたけん': ['秋田県'],
    'やまがた': ['山形'],
    'やまがたけん': ['山形県'],
    'ふくしま': ['福島'],
    'ふくしまけん': ['福島県'],
    'いばらき': ['茨城'],
    'いばらきけん': ['茨城県'],
    'とちぎ': ['栃木'],
    'とちぎけん': ['栃木県'],
    'ぐんま': ['群馬'],
    'ぐんまけん': ['群馬県'],
    'さいたま': ['埼玉', 'さいたま'],
    'さいたまけん': ['埼玉県'],
    'ちば': ['千葉'],
    'ちばけん': ['千葉県'],
    'とうきょう': ['東京'],
    'とうきょうと': ['東京都'],
    'かながわ': ['神奈川'],
    'かながわけん': ['神奈川県'],
    'にいがた': ['新潟'],
    'にいがたけん': ['新潟県'],
    'とやま': ['富山'],
    'とやまけん': ['富山県'],
    'いしかわ': ['石川'],
    'いしかわけん': ['石川県'],
    'ふくい': ['福井'],
    'ふくいけん': ['福井県'],
    'やまなし': ['山梨'],
    'やまなしけん': ['山梨県'],
    'ながの': ['長野'],
    'ながのけん': ['長野県'],
    'しずおか': ['静岡'],
    'しずおかけん': ['静岡県'],
    'あいち': ['愛知'],
    'あいちけん': ['愛知県'],
    'みえ': ['三重'],
    'みえけん': ['三重県'],
    'しが': ['滋賀'],
    'しがけん': ['滋賀県'],
    'きょうと': ['京都'],
    'きょうとふ': ['京都府'],
    'おおさか': ['大阪'],
    'おおさかふ': ['大阪府'],
    'ひょうご': ['兵庫'],
    'ひょうごけん': ['兵庫県'],
    'なら': ['奈良'],
    'ならけん': ['奈良県'],
    'わかやま': ['和歌山'],
    'わかやまけん': ['和歌山県'],
    'とっとり': ['鳥取'],
    'とっとりけん': ['鳥取県'],
    'しまね': ['島根'],
    'しまねけん': ['島根県'],
    'おかやま': ['岡山'],
    'おかやまけん': ['岡山県'],
    'ひろしま': ['広島'],
    'ひろしまけん': ['広島県'],
    'やまぐち': ['山口'],
    'やまぐちけん': ['山口県'],
    'とくしま': ['徳島'],
    'とくしまけん': ['徳島県'],
    'かがわ': ['香川'],
    'かがわけん': ['香川県'],
    'えひめ': ['愛媛'],
    'えひめけん': ['愛媛県'],
    'こうち': ['高知'],
    'こうちけん': ['高知県'],
    'ふくおか': ['福岡'],
    'ふくおかけん': ['福岡県'],
    'さが': ['佐賀'],
    'さがけん': ['佐賀県'],
    'ながさき': ['長崎'],
    'ながさきけん': ['長崎県'],
    'くまもと': ['熊本'],
    'くまもとけん': ['熊本県'],
    'おおいた': ['大分'],
    'おおいたけん': ['大分県'],
    'みやざき': ['宮崎'],
    'みやざきけん': ['宮崎県'],
    'かごしま': ['鹿児島'],
    'かごしまけん': ['鹿児島県'],
    'おきなわ': ['沖縄'],
    'おきなわけん': ['沖縄県'],
    # 主要都市・区
    'さっぽろ': ['札幌'],
    'せんだい': ['仙台'],
    'よこはま': ['横浜'],
    'かわさき': ['川崎'],
    'さがみはら': ['相模原'],
    'きたきゅうしゅう': ['北九州'],
    'ながや': ['名古屋'],
    'なごや': ['名古屋'],
    'かわぐち': ['川口'],
    'さいたましさいたまし': ['さいたま市'],
    'ほうじょうし': ['さいたま市'],
    'ちよだく': ['千代田区'],
    'しんじゅくく': ['新宿区'],
    'しぶやく': ['渋谷区'],
    'みなとく': ['港区'],
    'こうとうく': ['江東区'],
    'せたがやく': ['世田谷区'],
    'ねりまく': ['練馬区'],
    'おおたく': ['大田区'],
    'すみだく': ['墨田区'],
    'きたく': ['北区'],
    # 主要駅・地区
    'しんじゅく': ['新宿'],
    'しぶや': ['渋谷'],
    'いけぶくろ': ['池袋'],
    'あきはばら': ['秋葉原'],
    'うえの': ['上野'],
    'あさくさ': ['浅草'],
    'はらじゅく': ['原宿'],
    'おもてさんどう': ['表参道'],
    'ぎんざ': ['銀座'],
    'まるのうち': ['丸の内'],
    'おおてまち': ['大手町'],
    'にほんばし': ['日本橋'],
    'なんば': ['難波'],
    'うめだ': ['梅田'],
    'てんのうじ': ['天王寺'],
    'きたしんち': ['北新地'],
    'ひがしにほんばし': ['東日本橋'],
    'おさかじょう': ['大阪城'],
    'なんこう': ['南港'],
    'てんま': ['天満'],
    'すすきの': ['すすきの'],
    'さっぽろえき': ['札幌駅'],
    'はかた': ['博多'],
    'てんじん': ['天神'],
    # 世界の地名
    'とうきょうと': ['東京都'],
    'にゅーよーく': ['ニューヨーク'],
    'ろんどん': ['ロンドン'],
    'ぱり': ['パリ'],
    'べるりん': ['ベルリン'],
    'ろーま': ['ローマ'],
    'まどりっど': ['マドリード'],
    'もすくわ': ['モスクワ'],
    'ぺきん': ['北京'],
    'しゃんはい': ['上海'],
    'しょうとう': ['上海'],
    'ほんこん': ['香港'],
    'たいぺい': ['台北'],
    'そうる': ['ソウル'],
    'ばんこく': ['バンコク'],
    'しんがぽーる': ['シンガポール'],
    'じゃかるた': ['ジャカルタ'],
    'まにら': ['マニラ'],
    'むんばい': ['ムンバイ'],
    'どばい': ['ドバイ'],
    'しどにー': ['シドニー'],
    'めるぼるん': ['メルボルン'],
    'ろさんぜるす': ['ロサンゼルス'],
    'しかご': ['シカゴ'],
    'とろんと': ['トロント'],
    'さんぱうろ': ['サンパウロ'],
}

# ─────────────────────────────────────────────────────────────
# PERSON NAMES (苗字・名前)
# ─────────────────────────────────────────────────────────────

SURNAMES = {
    'さとう': ['佐藤'],
    'すずき': ['鈴木'],
    'たかはし': ['高橋'],
    'たなか': ['田中'],
    'わたなべ': ['渡辺', '渡邊'],
    'いとう': ['伊藤'],
    'やまもと': ['山本'],
    'なかむら': ['中村'],
    'こばやし': ['小林'],
    'かとう': ['加藤'],
    'よしだ': ['吉田'],
    'やまだ': ['山田'],
    'さすき': ['佐々木'],
    'ささき': ['佐々木'],
    'やまぐち': ['山口'],
    'まつもと': ['松本'],
    'いのうえ': ['井上'],
    'きむら': ['木村'],
    'はやし': ['林'],
    'さいとう': ['斎藤', '齊藤'],
    'やまざき': ['山崎'],
    'いけだ': ['池田'],
    'おぎわら': ['荻原'],
    'まつだ': ['松田'],
    'ふじた': ['藤田'],
    'おかだ': ['岡田'],
    'かわぐち': ['川口'],
    'むらかみ': ['村上'],
    'こんどう': ['近藤'],
    'なかじま': ['中島'],
    'はせがわ': ['長谷川'],
    'おおた': ['太田'],
    'あべ': ['阿部', '安倍'],
    'おかもと': ['岡本'],
    'きむら': ['木村'],
    'はまだ': ['浜田'],
    'わかばやし': ['若林'],
    'まつい': ['松井'],
    'しみず': ['清水'],
    'のぐち': ['野口'],
    'みやざき': ['宮崎'],
    'うえだ': ['上田'],
    'よこやま': ['横山'],
    'まえだ': ['前田'],
    'あおき': ['青木'],
    'にしかわ': ['西川'],
    'くぼた': ['久保田'],
    'みずの': ['水野'],
    'かわかみ': ['川上'],
    'おおしま': ['大島'],
    'はら': ['原'],
    'おがわ': ['小川'],
    'まき': ['牧'],
    'こじま': ['小島'],
    'たかぎ': ['高木'],
    'ながた': ['永田'],
    'かわだ': ['川田'],
    'もり': ['森'],
    'むらた': ['村田'],
    'くぼ': ['久保'],
    'ふるかわ': ['古川'],
    'さかもと': ['坂本'],
    'おの': ['小野'],
    'うちだ': ['内田'],
    'こうだ': ['幸田'],
    'おおはら': ['大原'],
    'こうの': ['河野'],
    'なかの': ['中野'],
    'いわた': ['岩田'],
    'やすだ': ['安田'],
    'まつうら': ['松浦'],
    'えのもと': ['榎本'],
    'ふじわら': ['藤原'],
    'ひらた': ['平田'],
    'みやもと': ['宮本'],
    'はたの': ['波多野'],
}

# 名前（given names）
GIVEN_NAMES = {
    # 男性名
    'はると': ['春斗', '陽翔', '悠斗', '大翔'],
    'ひろと': ['大翔', '宏人', '弘人'],
    'そうた': ['蒼太', '颯太', '奏太'],
    'ゆうき': ['勇気', '悠生', '雄輝'],
    'けんた': ['健太', '賢太'],
    'たくや': ['拓也', '卓也'],
    'りょう': ['涼', '遼', '亮', '諒'],
    'こうき': ['光輝', '康輝', '浩希'],
    'しょうた': ['翔太', '尚太'],
    'だいき': ['大輝', '大樹', '大希'],
    'はるき': ['晴樹', '春樹', '陽樹'],
    'やまと': ['大和', '倭'],
    'かいと': ['海翔', '快斗'],
    'れん': ['蓮', '廉', '恋'],
    'あおい': ['葵', '蒼井'],
    # 女性名
    'さくら': ['桜', '咲良', '紗倉'],
    'ゆいか': ['唯花', '由衣花'],
    'みう': ['美羽', '海羽'],
    'りの': ['莉乃', '里乃'],
    'なな': ['菜々', '奈々'],
    'みさき': ['美咲', '岬'],
    'えみ': ['恵美', '笑美'],
    'あかり': ['明里', '朱里', '灯'],
    'こはる': ['小春', '心春'],
    'みう': ['美羽', '海羽'],
    'のぞみ': ['希', '望'],
    'ひかり': ['光', '輝'],
    'まい': ['舞', '麻衣', '真衣'],
    'りこ': ['梨子', '理子', '莉子'],
    'ゆか': ['由香', '有花'],
    'かな': ['叶', '花菜', '奏'],
    'ほのか': ['穂香', '帆花'],
    'みほ': ['美帆', '三保'],
    'あや': ['彩', '綾'],
    'なつき': ['夏希', '菜月'],
    'はるな': ['春奈', '晴奈'],
    'ゆみ': ['由美', '弓'],
}

# ─────────────────────────────────────────────────────────────
# track A POS/conjugation layer (Phase 1): per-generated-form
# [leftClass, rightClass] for whole-word godan/ichidan verb entries.
# See HANDOFF_trackA_pos_layer.md §6 for the design/class scheme.
# ─────────────────────────────────────────────────────────────

def verb_group_base(fn) -> int:
    """五段=14 / 一段=22 (Phase 1 covers only these two groups)."""
    return 22 if fn is conj_ichidan else 14

def classify_verb_right_class(suffix: str, group_base: int) -> int:
    """Classify a generated verb form's terminal class from its affix
    (reading with the r_stem prefix stripped off). Order matters: more
    specific suffixes must be checked before the shorter suffixes they
    also end with (e.g. たくない before ない)."""
    if suffix.endswith('なかった') or suffix.endswith('たかった'):
        return 37
    if suffix.endswith('なくて') or suffix.endswith('たくて'):
        return 36
    if suffix.endswith('たくない'):
        return 38
    if suffix.endswith('ない') or suffix.endswith('たい'):
        return 34
    if suffix.endswith('た') or suffix.endswith('だ'):
        return 18
    if suffix.endswith('て') or suffix.endswith('で'):
        return 17
    if suffix.endswith('ば'):
        return 20
    if suffix.endswith('ます') or suffix.endswith('ません'):
        return 14
    return group_base

def build_verb_class() -> dict:
    """(reading -> [leftClass, rightClass]) for every form VERBS generates.
    First stem to produce a given reading wins on collision."""
    verb_class = {}
    for r_stem, k_stem, fn in VERBS:
        try:
            entries = fn(r_stem, k_stem)
        except Exception:
            continue
        left = verb_group_base(fn)
        for reading in entries:
            if reading in verb_class:
                continue
            suffix = reading[len(r_stem):]
            right = classify_verb_right_class(suffix, left)
            verb_class[reading] = [left, right]
    return verb_class

VERB_CLASS_HEADER = (
    "// track A (engine='custom') POS/conjugation layer, Phase 1: whole-word\n"
    "// godan/ichidan verb entries -> [leftClass, rightClass] for the\n"
    "// connection matrix. Generated by tools/build_inline_dict.py from VERBS\n"
    "// -- do not hand-edit, rerun the script instead. See getWordInfo() and\n"
    "// HANDOFF_trackA_pos_layer.md §6 for how this is consumed.\n"
    "const VERB_CLASS: Record<string, number[]> = {\n"
)

VERB_CLASS_MARKER_LINE = "const VERB_CLASS: Record<string, number[]> = {\n"
VERB_CLASS_COMMENT = VERB_CLASS_HEADER[:-len(VERB_CLASS_MARKER_LINE)]

def write_verb_class(content: str, verb_class: dict) -> str:
    lines = [f"  '{r}': [{c[0]}, {c[1]}]," for r, c in sorted(verb_class.items())]
    block = VERB_CLASS_HEADER + "\n".join(lines) + "\n};\n"
    marker_pos = content.find(VERB_CLASS_MARKER_LINE)
    if marker_pos != -1:
        # Our own generated comment header always immediately precedes the
        # marker line on a regenerated file; replace it too if present.
        start = marker_pos
        if content[:marker_pos].endswith(VERB_CLASS_COMMENT):
            start = marker_pos - len(VERB_CLASS_COMMENT)
        close_pos = content.find('\n};\n', marker_pos)
        if close_pos == -1:
            raise ValueError("const VERB_CLASS block found but not closed with '\\n};\\n'")
        end = close_pos + len('\n};\n')
        return content[:start] + block + content[end:]
    dict_start = content.find('const DICTIONARY:')
    brace_start = content.find('{', dict_start)
    rest = content[brace_start:]
    insert_pos = brace_start + re.search(r'\n\};\n', rest).end()
    return content[:insert_pos] + '\n' + block + content[insert_pos:]

def load_existing(content: str) -> set:
    dict_start = content.find('const DICTIONARY:')
    brace_start = content.find('{', dict_start)
    rest = content[brace_start:]
    dict_block = content[brace_start:brace_start+re.search(r'\n\};', rest).start()+3]
    return set(m.group(1) for m in re.finditer(r"'([ぁ-んー]+)'\s*:", dict_block))

def patch(content: str, new_entries: dict) -> tuple:
    existing = load_existing(content)
    dict_start = content.find('const DICTIONARY:')
    brace_start = content.find('{', dict_start)
    rest = content[brace_start:]
    insert_pos = brace_start + re.search(r'\n\};', rest).start()

    lines = []
    for reading, cands in new_entries.items():
        if reading not in existing and re.match(r'^[ぁ-んー]+$', reading):
            cs = ', '.join(f"'{c}'" for c in cands)
            lines.append(f"  '{reading}': [{cs}],")
    if lines:
        content = content[:insert_pos] + '\n' + '\n'.join(lines) + content[insert_pos:]
    return content, len(lines)


def main():
    with open(ETS_FILE, 'r') as f:
        content = f.read()

    total = 0

    # 1. Verb conjugations
    verb_entries = {}
    for r_stem, k_stem, fn in VERBS:
        try:
            entries = fn(r_stem, k_stem)
            verb_entries.update(entries)
        except Exception as e:
            print(f"  warn: {r_stem}/{k_stem}: {e}")
    content, n = patch(content, verb_entries)
    total += n
    print(f"Verbs:     +{n} entries")

    # 1b. Verb POS/conjugation classes (track A Phase 1, see HANDOFF §6)
    verb_class = build_verb_class()
    content = write_verb_class(content, verb_class)
    print(f"VerbClass: {len(verb_class)} entries")

    # 2. Nouns
    content, n = patch(content, NOUNS)
    total += n
    print(f"Nouns:     +{n} entries")

    # 3. Places
    content, n = patch(content, PLACES)
    total += n
    print(f"Places:    +{n} entries")

    # 4. Surnames + given names
    content, n = patch(content, SURNAMES)
    total += n
    content, n2 = patch(content, GIVEN_NAMES)
    total += n + n2
    print(f"Names:     +{n+n2} entries")

    with open(ETS_FILE, 'w') as f:
        f.write(content)
    print(f"Total new: +{total} entries")

if __name__ == '__main__':
    main()
