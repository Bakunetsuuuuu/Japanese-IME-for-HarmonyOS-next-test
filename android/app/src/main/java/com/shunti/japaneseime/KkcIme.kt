package com.shunti.japaneseime

import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.Executors

/**
 * shunti IME (Android 版)。入力の決まりは HarmonyOS 版の移植 (InputHandler)、変換は AI 変換 (shuntelligence) だけ。
 * 画面: 上に候補の帯 (入力中は変換の候補、確定の後は絵文字の候補)、下にキーボード (または記号・絵文字の一覧)。
 */
class KkcIme : InputMethodService(), InputHandler.Host {

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    override var ai: AiConverter? = null
        private set

    private lateinit var tables: Tables
    private lateinit var learning: Learning
    private lateinit var recent: RecentSymbols
    private lateinit var input: InputHandler
    private lateinit var settings: Settings
    private lateinit var haptics: Haptics
    private var viewSig = ""   // 画面の作りに効く設定 (色・高さ・ヒント・縦横)。変わったら作り直す

    private var bar: LinearLayout? = null
    private var scroll: HorizontalScrollView? = null
    private var keyboard: KeyboardView? = null
    private var palette: PaletteView? = null
    private var root: LinearLayout? = null
    private var theme: Map<String, Int> = emptyMap()

    override val ic: InputConnection? get() = currentInputConnection
    override val editorInfo: EditorInfo? get() = currentInputEditorInfo

    override fun onCreate() {
        super.onCreate()
        tables = Tables.load(assets)
        learning = Learning.get(this)
        settings = Settings(this)
        haptics = Haptics(this)
        recent = RecentSymbols(getSharedPreferences("shunti", MODE_PRIVATE), tables.DEFAULT_RECENT_SYMBOLS)
        input = InputHandler(this, tables, learning)
        // 辞書とモデルは裏で開く (開くまでは、かなとカタカナだけを出す)
        worker.execute {
            val e = Engine.open(assets, tables.SLURS)
            main.post {
                engine = e
                if (e != null) ai = AiConverter(e, worker, main)
                if (input.composingText.isNotEmpty()) input.updateCandidates()
            }
        }
    }

    override fun onDestroy() {
        learning.save()
        recent.save()
        worker.execute { engine?.close() }
        worker.shutdown()
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        val dp = resources.displayMetrics.density
        viewSig = sig()
        theme = if (settings.isDark(this)) tables.DARK_THEME else tables.LIGHT_THEME
        val kb = KeyboardView(this, input, tables, ::tick).also {
            it.theme = theme
            it.hints = settings.flickHints
        }
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        kb.rowH = (if (landscape) 44 else 56) * dp * settings.heightPercent / 100f
        val pal = PaletteView(this, input, tables, recent, ::tick).also {
            it.theme = theme
            it.totalH = kb.rowH * 4 + 8 * dp
        }
        val b = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val sc = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(b)
        }
        val frame = FrameLayout(this).apply {
            addView(kb)
            addView(pal)
        }
        val r = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(theme.getValue("panelBg"))
            addView(sc, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (44 * dp).toInt()))
            addView(frame)
            // 画面下のナビゲーションバー (ジェスチャーの線・キーボード切替) にキーが重ならないよう、その分だけ下を空ける
            setOnApplyWindowInsetsListener { v, insets ->
                val bottom = if (android.os.Build.VERSION.SDK_INT >= 30) insets.getInsets(android.view.WindowInsets.Type.navigationBars()).bottom
                else @Suppress("DEPRECATION") insets.systemWindowInsetBottom
                v.setPadding(0, 0, 0, bottom)
                insets
            }
        }
        bar = b
        scroll = sc
        keyboard = kb
        palette = pal
        root = r
        render()
        return r
    }

    private fun sig() = "${settings.isDark(this)}/${settings.heightPercent}/${settings.flickHints}/${resources.configuration.orientation}"

    /** キーボードを開くたびに、設定画面で変えた見た目を反映する */
    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (root != null && sig() != viewSig) setInputView(onCreateInputView())
    }

    /** キーに触れた瞬間の振動 (設定でオフにできる) */
    private fun tick() {
        if (settings.haptic) haptics.tick(settings.hapticStrength)
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        input.onInputStart(attribute, restarting)
    }

    override fun onFinishInput() {
        super.onFinishInput()
        input.onInputStop()
        recent.save()
    }

    // ---------------------------------------------------------------- InputHandler.Host
    override fun post(r: () -> Unit) {
        main.post(r)
    }

    override fun render() {
        val b = bar ?: return
        val palMode = input.subMode == InputHandler.SubMode.SYMBOL || input.subMode == InputHandler.SubMode.EMOJI
        keyboard?.visibility = if (palMode) View.INVISIBLE else View.VISIBLE
        palette?.visibility = if (palMode) View.VISIBLE else View.GONE
        keyboard?.invalidate()
        palette?.invalidate()

        val showCands = input.inputState != InputHandler.InputState.IDLE
        val list = if (showCands) input.candidates else input.predictions
        val sel = if (input.inputState == InputHandler.InputState.SELECTING) input.selectedCandidateIndex else -1
        val dp = resources.displayMetrics.density
        b.removeAllViews()
        for ((i, s) in list.withIndex()) {
            val tv = TextView(this).apply {
                text = s
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setTextColor(theme.getValue(if (i == sel) "onAccent" else "textPrimary"))
                if (i == sel) setBackgroundColor(theme.getValue("accent"))
                setPadding((12 * dp).toInt(), 0, (12 * dp).toInt(), 0)
                gravity = Gravity.CENTER_VERTICAL
                setOnClickListener {
                    tick()
                    if (showCands) input.commitCandidate(i) else input.commitPrediction(i)
                }
            }
            b.addView(tv, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, (44 * dp).toInt()))
        }
        // 選んでいる候補が見えるように
        if (sel >= 0) b.post { b.getChildAt(sel)?.let { scroll?.smoothScrollTo(maxOf(0, it.left - (40 * dp).toInt()), 0) } }
        else scroll?.scrollTo(0, 0)
    }
}
