package com.shunti.japaneseime

import android.content.res.AssetManager

/** 変換エンジン (kkc/engine/engine.cpp) の窓口。辞書とモデルは APK の資産をそのままメモリに写して使う。 */
class Engine private constructor(private var handle: Long, private val slurs: Regex?) {

    /** 変換の結果: 候補と、1 位の候補の語の区切り (ends[i] = i 語目の読みの終わり、lens[i] = 表記の長さ) */
    class Result(val cands: List<String>, val ends: IntArray, val lens: IntArray)

    /** 上位の候補。ctx = 確定済みの左の文脈、kana = 読み。times に段階ごとのミリ秒が入る (5 個) */
    fun convert(ctx: String, kana: String, max: Int = 10, model: Boolean = true, times: DoubleArray? = null): List<String> =
        convertWithSegments(ctx, kana, max, model, times).cands

    fun convertWithSegments(ctx: String, kana: String, max: Int = 10, model: Boolean = true, times: DoubleArray? = null): Result {
        if (handle == 0L || kana.isEmpty()) return Result(emptyList(), IntArray(0), IntArray(0))
        val raw = nativeConvert(handle, ctx, kana, max * 2, model, times)
        val seg = nativeSegments(handle)
        val cands = raw.asSequence().filter { slurs == null || !slurs.containsMatchIn(it) }.take(max).toList()
        // 差別語で 1 位が落ちたときは区切りを使わない (区切りは元の 1 位のもの)
        val ok = raw.isNotEmpty() && cands.isNotEmpty() && cands[0] == raw[0]
        val n = if (ok) seg.size / 2 else 0
        return Result(cands, IntArray(n) { seg[2 * it] }, IntArray(n) { seg[2 * it + 1] })
    }

    /**
     * ユーザー辞書の語を変換の網に入れ直す (前の分は消す)。forms は UserDict.engineForms() の、読み・表記と代表語の組。
     * 代表語から品詞とコストを写し、そこから bonus だけ選ばれやすくする。足せた数を返す。convert と同じスレッドで呼ぶ
     */
    fun setUserWords(forms: List<UserDict.Form>, bonus: Int = 800): Int {
        if (handle == 0L) return 0
        nativeUserClear(handle)
        var n = 0
        for (f in forms) n += nativeUserAddLike(handle, f.reading, f.surface, f.tmplReading, f.tmplSurface, bonus)
        return n
    }

    /** 予測: 読みが prefix で始まり、あと maxExtra 字までの辞書の語を、よく使う順に最大 max 個 (辞書を読むだけ。どのスレッドからでもよい) */
    fun complete(prefix: String, max: Int = 3, maxExtra: Int = 6): List<String> =
        if (handle == 0L || prefix.isEmpty()) emptyList() else nativeComplete(handle, prefix, maxExtra, max).toList()

    fun setThreads(n: Int) {
        if (handle != 0L) nativeSetThreads(handle, n)
    }

    fun close() {
        if (handle != 0L) nativeClose(handle)
        handle = 0L
    }

    companion object {
        init {
            System.loadLibrary("kkc")
        }

        /** slurs = 語をつないで差別語になった候補を弾く正規表現 (HarmonyOS 版 AiConverter.SLURS と同じ。Tables から) */
        fun open(am: AssetManager, slurs: Regex?, threads: Int = 4): Engine? {
            val h = nativeOpen(am, threads)
            if (h == 0L) return null
            return Engine(h, slurs)
        }

        @JvmStatic private external fun nativeOpen(am: AssetManager, threads: Int): Long
        @JvmStatic private external fun nativeClose(h: Long)
        @JvmStatic private external fun nativeConvert(h: Long, ctx: String, kana: String, max: Int, model: Boolean, times: DoubleArray?): Array<String>
        @JvmStatic private external fun nativeSetThreads(h: Long, n: Int)
        @JvmStatic private external fun nativeSegments(h: Long): IntArray
        @JvmStatic private external fun nativeUserClear(h: Long)
        @JvmStatic private external fun nativeComplete(h: Long, prefix: String, maxExtra: Int, maxOut: Int): Array<String>
        @JvmStatic private external fun nativeUserAddLike(h: Long, r: String, s: String, tr: String, ts: String, bonus: Int): Int
    }
}
