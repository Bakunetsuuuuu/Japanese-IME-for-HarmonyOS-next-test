package com.shunti.japaneseime

import java.util.Calendar

/**
 * 日付・時刻の候補 (HarmonyOS 版 ime/DateTimePredictor.ets の移植)。
 * きょう → 今日の日付、いま → 今の時刻、あした → 明日の日付、ことし → 今年 (和暦つき)。
 * 今の時刻は引数で受け取る (中で時計を読まない) ので、結果は引数だけで決まる。
 */
object DateTimePredictor {
    private val DOW = listOf("日", "月", "火", "水", "木", "金", "土")

    private val DAY_OFFSETS = mapOf(
        "きょう" to 0, "ほんじつ" to 0,
        "あした" to 1, "あす" to 1, "みょうにち" to 1,
        "きのう" to -1, "さくじつ" to -1,
        "あさって" to 2, "みょうごにち" to 2,
        "おととい" to -2, "いっさくじつ" to -2,
    )

    private val YEAR_OFFSETS = mapOf(
        "ことし" to 0, "こんねん" to 0,
        "らいねん" to 1, "みょうねん" to 1,
        "きょねん" to -1, "さくねん" to -1,
        "さらいねん" to 2,
    )

    private val TIME_READINGS = setOf("いま", "げんざい", "ただいま")

    /** 令和 (2019-05-01 から) の年。それより前は null */
    private fun wareki(year: Int, month: Int, day: Int): String? {
        if (year > 2019 || (year == 2019 && (month > 5 || (month == 5 && day >= 1)))) {
            val r = year - 2018
            return if (r == 1) "令和元年" else "令和${r}年"
        }
        return null
    }

    private fun dateForms(d: Calendar): List<String> {
        val y = d.get(Calendar.YEAR)
        val m = d.get(Calendar.MONTH) + 1
        val day = d.get(Calendar.DAY_OF_MONTH)
        val dow = DOW[d.get(Calendar.DAY_OF_WEEK) - 1]
        val out = mutableListOf("${y}年${m}月${day}日", "${y}年${m}月${day}日($dow)", "${m}月${day}日", "$y/$m/$day")
        wareki(y, m, day)?.let { out.add("$it${m}月${day}日") }
        return out
    }

    private fun timeForms(d: Calendar): List<String> {
        val h = d.get(Calendar.HOUR_OF_DAY)
        val mm = d.get(Calendar.MINUTE)
        val mm2 = if (mm < 10) "0$mm" else "$mm"
        val ampm = if (h < 12) "午前" else "午後"
        val h12 = if (h % 12 == 0) 12 else h % 12
        return listOf("$h:$mm2", "${h}時${mm}分", "$ampm${h12}時${mm}分")
    }

    /** reading の日付・時刻の候補 (now の時点で)。日付・時刻の読みでなければ空 */
    fun predict(reading: String, now: Calendar): List<String> {
        DAY_OFFSETS[reading]?.let { off ->
            val d = Calendar.getInstance().apply {
                clear()
                set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH))
                add(Calendar.DAY_OF_MONTH, off)
            }
            return dateForms(d)
        }
        YEAR_OFFSETS[reading]?.let { off ->
            val y = now.get(Calendar.YEAR) + off
            val out = mutableListOf("${y}年")
            wareki(y, 6, 15)?.let { out.add(it) }   // 年の半ば: 元号が変わる年でもどちらか決まる
            return out
        }
        if (reading in TIME_READINGS) return timeForms(now)
        return emptyList()
    }
}
