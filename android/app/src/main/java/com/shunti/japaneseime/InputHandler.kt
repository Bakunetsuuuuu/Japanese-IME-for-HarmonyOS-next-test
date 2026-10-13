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
    /** 提案 (種類, 確定する文)。設定「提案を分けて表示する」のとき、候補の帯の上の行に出す */
    var suggestions: List<Pair<Int, String>> = emptyList()
        private set
    private val glyphPaint = android.graphics.Paint()
    private val glyphOk = HashMap<String, Boolean>()
    /** この端末のフォントで出せる字か (豆腐にならないか)。変体仮名は Android 15 から出る端末がある */
    private fun renderable(s: String): Boolean = glyphOk.getOrPut(s) {
        var i = 0
        var ok = true
        while (i < s.length && ok) {
            val cp = s.codePointAt(i)
            if (cp in 0x1B000..0x1B16F || cp in 0x13000..0x1345F || cp in 0x1F000..0x1F0FF) ok = glyphPaint.hasGlyph(String(Character.toChars(cp)))
            i += Character.charCount(cp)
        }
        ok
    }

    private var conversionEnd = 0                  // 0 = 読みの全体を変換。それ以外は先頭からこの字数だけ
    private var ctx = ""                           // 変換の文脈 (入力を始めたときのカーソルの左 + その後に確定した分)
    private val composingUndoStack = ArrayList<String>()
    private val romaji = JapaneseConverter(tables.ROMAJI_TABLE)   // QWERTY でかなを打つとき

    /** まだかなに決まっていないローマ字 (QWERTY) */
    val pendingRomaji get() = romaji.pending()

    private class HostOp(val insert: Boolean, val text: String, val at: Int)
    private val hostUndoStack = ArrayList<HostOp>()

    // ---------------------------------------------------------------- 入力欄の出入り
    /** 数字の入力欄 (電話番号・数値) か。数字はそのまま入れる (変換の候補を出さない) */
    private var numericField = false

    fun onInputStart(ei: EditorInfo?, restarting: Boolean) {
        if (restarting) return
        resetComposition()
        numericField = false
        predictions = emptyList()
        hostUndoStack.clear()
        val cls = (ei?.inputType ?: 0) and EditorInfo.TYPE_MASK_CLASS
        val variation = (ei?.inputType ?: 0) and EditorInfo.TYPE_MASK_VARIATION
        when {
            cls == EditorInfo.TYPE_CLASS_NUMBER || cls == EditorInfo.TYPE_CLASS_PHONE || cls == EditorInfo.TYPE_CLASS_DATETIME -> {
                inputMode = InputMode.ALPHANUMERIC
                subMode = SubMode.NUMERIC
                numericField = true
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

    /**
     * キーボードだけを隠したとき (入力欄は続いている)。Android の標準の処理は入力中の文字をそのまま入力欄に確定するので、
     * その前に見えているとおりに自分で確定して、入力中の状態を空にする。
     * (空にしないと読みが残ったまま、次に打った字を足して入力中に出し直し「かに」+「かにあ」と二重になる)
     */
    fun onViewHidden() {
        if (inputState == InputState.SELECTING) commitTopCandidate()   // 選んでいる候補 (+ 範囲の外の残りのかな) が見えている
        if (inputState == InputState.COMPOSING) commitRaw()
    }

    // ---------------------------------------------------------------- キー
    /** かな・数字のキー (フリックのかなキー、数字パッド) */
    fun handleDirectKana(kana: String) {
        // 英字 (と数字の入力欄の数字) は、入力中の文字があれば足して一緒に変換する (ぱちんこ + CR -> パチンコCR)。
        // 無ければそのまま入れる。数字パッドの数字は入力中の文字として組み立てる (2000 -> 2,000・二千)
        val direct = (inputMode == InputMode.ALPHANUMERIC && subMode != SubMode.NUMERIC) || numericField
        if (direct && composingText.isEmpty()) {
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
            // 入力中の文字があれば英字も足して一緒に変換する (ぱちんこ + CR -> パチンコCR)。無ければそのまま入れる (英文)
            if (composingText.isEmpty()) {
                commitPending()
                insertText(key)
                return
            }
            if (inputState == InputState.SELECTING) commitTopCandidate()
            composingText += key
            inputState = InputState.COMPOSING
            conversionEnd = 0
            updateCandidates()
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
    /** 提案を選んだ: その文で確定する (打ったとおりの変換ではないので学習しない) */
    fun commitSuggestion(index: Int) {
        val text = suggestions.getOrNull(index)?.second ?: return
        val (_, tail) = splitAtConversionEnd(composingText)
        insertText(text)
        ctx += text
        suggestions = emptyList()
        if (tail.isNotEmpty()) {
            continueWithTail(tail)
            return
        }
        resetComposition()
    }

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
        predictions = emailStrip()
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
        suggestions = emptyList()
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
        // 入力中の文字は確定しない (英字・数字も続けて足して一緒に変換する: ぱちんこ + CR、2000 + えん)
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
        // @ を入れた (あっと の変換・記号): 確定の後の帯にメールのドメインの続きを出す (ユーザー 2026-10-13)
        if ('@' in text) {
            val es = emailStrip()
            if (es.isNotEmpty()) { predictions = es; host.render() }
        }
    }

    /** 入力欄のカーソルの前が「…@打ちかけのドメイン」なら、ドメインの続き (gmail.com …) */
    private fun emailStrip(): List<String> {
        val before = host.ic?.getTextBeforeCursor(64, 0)?.toString() ?: return emptyList()
        val m = EMAIL_TAIL.find(before) ?: return emptyList()
        val typed = m.groupValues[1].lowercase()
        return EMAIL_DOMAINS.filter { it.startsWith(typed) && it != typed }.take(6).map { it.substring(typed.length) }
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

    /** 予測 (読みの続きの語・決まり文句) で出した候補。読みが打った分より長いので、打った読みでは学習しない */
    private var completions: Set<String> = emptySet()

    /** 日付・数字の書き換え・絵文字・予測は、その場の値や記号や読みの違う語なので学習しない */
    private fun isNonLearningCandidate(reading: String, text: String): Boolean =
        text in completions ||
            text in DateTimePredictor.predict(reading, Calendar.getInstance()) ||
            text in NumberFormatter.predict(reading) ||
            tables.EMOJI_MAP[reading]?.contains(text) == true ||
            tables.KAOMOJI_MAP[reading]?.contains(text) == true

    fun updateCandidates() {
        if (composingText.isEmpty()) {
            candidates = emptyList()
            suggestions = emptyList()
            showComposing()   // ローマ字の打ちかけだけのとき
            host.render()
            return
        }
        val target = conversionTarget()
        val fullKatakana = toKatakana(target)
        val ai = host.ai
        var cands = ArrayList<String>()
        if (ai != null) {
            ai.liveCommit = settings.liveCommit
            cands.addAll(ai.candidates(ctx, target) { if (conversionTarget() == target) updateCandidates() })
            // 長い入力で前の方が固定されたとき: 既定 (保留) では入力欄に確定しない (固定した部分に候補を持たせ、一覧から選び直せる)。
            // 設定「オート確定」がオンなら、固定した所を入力欄に確定して、残りだけを入力中に残す
            val fk = ai.frozenKana()
            if (ai.liveCommit && fk.isNotEmpty() && !isRangeShrunk()) {
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
        // 括弧は全種類を必ず出す (Brackets.kt)。括弧 1 字を打ったときは同じ側の全種類を先頭から (打った字が 1 位)、
        // かっこ などの読みでは全種類の組を 1 位の後ろに足す
        val brackets = Brackets.variants(target)
        if (brackets.firstOrNull() == target) {
            cands = ArrayList(brackets + cands.filter { it !in brackets })
        } else {
            // 辞書に下の方で入っている組 (（）「」 など) も引き上げる
            for (b in brackets) {
                val at = cands.indexOf(b)
                if (at in 0 until insAt) continue
                if (at >= 0) cands.removeAt(at)
                cands.add(insAt++, b)
            }
        }
        preferGreetings(target, cands)
        // 予測 (HarmonyOS 版と同じ置き方): 決まり文句は先頭に、読みの続く語 (学習した語・辞書の語) は 1 位の直後に 3 つまで
        val comp = LinkedHashSet<String>()
        val phrase = tables.PREDICTIVE_PHRASES.firstOrNull {
            target.length >= it.minPrefix && target.length < it.reading.length && it.reading.startsWith(target)
        }
        if (target.length >= 2 && !isRangeShrunk()) {
            comp.addAll(learning.completions(target, 2))
            ai?.let { comp.addAll(it.complete(target, 4)) }
        }
        val inserted = ArrayList<String>()
        var at = minOf(1, cands.size)
        for (c in comp) {
            if (inserted.size >= 3) break
            if (c in cands || c == phrase?.text) continue
            cands.add(at++, c)
            inserted.add(c)
        }
        if (phrase != null) {
            cands.remove(phrase.text)
            cands.add(0, phrase.text)
        }
        completions = (inserted + listOfNotNull(phrase?.text)).toSet()
        // ユーザー辞書に登録した語は先頭に (HarmonyOS 版 withRegisteredWords と同じ)
        val user = userDict.lookup(target)
        if (user.isNotEmpty()) cands = ArrayList(user + cands.filter { it !in user })
        // メールアドレス: @ の後ろにドメインの候補 (HarmonyOS 版 emailCompletions と同じ。ユーザー 2026-10-13)
        var emailAt = minOf(1, cands.size)
        for (m in emailCompletions(target)) if (m !in cands) cands.add(emailAt++, m)
        // あっと -> 全角の ＠ しか無かった。メールアドレスに使う半角の @ をその前に
        val fwAt = cands.indexOf("＠")
        if (fwAt >= 0 && "@" !in cands) cands.add(fwAt, "@")
        // 絵文字・顔文字は後ろに (HarmonyOS 版の辞書変換と同じ位置)
        for (e in (tables.EMOJI_MAP[target] ?: emptyList()) + (tables.KAOMOJI_MAP[target] ?: emptyList())) {
            if (e !in cands) cands.add(e)
        }
        cands = ArrayList(learning.applyLearnedOrder(target, cands))
        // 提案: 候補に混ぜず分ける (エンジンの提案 + こちらの日付・括弧・絵文字・顔文字)。候補からは外す
        if (settings.separateSuggest && ai != null) {
            val sg = ArrayList(ai.suggestions)
            val dates = DateTimePredictor.predict(target, Calendar.getInstance())
            val moveDates = sg.any { it.first == 2 }
            val symbolic = { c: String -> c.none { it.isLetterOrDigit() } || (tables.EMOJI_MAP[target]?.contains(c) == true) || (tables.KAOMOJI_MAP[target]?.contains(c) == true) }
            val moved = cands.filter { c -> c != target && (sg.any { it.second == c } || (moveDates && c in dates) || (symbolic(c) && target.any { it in 'ぁ'..'ゖ' })) }
            for (c in moved) if (sg.none { it.second == c }) sg.add(7 to c)
            val rest = cands.filter { it !in moved }
            if (rest.isNotEmpty()) cands = ArrayList(rest)
            suggestions = sg.filter { renderable(it.second) }.distinctBy { it.second }.take(12)
        } else {
            suggestions = emptyList()
        }
        // 半角カタカナ (ほかに出す手段が無かった。ユーザー 2026-10-13)。いちばん後ろに
        val half = toHalfKatakana(toKatakana(target))
        if (half != toKatakana(target) && half !in cands) cands.add(half)
        cands = ArrayList(cands.filter { renderable(it) })
        candidates = cands
        if (inputState != InputState.SELECTING) selectedCandidateIndex = 0
        else selectedCandidateIndex = selectedCandidateIndex.coerceAtMost(cands.size - 1)
        showComposing()
        host.render()
    }

    /**
     * 挨拶はかな書きを先に。モデルは「こんにちは」を「今日は」と書きがち (教材の読みの入れ替え「今日 → こんにち」の副作用)。
     * こんにちは は読みのどこにあっても (きょうは も打っていなければ)、こんばんは は読みがそれだけのとき (今晩は寒い があるので)、
     * 1 位の「今日は」「今晩は」をかな書きに直した候補を 1 位に置く (漢字の方も残す)
     */
    private fun preferGreetings(target: String, cands: MutableList<String>) {
        val top = cands.firstOrNull() ?: return
        val rules = listOf(
            Triple("今日は", "こんにちは", "こんにちは" in target && "きょうは" !in target),
            Triple("今晩は", "こんばんは", target.trimEnd('、', '。', '！', '？', '!', '?', 'ー', '〜') == "こんばんは"),
        )
        for ((kanji, kana, ok) in rules) {
            if (!ok || kanji !in top) continue
            val fixed = top.replace(kanji, kana)
            cands.remove(fixed)
            cands.add(0, fixed)
            return
        }
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
        predictions = emailStrip().ifEmpty { strip }
        host.render()
    }

    companion object {
        private val EMAIL_TAIL = Regex("""[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]*)$""")
        private const val MAX_HOST_UNDO = 50
        private val RANGE_BG = Color.argb(0x60, 0x4C, 0x8D, 0xFF)
        private val ALPHA_VARIATIONS = setOf(
            EditorInfo.TYPE_TEXT_VARIATION_PASSWORD, EditorInfo.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            EditorInfo.TYPE_TEXT_VARIATION_WEB_PASSWORD, EditorInfo.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            EditorInfo.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS, EditorInfo.TYPE_TEXT_VARIATION_URI,
        )

        fun toKatakana(s: String) = buildString { for (c in s) append(if (c in 'ぁ'..'ゖ') c + 0x60 else c) }

        private const val HALF_BASE = "ｧｱｨｲｩｳｪｴｫｵｶｶｷｷｸｸｹｹｺｺｻｻｼｼｽｽｾｾｿｿﾀﾀﾁﾁｯﾂﾂﾃﾃﾄﾄﾅﾆﾇﾈﾉﾊﾊﾊﾋﾋﾋﾌﾌﾌﾍﾍﾍﾎﾎﾎﾏﾐﾑﾒﾓｬﾔｭﾕｮﾖﾗﾘﾙﾚﾛﾜﾜｲｴｦﾝｳｶｹ"
        private const val HALF_MARK = "00000000000101010101010101010101010010101000000120120120120120000000000000000000000100"

        /** 全角カタカナ -> 半角カタカナ (HarmonyOS 版 toHalfKatakana と同じ表) */
        fun toHalfKatakana(s: String) = buildString {
            for (c in s) {
                val i = c - 'ァ'
                when {
                    i in HALF_BASE.indices -> { append(HALF_BASE[i]); when (HALF_MARK[i]) { '1' -> append('ﾞ'); '2' -> append('ﾟ') } }
                    c == 'ー' -> append('ｰ')
                    c == '・' -> append('･')
                    else -> append(c)
                }
            }
        }

        /** メールのドメイン。順は教材に「@ドメイン」が書かれた回数の多い順 (HarmonyOS 版 EMAIL_DOMAINS と同じ) */
        private val EMAIL_DOMAINS = listOf("gmail.com", "yahoo.co.jp", "docomo.ne.jp", "i.softbank.jp", "hotmail.com", "ezweb.ne.jp",
            "live.jp", "hotmail.co.jp", "ybb.ne.jp", "softbank.ne.jp", "nifty.com", "me.com", "yahoo.com", "icloud.com", "outlook.jp",
            "outlook.com", "au.com", "rakuten.jp")
        private val EMAIL = Regex("""^([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]*)$""")

        fun emailCompletions(s: String): List<String> {
            val m = EMAIL.matchEntire(s) ?: return emptyList()
            val typed = m.groupValues[2].lowercase()
            return EMAIL_DOMAINS.filter { it.startsWith(typed) && it != typed }.take(5).map { "${m.groupValues[1]}@$it" }
        }
    }
}
