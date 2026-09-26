package com.shunti.japaneseime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs

/**
 * 記号と絵文字の一覧 (HarmonyOS 版の SymbolView / EmojiView)。上に種類のタブ、真ん中に 8 列の一覧 (縦に動かせる)、
 * 下に [あいう, 記号⇔絵文字, ⌫]。記号の最初のタブは最近使った記号。描画も当たり判定も自前。
 */
@SuppressLint("ViewConstructor")
class PaletteView(
    context: Context,
    private val h: InputHandler,
    private val tables: Tables,
    private val recent: RecentSymbols,
    private val haptic: () -> Unit,
) : View(context) {

    var theme: Map<String, Int> = tables.LIGHT_THEME
        set(v) { field = v; invalidate() }
    var totalH = 0f

    private val dp = resources.displayMetrics.density
    private val barH = 40 * dp
    private val bottomH = 44 * dp
    private val cellH = 44 * dp
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val rect = RectF()

    private val emoji get() = h.subMode == InputHandler.SubMode.EMOJI
    private var symTab = 1
    private var emojiTab = 0
    private var scroll = 0f

    private var downX = 0f
    private var downY = 0f
    private var downScroll = 0f
    private var dragging = false

    private fun tabs() = if (emoji) tables.EMOJI_TABS else tables.SYM_TABS
    private fun tab() = if (emoji) emojiTab else symTab

    private fun items(): List<String> = if (!emoji && symTab == 0) recent.list() else
        (if (emoji) tables.EMOJI_CATEGORIES else tables.SYMBOL_CATEGORIES).getOrNull(tab())?.flatten() ?: emptyList()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), totalH.toInt())
    }

    private fun gridTop() = barH
    private fun gridH() = height - barH - bottomH
    private fun maxScroll(): Float = maxOf(0f, ((items().size + 7) / 8) * cellH - gridH())

    override fun onDraw(canvas: Canvas) {
        paint.color = theme.getValue("panelBg")
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        val tw = width / 9f
        // タブ (先頭は戻る)
        for (i in 0 until 9) {
            val s = if (i == 0) "◀" else tabs().getOrNull(i - 1) ?: continue
            if (i > 0 && i - 1 == tab()) {
                paint.color = theme.getValue("accentSoft")
                rect.set(i * tw + 2 * dp, 4 * dp, (i + 1) * tw - 2 * dp, barH - 4 * dp)
                canvas.drawRoundRect(rect, 8 * dp, 8 * dp, paint)
            }
            drawText(canvas, s, i * tw + tw / 2, barH / 2, if (s.length > 2) 11f else 15f)
        }
        // 一覧
        canvas.save()
        canvas.clipRect(0f, gridTop(), width.toFloat(), gridTop() + gridH())
        val cw = width / 8f
        val list = items()
        val first = (scroll / cellH).toInt()
        for (row in first..(first + (gridH() / cellH).toInt() + 1)) for (c in 0 until 8) {
            val s = list.getOrNull(row * 8 + c) ?: continue
            val cy = gridTop() + row * cellH - scroll + cellH / 2
            paint.color = theme.getValue("keyBg")
            rect.set(c * cw + 2 * dp, cy - cellH / 2 + 2 * dp, (c + 1) * cw - 2 * dp, cy + cellH / 2 - 2 * dp)
            canvas.drawRoundRect(rect, 6 * dp, 6 * dp, paint)
            drawText(canvas, s, c * cw + cw / 2, cy, if (s.length > 2 && !emoji) 12f else if (emoji) 22f else 18f)
        }
        canvas.restore()
        // 下の段
        val by = height - bottomH / 2
        val bw = width / 3f
        for ((i, s) in listOf("あいう", if (emoji) "記号" else "☺", "⌫").withIndex()) {
            paint.color = theme.getValue("specialBg")
            rect.set(i * bw + 3 * dp, height - bottomH + 3 * dp, (i + 1) * bw - 3 * dp, height - 3 * dp)
            canvas.drawRoundRect(rect, 8 * dp, 8 * dp, paint)
            drawText(canvas, s, i * bw + bw / 2, by, 15f)
        }
    }

    private fun drawText(canvas: Canvas, s: String, x: Float, y: Float, sp: Float) {
        text.textSize = sp * dp
        text.color = theme.getValue("textPrimary")
        canvas.drawText(s, x, y - (text.descent() + text.ascent()) / 2, text)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x
                downY = e.y
                downScroll = scroll
                dragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (downY in gridTop()..(gridTop() + gridH()) && abs(e.y - downY) > 10 * dp) dragging = true
                if (dragging) {
                    scroll = (downScroll - (e.y - downY)).coerceIn(0f, maxScroll())
                    invalidate()
                }
            }
            MotionEvent.ACTION_UP -> if (!dragging) tap(e.x, e.y)
        }
        return true
    }

    private fun tap(x: Float, y: Float) {
        haptic()
        when {
            y < barH -> {
                val i = (x / (width / 9f)).toInt()
                if (i == 0) {
                    h.subMode = InputHandler.SubMode.KANA
                    h.updateView()
                    return
                }
                if (i - 1 < tabs().size) {
                    if (emoji) emojiTab = i - 1 else symTab = i - 1
                    scroll = 0f
                }
            }
            y > height - bottomH -> when ((x / (width / 3f)).toInt()) {
                0 -> {
                    h.subMode = InputHandler.SubMode.KANA
                    h.updateView()
                    return
                }
                1 -> {
                    h.subMode = if (emoji) InputHandler.SubMode.SYMBOL else InputHandler.SubMode.EMOJI
                    scroll = 0f
                    h.updateView()
                    return
                }
                else -> h.handleBackspace()
            }
            else -> {
                val row = ((y - gridTop() + scroll) / cellH).toInt()
                val c = (x / (width / 8f)).toInt().coerceIn(0, 7)
                val s = items().getOrNull(row * 8 + c) ?: return
                h.insertSymbol(s)
                if (!emoji) recent.use(s)
            }
        }
        invalidate()
    }
}

/** 最近使った記号 (HarmonyOS 版 recordSymbolUse)。使った順に前へ、24 個まで。まだ無ければ既定の並び */
class RecentSymbols(private val prefs: android.content.SharedPreferences, private val defaults: List<String>) {
    private val items = ArrayList(prefs.getString("recentSymbols", null)?.split('\u0001')?.filter { it.isNotEmpty() } ?: emptyList())
    private var dirty = false

    fun list(): List<String> = if (items.isEmpty()) defaults else items

    fun use(s: String) {
        items.remove(s)
        items.add(0, s)
        while (items.size > 24) items.removeAt(items.size - 1)
        dirty = true
    }

    fun save() {
        if (!dirty) return
        dirty = false
        prefs.edit().putString("recentSymbols", items.joinToString("\u0001")).apply()
    }
}
