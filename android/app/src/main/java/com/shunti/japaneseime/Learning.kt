package com.shunti.japaneseime

import org.json.JSONObject
import java.io.File

/**
 * 変換の学習 (HarmonyOS 版 KanaKanjiConverter の recordChoice / applyLearnedOrder と同じ決まり)。
 * 読み → {選んだ表記: 回数}。読みは 500 個まで (あふれたら、いちばん使われていない読みを捨てる)、
 * 1 つの読みに表記は 5 個まで。候補の列は、選んだ回数の多い表記を前に寄せる。
 * 端末の中のファイル (filesDir/learned.json) にだけ保存する。
 */
class Learning(private val file: File) {
    private var learned = LinkedHashMap<String, LinkedHashMap<String, Int>>()
    private var dirty = false

    init {
        runCatching {
            val o = JSONObject(file.readText())
            for (r in o.keys()) {
                val e = o.getJSONObject(r)
                learned[r] = LinkedHashMap<String, Int>().apply { for (s in e.keys()) put(s, e.getInt(s)) }
            }
        }
    }

    fun recordChoice(kana: String, candidate: String) {
        if (kana.isEmpty() || candidate.isEmpty() || candidate == kana) return
        val entry = learned[kana] ?: run {
            if (learned.size >= MAX_READINGS) evictWeakestLearnedReading()
            LinkedHashMap<String, Int>().also { learned[kana] = it }
        }
        if (entry.containsKey(candidate) || entry.size < MAX_SURFACES) {
            entry[candidate] = (entry[candidate] ?: 0) + 1
            dirty = true
        }
    }

    /** 候補を消したときなど: その読みでその表記を選んだ記録を消す */
    fun forgetChoice(kana: String, candidate: String) {
        val entry = learned[kana] ?: return
        if (entry.remove(candidate) == null) return
        if (entry.isEmpty()) learned.remove(kana)
        dirty = true
    }

    private fun evictWeakestLearnedReading() {
        val weakest = learned.minByOrNull { (_, e) -> e.values.maxOrNull() ?: 0 }?.key ?: return
        learned.remove(weakest)
    }

    /** 出来上がった候補の列のうち、選んだことのある表記を回数の多い順に前へ (他の並びはそのまま) */
    fun applyLearnedOrder(kana: String, cands: List<String>): List<String> {
        val counts = learned[kana]
        if (counts.isNullOrEmpty()) return cands
        val boosted = cands.filter { (counts[it] ?: 0) > 0 }.sortedByDescending { counts[it] ?: 0 }
        return boosted + cands.filter { (counts[it] ?: 0) == 0 }
    }

    /** 予測: 読みが prefix で始まる、より長い読みで選んだ表記 (選んだ回数の多い順) */
    fun completions(prefix: String, max: Int): List<String> {
        if (prefix.isEmpty()) return emptyList()
        return learned.entries.asSequence()
            .filter { it.key.length > prefix.length && it.key.startsWith(prefix) }
            .flatMap { e -> e.value.entries.map { it.key to it.value } }
            .sortedByDescending { it.second }
            .map { it.first }.distinct().take(max).toList()
    }

    fun clear() {
        learned.clear()
        dirty = true
    }

    /** 変わっていれば保存する (書き込みを減らすため、入力欄を離れたときなどにまとめて) */
    fun save() {
        if (!dirty) return
        dirty = false
        val o = JSONObject()
        for ((r, e) in learned) o.put(r, JSONObject().apply { for ((s, n) in e) put(s, n) })
        runCatching {
            val tmp = File(file.path + ".tmp")
            tmp.writeText(o.toString())
            tmp.renameTo(file)
        }
    }

    companion object {
        private var instance: Learning? = null

        /** キーボードと設定画面で同じものを使う (設定画面で消した学習を、キーボードが古い中身で書き戻さないように) */
        @Synchronized
        fun get(context: android.content.Context): Learning =
            instance ?: Learning(java.io.File(context.filesDir, "learned.json")).also { instance = it }

        private const val MAX_READINGS = 500
        private const val MAX_SURFACES = 5
    }
}
