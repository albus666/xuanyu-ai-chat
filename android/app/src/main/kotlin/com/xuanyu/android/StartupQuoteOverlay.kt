package com.xuanyu.android

import android.app.Activity
import android.graphics.Outline
import android.view.ViewOutlineProvider
import android.widget.ImageView
import android.view.View
import android.widget.TextView

/** Android 启动阶段使用的寄语页，与 Flutter 首帧共用同一份缓存文案。 */
object StartupQuoteOverlay {
    private const val STARTUP_QUOTE_KEY = "flutter.startup_quote_content_v1"
    private const val MAX_QUOTE_LENGTH = 42

    fun create(activity: Activity): View {
        val view = activity.layoutInflater.inflate(R.layout.view_startup_quote, null)
        val metrics = activity.resources.displayMetrics
        val widthDp = metrics.widthPixels / metrics.density
        val iconSize = ((widthDp * .27f).coerceIn(82f, 104f) * metrics.density).toInt()
        view.findViewById<ImageView>(R.id.startup_quote_icon).apply {
            layoutParams = layoutParams.apply { width = iconSize; height = iconSize }
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, view.width * .24f)
                }
            }
            clipToOutline = true
        }
        val quote = cachedQuote(activity)
        val quoteLength = quote.codePointCount(0, quote.length)
        view.findViewById<TextView>(R.id.startup_quote_text).apply {
            text = quote
            val widthFactor = when {
                quoteLength <= 10 -> .88f
                quoteLength <= 24 -> .84f
                else -> .78f
            }
            layoutParams = layoutParams.apply {
                width = ((widthDp * widthFactor).coerceIn(228f, 350f) * metrics.density).toInt()
            }
            textSize = when {
                quoteLength <= 10 -> 24f
                quoteLength <= 24 -> 22f
                else -> 20f
            }
        }
        return view
    }

    private fun cachedQuote(activity: Activity): String {
        val cached = PrivacyConsentStore.prefs(activity)
            .getString(STARTUP_QUOTE_KEY, null)
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
        if (cached.isNullOrEmpty() ||
            cached.codePointCount(0, cached.length) > MAX_QUOTE_LENGTH
        ) {
            return activity.getString(R.string.startup_quote_default)
        }
        return cached
    }
}
