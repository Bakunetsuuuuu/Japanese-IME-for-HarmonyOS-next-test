package com.shunti.japaneseime

/**
 * 括弧の全種類 (開き, 閉じ)。どの括弧も必ず打てるように、変換の候補はここから出す。
 * HarmonyOS 版 ime/Brackets.ets・Windows 版 desktop/core/composer.cpp の BRACKETS も同じ並び (変えるときは 3 つとも)。
 */
object Brackets {
    val ALL = listOf(
        "（" to "）", "(" to ")", "「" to "」", "『" to "』", "【" to "】", "［" to "］", "[" to "]",
        "｛" to "｝", "{" to "}", "〔" to "〕", "〈" to "〉", "《" to "》", "〖" to "〗", "〘" to "〙",
        "〚" to "〛", "｢" to "｣", "＜" to "＞", "<" to ">", "«" to "»", "‹" to "›", "“" to "”",
        "‘" to "’", "〝" to "〟", "｟" to "｠",
    )
    private val OPENS = ALL.map { it.first }
    private val CLOSES = ALL.map { it.second }

    /**
     * 読みに合う括弧の候補。括弧 1 字 → 同じ側 (開き・閉じ) の全種類 (打った字が先頭)、
     * かっこ → 全種類の組、かっこひらき・かっことじ → 開き・閉じの全種類。括弧でない読みは空
     */
    fun variants(reading: String): List<String> = when {
        reading == "かっこ" -> ALL.map { it.first + it.second }
        reading == "かっこひらき" -> OPENS
        reading == "かっことじ" -> CLOSES
        reading in OPENS -> listOf(reading) + OPENS.filter { it != reading }
        reading in CLOSES -> listOf(reading) + CLOSES.filter { it != reading }
        else -> emptyList()
    }
}
