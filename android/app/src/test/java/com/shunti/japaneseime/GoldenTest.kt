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
