package com.shunti.japaneseime

/**
 * 数字の書き換え (HarmonyOS 版 ime/NumberFormatter.ets の移植。関数名と中身は向こうと同じ)。
 * 読みが数字だけのとき、桁区切り (1,000,000)・万の混ぜ書き (100万)・漢数字 (百万) を候補に足す。
 * 文字列のまま扱うので、大きい数でも桁が落ちない。
 */
object NumberFormatter {
    private val DIGIT_KANJI = listOf("〇", "一", "二", "三", "四", "五", "六", "七", "八", "九")
    private val SMALL_UNITS = listOf("", "十", "百", "千")      // 4 桁の組の中の位
    private val BIG_UNITS = listOf("", "万", "億", "兆", "京")   // 4 桁の組ごと
    private const val MAX_DIGITS = 20

    /** 全角の数字も半角にした数字の列。数字だけでなければ null */
    private fun normalizeDigits(s: String): String? {
        if (s.isEmpty()) return null
        val out = StringBuilder()
        for (c in s) {
            when (c) {
                in '0'..'9' -> out.append(c)
                in '０'..'９' -> out.append('0' + (c - '０'))
                else -> return null
            }
        }
        return out.toString()
    }

    private fun addCommas(digits: String): String {
        val out = StringBuilder()
        val n = digits.length
        for (i in 0 until n) {
            if (i > 0 && (n - i) % 3 == 0) out.append(',')
            out.append(digits[i])
        }
        return out.toString()
    }

    /** 1〜4 桁の組を千百十の漢数字に (千・百・十の前の一は書かない) */
    private fun groupToKanji(group: String): String {
        val g = group.padStart(4, '0')
        val out = StringBuilder()
        for (place in 3 downTo 0) {
            val d = g[3 - place] - '0'
            if (d == 0) continue
            if (d == 1 && place > 0) out.append(SMALL_UNITS[place]) else out.append(DIGIT_KANJI[d]).append(SMALL_UNITS[place])
        }
        return out.toString()
    }

    /** 右から 4 桁ずつ。groups[0] がいちばん下の組 */
    private fun groupsOf(s: String): List<String> {
        val groups = ArrayList<String>()
        var end = s.length
        while (end > 0) {
            groups.add(s.substring(maxOf(0, end - 4), end))
            end -= 4
        }
        return groups
    }

    private fun toKanji(digits: String): String {
        val s = digits.trimStart('0')
        if (s.isEmpty()) return DIGIT_KANJI[0]
        val groups = groupsOf(s)
        val out = StringBuilder()
        for (gi in groups.indices.reversed()) {
            val gk = groupToKanji(groups[gi])
            if (gk.isEmpty()) continue
            out.append(gk).append(BIG_UNITS[gi])
        }
        return out.toString()
    }

    /** 組の中は算用数字、組の間に万・億 (12345678 → 1234万5678。0 の組は飛ばす: 1000000 → 100万) */
    private fun toManMixed(digits: String): String {
        val s = digits.trimStart('0')
        if (s.isEmpty()) return "0"
        if (s.length <= 4) return s
        val groups = groupsOf(s)
        val out = StringBuilder()
        for (gi in groups.indices.reversed()) {
            val grp = groups[gi]
            if (grp.toInt() == 0) continue
            val isHighest = out.isEmpty()
            out.append(if (isHighest) grp.toInt().toString() else grp.padStart(4, '0')).append(BIG_UNITS[gi])
        }
        return out.toString()
    }

    /** 数字だけの読みの書き換えの候補。数字でない・短すぎる・長すぎる・0 で始まる (番号らしい) なら空 */
    fun predict(composing: String): List<String> {
        val digits = normalizeDigits(composing) ?: return emptyList()
        if (digits.length < 4 || digits.length > MAX_DIGITS) return emptyList()
        if (digits[0] == '0') return emptyList()
        val out = ArrayList<String>()
        fun push(s: String) {
            if (s.isNotEmpty() && s != composing && s !in out) out.add(s)
        }
        push(addCommas(digits))
        push(toManMixed(digits))
        push(toKanji(digits))
        return out
    }
}
