package com.shunti.japaneseime

import android.os.Handler
import java.util.concurrent.ExecutorService

/**
 * AI 変換 (HarmonyOS 版 ime/AiConverter.ets の移植。関数名と決まりは向こうと同じ)。
 * 変換は worker のスレッドで行い、結果は main のスレッドで受け取る。このクラスの状態は main のスレッドだけで触る。
 */
class AiConverter(private val engine: Engine, private val worker: ExecutorService, private val main: Handler) {

    var lastMs = 0.0
        private set

    // ---- 長い入力: 前の方を固定して、後ろだけを変換する ----
    // 1 位の候補の語の区切りのうち、末尾から KEEP 字より前にあって、2 回続けて同じ変換になったところ
    // (または「、」「。」の後ろ) までを固定する。固定した部分は文脈としてモデルに渡すので、後ろの変換の質は落ちない。
    // 固定した読みまで消して戻ったら・確定して文脈が変わったら、固定を解く。
    private var fCtx = ""      // 固定を始めたときの文脈
    private var fKana = ""     // 固定した読み
    private var fSurf = ""     // 固定した表記
    private var prevSegs = HashMap<Int, String>()   // 前回の結果の (区切りの位置 -> そこまでの表記)
    private var lastTarget = ""                     // 最後に出した読みと、その候補 (結果を待つ間の表示に使う)
    private var lastCands: List<String> = emptyList()

    /**
     * 読みの全体 target の候補 (固定した部分を前に付けた文)。変換がまだ届いていなければ、裏で変換を頼み、
     * 前回の候補 + 新しく打ったかな を仮に返す (届いたら onDone で出し直す)
     */
    fun candidates(context: String, target: String, onDone: () -> Unit): List<String> {
        if (fCtx != context || !target.startsWith(fKana)) {
            fCtx = context
            fKana = ""
            fSurf = ""
            prevSegs.clear()
        }
        val tail = target.substring(fKana.length)
        if (tail.isEmpty()) return listOf(fSurf)
        val ctx2 = (context + fSurf).takeLast(40)
        val hit = cache[key(ctx2, tail)]
        if (hit != null && hit.cands.isNotEmpty()) {
            val out = hit.cands.map { fSurf + it }
            lastTarget = target
            lastCands = out
            maybeFreeze(tail, hit)
            return out
        }
        request(ctx2, tail, onDone)
        // 結果が届くまでは、前回の候補に新しく打ったかなをつないで出す (かなに戻ったり、候補の帯が縮んだりしない)
        if (lastTarget.isNotEmpty() && target.startsWith(lastTarget) && lastCands.isNotEmpty()) {
            val extra = target.substring(lastTarget.length)
            return lastCands.map { it + extra }
        }
        return listOf(fSurf + tail)
    }

    /** 固定した読みと表記 (呼ぶ側がこれを入力欄に確定して、残りだけを入力中に残す) */
    fun frozenKana() = fKana
    fun frozenSurf() = fSurf

    /**
     * 固定した部分 (読み fk、表記 fs) を確定したあと。前回の候補も、確定した分だけ前を削って残す
     * (消してしまうと、次の結果が届くまで残りがかなで出てちらつく)
     */
    fun clearFrozen(fk: String = "", fs: String = "") {
        fKana = ""
        fSurf = ""
        prevSegs.clear()
        if (fk.isNotEmpty() && lastTarget.startsWith(fk)) {
            lastTarget = lastTarget.substring(fk.length)
            lastCands = lastCands.filter { it.startsWith(fs) }.map { it.substring(fs.length) }
        } else {
            lastTarget = ""
            lastCands = emptyList()
        }
    }

    private fun maybeFreeze(tail: String, r: Engine.Result) {
        val top = r.cands[0]
        var cum = 0
        var freezeEnd = 0
        var freezeLen = 0
        val segs = HashMap<Int, String>()
        for (i in 0 until r.ends.size - 1) {   // 最後の語は固定しない
            cum += r.lens[i]
            val end = r.ends[i]
            val surf = top.substring(0, minOf(cum, top.length))
            segs[end] = surf
            val punct = "、。！？!?".indexOf(tail[end - 1]) >= 0
            val stable = prevSegs[end] == surf
            if (end <= tail.length - KEEP && (stable || punct)) {
                freezeEnd = end
                freezeLen = cum
            }
        }
        prevSegs = segs
        if (freezeEnd > 0) {
            fKana += tail.substring(0, freezeEnd)
            fSurf += top.substring(0, minOf(freezeLen, top.length))
            prevSegs.clear()
        }
    }

    /** 変換の結果の控えを捨てる (ユーザー辞書が変わって、同じ読みでも結果が変わるとき) */
    fun clearCache() {
        cache.clear()
    }

    // ---- 裏のスレッドでの変換 ----
    private val cache = HashMap<String, Engine.Result>()
    private var inflight = false
    private var wantKey = ""
    private var wantCtx = ""
    private var wantKana = ""
    private var wantCb: () -> Unit = {}

    private fun key(context: String, kana: String) = "$context|$kana"

    /** 変換中にまた頼まれたら、終わったあとで最新の 1 つだけを変換する (古い読みの変換を溜めない) */
    private fun request(context: String, kana: String, onDone: () -> Unit) {
        wantKey = key(context, kana)
        wantCtx = context
        wantKana = kana
        wantCb = onDone
        if (!inflight) run()
    }

    private fun run() {
        inflight = true
        val key = wantKey
        val ctx = wantCtx
        val kana = wantKana
        val cb = wantCb
        worker.execute {
            val t = DoubleArray(5)
            val r = runCatching { engine.convertWithSegments(ctx, kana, 10, true, t) }
                .getOrElse { Engine.Result(emptyList(), IntArray(0), IntArray(0)) }
            main.post {
                lastMs = t.sum()
                if (cache.size > 256) cache.clear()
                cache[key] = r
                inflight = false
                if (wantKey != key) run()      // 変換中に読みが変わった: 最新の読みを変換する
                else cb()
            }
        }
    }

    companion object {
        private const val KEEP = 8
    }
}
