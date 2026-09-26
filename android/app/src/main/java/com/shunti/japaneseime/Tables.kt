package com.shunti.japaneseime

import android.content.res.AssetManager
import org.json.JSONArray
import org.json.JSONObject

/**
 * HarmonyOS 版の定数の表 (キーの配置・記号・絵文字・色など)。正本は HarmonyOS 版の ArkTS で、
 * tools/gen_hmos_tables.mjs が assets/hmos_tables.json に書き出したものを読む。名前は HarmonyOS 版と同じ。
 */
class Tables private constructor(j: JSONObject) {

    /** フリックのキー 1 つ。[タップ, 左, 上, 右, 下] (無い向きは null)。special は HarmonyOS 版の special の値 */
    class FlickKey(val center: String, val left: String?, val up: String?, val right: String?, val down: String?, val special: String?) {
        /** dir: 0 タップ, 1 左, 2 上, 3 右, 4 下 (無い向きはタップと同じ) */
        fun at(dir: Int): String = when (dir) {
            1 -> left
            2 -> up
            3 -> right
            4 -> down
            else -> null
        } ?: center
    }

    val FLICK_GRID = grid(j.getJSONArray("FLICK_GRID"))
    val ALPHA_GRID = grid(j.getJSONArray("ALPHA_GRID"))
    val NUM_FLICK_GRID = grid(j.getJSONArray("NUM_FLICK_GRID"))
    val SYM_TABS = strings(j.getJSONArray("SYM_TABS"))
    val DEFAULT_RECENT_SYMBOLS = strings(j.getJSONArray("DEFAULT_RECENT_SYMBOLS"))
    val SYMBOL_CATEGORIES = pages(j.getJSONArray("SYMBOL_CATEGORIES"))
    val EMOJI_TABS = strings(j.getJSONArray("EMOJI_TABS"))
    val EMOJI_CATEGORIES = pages(j.getJSONArray("EMOJI_CATEGORIES"))
    val LIGHT_THEME = theme(j.getJSONObject("LIGHT_THEME"))
    val DARK_THEME = theme(j.getJSONObject("DARK_THEME"))
    val EMOJI_FOR_SURFACE = listMap(j.getJSONObject("EMOJI_FOR_SURFACE"))
    val EMOJI_MAP = listMap(j.getJSONObject("EMOJI_MAP"))
    val KAOMOJI_MAP = listMap(j.getJSONObject("KAOMOJI_MAP"))
    val SLURS: Regex? = if (j.has("SLURS")) Regex(j.getString("SLURS")) else null
    val VARIANT_CYCLE: Map<String, String> = j.getJSONObject("VARIANT_CYCLE").let { o -> o.keys().asSequence().associateWith { o.getString(it) } }

    companion object {
        fun load(am: AssetManager): Tables = Tables(JSONObject(am.open("hmos_tables.json").bufferedReader().readText()))

        private fun strings(a: JSONArray) = List(a.length()) { a.getString(it) }
        private fun pages(a: JSONArray) = List(a.length()) { p -> a.getJSONArray(p).let { rows -> List(rows.length()) { strings(rows.getJSONArray(it)) } } }
        private fun listMap(o: JSONObject) = o.keys().asSequence().associateWith { strings(o.getJSONArray(it)) }

        private fun grid(a: JSONArray) = List(a.length()) { r ->
            val row = a.getJSONArray(r)
            List(row.length()) { c ->
                val k = row.getJSONObject(c)
                fun s(n: String) = if (k.has(n)) k.getString(n) else null
                FlickKey(k.getString("center"), s("left"), s("up"), s("right"), s("down"), s("special"))
            }
        }

        /** "#RRGGBB" / "#AARRGGBB" (HarmonyOS の色の書き方) → ARGB */
        private fun theme(o: JSONObject): Map<String, Int> = o.keys().asSequence().associateWith {
            val h = o.getString(it).removePrefix("#")
            (if (h.length == 6) 0xFF000000L or h.toLong(16) else h.toLong(16)).toInt()
        }
    }
}
