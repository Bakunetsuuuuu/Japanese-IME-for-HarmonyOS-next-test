package com.shunti.japaneseime

import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import java.text.BreakIterator
import java.util.Calendar

/**
 * 入力の状態と操作 (HarmonyOS 版 ime/KeyboardController.ets の InputHandler の、AI 変換で使う部分の移植)。
 * 関数名と状態の決まりは向こうと同じ。向こうとの違い:
 *  - 辞書を使う機能 (ハイブリッド変換・予測変換・文節の編集) は持たない。変換は AI 変換だけ (+ ユーザー辞書)
 *  - 文脈は確定した文のかわりに、入力欄のカーソルの左をそのまま読む (Android では読めるので)
 *  - SELECTING (空白で候補を選んでいる) の間は、選んでいる候補を入力欄に出す
 */
class InputHandler(
    private val host: Host,
    private val tables: Tables,
    private val learning: Learning,
    private val settings: Settings,
    private val userDict: UserDict,
) {

    interface Host {
        val ic: InputConnection?
        val editorInfo: EditorInfo?
        val ai: AiConverter?
        fun render()          // 候補の帯とキーの表示を出し直す
        fun post(r: () -> Unit)   // いまの処理が終わってから r を呼ぶ
    }

    enum class InputState { IDLE, COMPOSING, SELECTING }
    enum class InputMode { HIRAGANA, ALPHANUMERIC }
    enum class SubMode { KANA, NUMERIC, SYMBOL, EMOJI, MENU }

    var inputState = InputState.IDLE
        private set
    var inputMode = InputMode.HIRAGANA
        private set
    var subMode = SubMode.KANA
    var composingText = ""
        private set
    var candidates: List<String> = emptyList()
        private set
    var selectedCandidateIndex = 0
        private set
    var predictions: List<String> = emptyList()   // 確定のあとに出す候補 (絵文字)
        private set

    private var conversionEnd = 0                  // 0 = 読みの全体を変換。それ以外は先頭からこの字数だけ
    private var ctx = ""                           // 変換の文脈 (入力を始めたときのカーソルの左 + その後に確定した分)
    private val composingUndoStack = ArrayList<String>()
    private val romaji = JapaneseConverter(tables.ROMAJI_TABLE)   // QWERTY でかなを打つとき

    /** まだかなに決まっていないローマ字 (QWERTY) */
    val pendingRomaji get() = romaji.pending()

    private class HostOp(val insert: Boolean, val text: String, val at: Int)
    private val hostUndoStack = ArrayList<HostOp>()

    // ---------------------------------------------------------------- 入力欄の出入り
    fun onInputStart(ei: EditorInfo?, restarting: Boolean) {
        if (restarting) return
        resetComposition()
        predictions = emptyList()
        hostUndoStack.clear()
        val cls = (ei?.inputType ?: 0) and EditorInfo.TYPE_MASK_CLASS
        val variation = (ei?.inputType ?: 0) and EditorInfo.TYPE_MASK_VARIATION
        when {
            cls == EditorInfo.TYPE_CLASS_NUMBER || cls == EditorInfo.TYPE_CLASS_PHONE || cls == EditorInfo.TYPE_CLASS_DATETIME -> {
                inputMode = InputMode.ALPHANUMERIC
                subMode = SubMode.NUMERIC
            }
            cls == EditorInfo.TYPE_CLASS_TEXT && variation in ALPHA_VARIATIONS -> {
                inputMode = InputMode.ALPHANUMERIC
                subMode = SubMode.KANA
            }
            else -> {
                inputMode = InputMode.HIRAGANA
                subMode = SubMode.KANA
            }
        }
        host.render()
    }

    fun onInputStop() {
        resetComposition()
        learning.save()
    }

    // ---------------------------------------------------------------- キー
    /** かな・数字のキー (フリックのかなキー、数字パッド) */
    fun handleDirectKana(kana: String) {
        if (inputMode == InputMode.ALPHANUMERIC && subMode != SubMode.NUMERIC) {
            commitPending()
            insertText(kana)
            return
        }
        if (inputState == InputState.SELECTING) commitTopCandidate()
        beginIfIdle()
        composingText += romaji.flushPending() + kana
        inputState = InputState.COMPOSING
        conversionEnd = 0
        updateCandidates()
    }

    /** 入力を始めるとき: 文脈 (カーソルの左) を読み、確定の後の帯を消す */
    private fun beginIfIdle() {
        if (composingText.isEmpty() && romaji.pending().isEmpty()) {
            ctx = host.ic?.getTextBeforeCursor(40, 0)?.toString() ?: ""
            predictions = emptyList()
        }
    }

    /**
     * QWERTY のキー。英数モードでは打った字をそのまま入れる。かなモードではローマ字をかなにする
     * (HarmonyOS 版 handleKeyPress と同じ: かなに決まった分を読みに足し、決まらない分は pendingRomaji に残す)
     */
    fun handleKeyPress(key: String) {
        if (inputMode == InputMode.ALPHANUMERIC) {
            commitPending()
            insertText(key)
            return
        }
        if (inputState == InputState.SELECTING) commitTopCandidate()
        beginIfIdle()
        val r = romaji.processKey(key)
        composingText += r.committed
        inputState = if (composingText.isNotEmpty() || r.pending.isNotEmpty()) InputState.COMPOSING else InputState.IDLE
        conversionEnd = 0
        updateCandidates()
    }

    /** 打ちかけのローマ字を読みに足す (n → ん にはならず、そのまま) */
    private fun flushRomaji(): Boolean {
        val p = romaji.flushPending()
        if (p.isEmpty()) return false
        composingText += p
        return true
    }

    /** 小゛゜ キー: 最後の 1 文字を順に切り替える */
    fun handleVariantCycle() {
        if (inputState != InputState.COMPOSING || composingText.isEmpty()) return
        val next = tables.VARIANT_CYCLE[composingText.takeLast(1)] ?: return
        composingText = composingText.dropLast(1) + next
        updateCandidates()
    }

    fun handleSpaceKey() {
        if (inputState == InputState.COMPOSING && flushRomaji()) updateCandidates()
        if (inputState == InputState.IDLE || composingText.isEmpty()) {
            insertText(if (inputMode == InputMode.ALPHANUMERIC) " " else "　")
            return
        }
        if (inputState == InputState.COMPOSING) {
            if (candidates.isEmpty()) return
            inputState = InputState.SELECTING
            selectedCandidateIndex = 0
        } else {
            selectedCandidateIndex = (selectedCandidateIndex + 1) % maxOf(1, candidates.size)
        }
        showComposing()
        host.render()
    }

    fun handleBackspace() {
        when (inputState) {
            InputState.IDLE -> deleteBeforeCursor()
            InputState.SELECTING -> {
                inputState = InputState.COMPOSING
                showComposing()
                host.render()
            }
            InputState.COMPOSING -> {
                if (romaji.pending().isNotEmpty()) {
                    romaji.backspace()
                } else if (composingText.isNotEmpty()) {
                    composingUndoStack.add(composingText.takeLast(1))
                    composingText = composingText.dropLast(1)
                }
                if (conversionEnd > composingText.length) conversionEnd = 0
                if (composingText.isEmpty() && romaji.pending().isEmpty()) {
                    inputState = InputState.IDLE
                    host.ic?.setComposingText("", 1)
                    host.ic?.finishComposingText()
                    candidates = emptyList()
                    host.render()
                    return
                }
                updateCandidates()
            }
        }
    }

    fun handleEnterKey() {
        when (inputState) {
            InputState.SELECTING -> commitTopCandidate()
            InputState.COMPOSING -> commitRaw()
            InputState.IDLE -> {
                val ic = host.ic ?: return
                val ei = host.editorInfo
                val action = (ei?.imeOptions ?: 0) and EditorInfo.IME_MASK_ACTION
                val noAction = ((ei?.imeOptions ?: 0) and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0
                if (!noAction && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED) {
                    ic.performEditorAction(action)
                } else {
                    ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                    ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                }
                predictions = emptyList()
                host.render()
            }
        }
    }

    /** 確定キーの表示 (入力中は「確定」、そうでなければ入力欄の指定に合わせる) */
    fun enterLabel(): String {
        if (inputState != InputState.IDLE) return "確定"
        val ei = host.editorInfo
        if (((ei?.imeOptions ?: 0) and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0) return "改行"
        return when ((ei?.imeOptions ?: 0) and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_SEND -> "送信"
            EditorInfo.IME_ACTION_SEARCH -> "検索"
            EditorInfo.IME_ACTION_GO -> "移動"
            EditorInfo.IME_ACTION_NEXT -> "次へ"
            EditorInfo.IME_ACTION_DONE -> "完了"
            else -> "改行"
        }
    }

    /** かなのまま確定 */
    fun commitRaw() {
        flushRomaji()
        if (composingText.isNotEmpty()) insertText(composingText)
        resetComposition()
    }

    /** 候補の帯をタップ */
    fun commitCandidate(index: Int) {
        val text = candidates.getOrNull(index)
        if (text.isNullOrEmpty()) {
            resetComposition()
            return
        }
        commitChosen(text)
    }

    /** いま選んでいる候補で確定 (候補が無ければかなのまま) */
    fun commitTopCandidate() {
        val text = candidates.getOrNull(selectedCandidateIndex)
        if (text.isNullOrEmpty()) {
            commitPending()
            return
        }
        commitChosen(text)
    }

    private fun commitChosen(text: String) {
        val (reading, tail) = splitAtConversionEnd(composingText)
        if (!isNonLearningCandidate(reading, text)) learning.recordChoice(reading, text)
        insertText(text)
        ctx += text
        if (tail.isNotEmpty()) {
            continueWithTail(tail)
            return
        }
        resetComposition()
        pushPredictions(text)
    }

    private fun commitPending() {
        flushRomaji()
        if (composingText.isNotEmpty()) insertText(composingText)
        resetComposition()
    }

    /** 確定の後の帯の候補をタップ */
    fun commitPrediction(index: Int) {
        val text = predictions.getOrNull(index) ?: return
        insertText(text)
        predictions = emptyList()
        host.render()
    }

    /** 変換範囲を縮めて確定したときの残りを、続けて変換できる状態にする */
    private fun continueWithTail(tail: String) {
        composingUndoStack.clear()
        composingText = tail
        conversionEnd = 0
        inputState = InputState.COMPOSING
        selectedCandidateIndex = 0
        updateCandidates()
    }

    /** AI 変換で固定された前の方 (読み fk -> 表記 fs) を確定し、残りのかなを入力中に残す */
    private fun autoCommitFrozen(target: String, fk: String, fs: String) {
        // 速く打つと、ここに来るまでに入力がもう進んでいる。固定した読みが頭に残っていれば確定してよい
        if (fk.isEmpty() || !composingText.startsWith(fk) || !target.startsWith(fk) || isRangeShrunk()) return
        if (inputState != InputState.COMPOSING) return
        insertText(fs)
        ctx += fs
        host.ai?.clearFrozen(fk, fs)
        continueWithTail(composingText.substring(fk.length))
    }

    private fun resetComposition() {
        romaji.reset()
        if (composingText.isNotEmpty() || inputState != InputState.IDLE) {
            host.ic?.setComposingText("", 1)
            host.ic?.finishComposingText()
        }
        composingUndoStack.clear()
        composingText = ""
        conversionEnd = 0
        candidates = emptyList()
        selectedCandidateIndex = 0
        inputState = InputState.IDLE
        host.render()
    }

    fun handleCursorLeft() {
        if (inputState != InputState.IDLE && composingText.isNotEmpty()) {
            if (conversionEnd == 0) conversionEnd = composingText.length
            if (conversionEnd > 1) {
                conversionEnd--
                updateCandidates()
            }
        } else {
            moveCursor(KeyEvent.KEYCODE_DPAD_LEFT)
        }
    }

    fun handleCursorRight() {
        if (inputState != InputState.IDLE && composingText.isNotEmpty()) {
            if (conversionEnd > 0 && conversionEnd < composingText.length) {
                conversionEnd++
                if (conversionEnd == composingText.length) conversionEnd = 0
                updateCandidates()
            }
        } else {
            moveCursor(KeyEvent.KEYCODE_DPAD_RIGHT)
        }
    }

    /** あA キー: 日本語 → 英字 (→ 数字パッド。設定でオンのとき) → 日本語 (HarmonyOS 版 cycleInputMode と同じ) */
    fun cycleInputMode() {
        commitTopCandidate()
        when {
            subMode == SubMode.NUMERIC -> {
                inputMode = InputMode.HIRAGANA
                subMode = SubMode.KANA
            }
            inputMode == InputMode.ALPHANUMERIC -> {
                if (settings.numericPad) subMode = SubMode.NUMERIC
                else inputMode = InputMode.HIRAGANA
            }
            else -> inputMode = InputMode.ALPHANUMERIC
        }
        host.render()
    }

    /** 表示だけ出し直す (キーボードの種類を変えたときなど) */
    fun updateView() = host.render()

    /** 記号・絵文字の帯からの入力 */
    fun insertSymbol(sym: String) {
        commitTopCandidate()
        insertText(sym)
    }

    // ---------------------------------------------------------------- 取消
    /**
     * 取消キー。入力中ならその場で 1 文字ずつ戻す。確定済みなら、入力欄への直前の操作 (入れた・消した) を
     * 起きた位置まで戻って取り消す (本当の元に戻すと同じ順序で遡る)
     */
    fun undoLastDeletion() {
        if (inputState != InputState.IDLE) {
            val ch = composingUndoStack.removeLastOrNull() ?: return
            handleDirectKana(ch)
            return
        }
        val op = hostUndoStack.removeLastOrNull() ?: return
        val ic = host.ic ?: return
        ic.beginBatchEdit()
        if (op.insert) {
            // 入れた字の直後へ動いて、その字が本当にそこにあるときだけ消す
            ic.setSelection(op.at + op.text.length, op.at + op.text.length)
            if (ic.getTextBeforeCursor(op.text.length, 0)?.toString() == op.text) ic.deleteSurroundingText(op.text.length, 0)
        } else {
            ic.setSelection(op.at, op.at)
            ic.commitText(op.text, 1)
        }
        ic.endBatchEdit()
    }

    // ---------------------------------------------------------------- 入力欄への出力
    /** 入力欄に文字を確定する (出口はここ 1 箇所。取消のための記録もここ) */
    fun insertText(text: String) {
        val ic = host.ic ?: return
        ic.commitText(text, 1)
        cursor()?.let { pushHostOp(true, text, it - text.length) }
    }

    private fun deleteBeforeCursor() {
        val ic = host.ic ?: return
        val sel = ic.getSelectedText(0)
        if (!sel.isNullOrEmpty()) {
            val at = cursor()
            ic.commitText("", 1)
            at?.let { pushHostOp(false, sel.toString(), it) }
            return
        }
        // 最後の 1 文字 (絵文字の合成列なども 1 文字として) を消す
        val before = ic.getTextBeforeCursor(16, 0)?.toString() ?: ""
        if (before.isEmpty()) {
            // 読めない入力欄 (や先頭): キーを送って入力欄に任せる
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
            return
        }
        val bi = BreakIterator.getCharacterInstance()
        bi.setText(before)
        val start = bi.preceding(before.length).coerceAtLeast(0)
        val ch = before.substring(start)
        val at = cursor()
        ic.deleteSurroundingText(ch.length, 0)
        at?.let { pushHostOp(false, ch, it - ch.length) }
        predictions = emptyList()
        host.render()
    }

    private fun pushHostOp(insert: Boolean, text: String, at: Int) {
        if (text.isEmpty() || at < 0) return
        hostUndoStack.add(HostOp(insert, text, at))
        if (hostUndoStack.size > MAX_HOST_UNDO) hostUndoStack.removeAt(0)
    }

    /** 入力欄のカーソルの位置 (読めなければ null) */
    private fun cursor(): Int? {
        val et = host.ic?.getExtractedText(ExtractedTextRequest().apply { hintMaxChars = 0 }, 0) ?: return null
        if (et.selectionStart < 0) return null
        return et.startOffset + et.selectionStart
    }

    private fun moveCursor(code: Int) {
        val ic = host.ic ?: return
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    /** 入力中の文字列を入力欄に出す: 読み (変換範囲を縮めていればその部分に色) か、選んでいる候補 + 残りのかな */
    private fun showComposing() {
        val ic = host.ic ?: return
        if (inputState == InputState.SELECTING) {
            val (_, tail) = splitAtConversionEnd(composingText)
            ic.setComposingText((candidates.getOrNull(selectedCandidateIndex) ?: "") + tail, 1)
            return
        }
        val shown = composingText + romaji.pending()   // 打ちかけのローマ字も後ろに出す
        if (isRangeShrunk()) {
            val s = SpannableString(shown)
            s.setSpan(BackgroundColorSpan(RANGE_BG), 0, conversionEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            ic.setComposingText(s, 1)
        } else {
            ic.setComposingText(shown, 1)
        }
    }

    // ---------------------------------------------------------------- 候補
    private fun isRangeShrunk() = conversionEnd in 1 until composingText.length

    private fun splitAtConversionEnd(composing: String): Pair<String, String> {
        val end = if (isRangeShrunk()) conversionEnd else composing.length
        return composing.substring(0, end) to composing.substring(end)
    }

    private fun conversionTarget() = splitAtConversionEnd(composingText).first

    /** 日付・数字の書き換え・絵文字は、その場の値や記号なので学習しない */
    private fun isNonLearningCandidate(reading: String, text: String): Boolean =
        text in DateTimePredictor.predict(reading, Calendar.getInstance()) ||
            text in NumberFormatter.predict(reading) ||
            tables.EMOJI_MAP[reading]?.contains(text) == true ||
            tables.KAOMOJI_MAP[reading]?.contains(text) == true

    fun updateCandidates() {
        if (composingText.isEmpty()) {
            candidates = emptyList()
            showComposing()   // ローマ字の打ちかけだけのとき
            host.render()
            return
        }
        val target = conversionTarget()
        val fullKatakana = toKatakana(target)
        val ai = host.ai
        var cands = ArrayList<String>()
        if (ai != null) {
            cands.addAll(ai.candidates(ctx, target) { if (conversionTarget() == target) updateCandidates() })
            // 前の方が固定されたら、それを入力欄に確定して、残りだけを入力中に残す (長い入力でも変換中の文字列を短く保つ)
            val fk = ai.frozenKana()
            if (fk.isNotEmpty() && !isRangeShrunk()) {
                val fs = ai.frozenSurf()
                host.post { autoCommitFrozen(target, fk, fs) }
            }
        }
        if (fullKatakana !in cands) cands.add(fullKatakana)
        if (target !in cands) cands.add(target)
        // 日付・時刻と数字の書き換えは 1 位のすぐ後ろに
        var insAt = if (cands.isNotEmpty()) 1 else 0
        for (d in DateTimePredictor.predict(target, Calendar.getInstance()) + NumberFormatter.predict(target)) {
            if (d !in cands) cands.add(insAt++, d)
        }
        // ユーザー辞書に登録した語は先頭に (HarmonyOS 版 withRegisteredWords と同じ)
        val user = userDict.lookup(target)
        if (user.isNotEmpty()) cands = ArrayList(user + cands.filter { it !in user })
        // 絵文字・顔文字は後ろに (HarmonyOS 版の辞書変換と同じ位置)
        for (e in (tables.EMOJI_MAP[target] ?: emptyList()) + (tables.KAOMOJI_MAP[target] ?: emptyList())) {
            if (e !in cands) cands.add(e)
        }
        cands = ArrayList(learning.applyLearnedOrder(target, cands))
        candidates = cands
        if (inputState != InputState.SELECTING) selectedCandidateIndex = 0
        else selectedCandidateIndex = selectedCandidateIndex.coerceAtMost(cands.size - 1)
        showComposing()
        host.render()
    }

    /**
     * 確定の後の帯: 確定した文の終わりの語に決まった絵文字があれば出す (HarmonyOS 版 EmojiSuggest)。
     * 向こうは確定した語で引くが、AI 変換は文ごと確定するので、文の末尾のいちばん長い一致で引く
     */
    private fun pushPredictions(text: String) {
        val strip = ArrayList<String>()
        for (i in text.indices) {
            val e = tables.EMOJI_FOR_SURFACE[text.substring(i)] ?: continue
            for (x in e) if (x !in strip && strip.size < 6) strip.add(x)
            break
        }
        predictions = strip
        host.render()
    }

    companion object {
        private const val MAX_HOST_UNDO = 50
        private val RANGE_BG = Color.argb(0x60, 0x4C, 0x8D, 0xFF)
        private val ALPHA_VARIATIONS = setOf(
            EditorInfo.TYPE_TEXT_VARIATION_PASSWORD, EditorInfo.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            EditorInfo.TYPE_TEXT_VARIATION_WEB_PASSWORD, EditorInfo.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            EditorInfo.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS, EditorInfo.TYPE_TEXT_VARIATION_URI,
        )

        fun toKatakana(s: String) = buildString { for (c in s) append(if (c in 'ぁ'..'ゖ') c + 0x60 else c) }
    }
}
