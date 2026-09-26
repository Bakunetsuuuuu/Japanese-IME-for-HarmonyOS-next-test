package com.shunti.japaneseime

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar

/**
 * 移植の答え合わせ: HarmonyOS 版のロジックを Node でそのまま動かした結果 (tools/gen_golden.mjs が作る golden.json) と、
 * Kotlin 版の結果が 1 件も違わないことを確かめる。
 */
class GoldenTest {
    private val golden = JSONObject(javaClass.getResource("/golden.json")!!.readText())

    private fun strings(a: JSONArray) = List(a.length()) { a.getString(it) }

    @Test
    fun numberFormatter() {
        val cases = golden.getJSONArray("numbers")
        for (i in 0 until cases.length()) {
            val c = cases.getJSONArray(i)
            val input = c.getString(0)
            assertEquals("NumberFormatter.predict($input)", strings(c.getJSONArray(1)), NumberFormatter.predict(input))
        }
    }

    @Test
    fun japaneseConverter() {
        // 表は HarmonyOS 版から生成した資産 (テストは android/app で走る)
        val t = JSONObject(java.io.File("src/main/assets/hmos_tables.json").readText()).getJSONObject("ROMAJI_TABLE")
        val table = t.keys().asSequence().associateWith { t.getString(it) }
        val cases = golden.getJSONArray("romaji")
        for (i in 0 until cases.length()) {
            val c = cases.getJSONArray(i)
            val word = c.getString(0)
            val want = c.getJSONArray(1)
            val conv = JapaneseConverter(table)
            for (k in word.indices) {
                val r = conv.processKey(word[k].toString())
                val w = want.getJSONArray(k)
                assertEquals("$word の ${k + 1} 打目", w.getString(0) + "|" + w.getString(1), r.committed + "|" + r.pending)
            }
        }
    }

    @Test
    fun dateTimePredictor() {
        val cases = golden.getJSONArray("dates")
        for (i in 0 until cases.length()) {
            val c = cases.getJSONArray(i)
            val t = c.getJSONArray(0)
            val now = Calendar.getInstance().apply {
                clear()
                set(t.getInt(0), t.getInt(1) - 1, t.getInt(2), t.getInt(3), t.getInt(4))
            }
            val r = c.getString(1)
            assertEquals("DateTimePredictor.predict($r, $t)", strings(c.getJSONArray(2)), DateTimePredictor.predict(r, now))
        }
    }
}
