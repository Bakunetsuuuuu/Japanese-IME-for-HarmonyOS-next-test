package com.shunti.japaneseime

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * ユーザー辞書: 読み → 単語。読みがちょうど一致したら、その単語を候補の先頭に出す (HarmonyOS 版と同じく、登録した語は前に)。
 * 端末の中のファイル (filesDir/userdict.json) にだけ保存する。キーボードと設定画面で同じものを使う。
 */
class UserDict private constructor(private val file: File) {
    class Entry(val reading: String, val word: String)

    private val entries = ArrayList<Entry>()

    init {
        runCatching {
            val a = JSONArray(file.readText())
            for (i in 0 until a.length()) {
                val o = a.getJSONObject(i)
                entries.add(Entry(o.getString("r"), o.getString("w")))
            }
        }
    }

    @Synchronized
    fun list(): List<Entry> = entries.toList()

    /** 読み (ひらがな) に登録した単語 (登録した順) */
    @Synchronized
    fun lookup(reading: String): List<String> = entries.filter { it.reading == reading }.map { it.word }

    /** 登録。読みはひらがなにそろえる (カタカナで入れても同じ)。同じ組があれば何もしない */
    @Synchronized
    fun add(reading: String, word: String): Boolean {
        val r = toHiragana(reading.trim())
        val w = word.trim()
        if (r.isEmpty() || w.isEmpty() || entries.any { it.reading == r && it.word == w }) return false
        entries.add(Entry(r, w))
        save()
        return true
    }

    @Synchronized
    fun remove(e: Entry) {
        entries.removeAll { it.reading == e.reading && it.word == e.word }
        save()
    }

    private fun save() {
        val a = JSONArray()
        for (e in entries) a.put(JSONObject().put("r", e.reading).put("w", e.word))
        runCatching {
            val tmp = File(file.path + ".tmp")
            tmp.writeText(a.toString())
            tmp.renameTo(file)
        }
    }

    companion object {
        private var instance: UserDict? = null

        @Synchronized
        fun get(context: Context): UserDict = instance ?: UserDict(File(context.filesDir, "userdict.json")).also { instance = it }

        fun toHiragana(s: String) = buildString { for (c in s) append(if (c in 'ァ'..'ヶ') c - 0x60 else c) }
    }
}
