package com.xuanyu.android

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Process
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.text.style.StyleSpan
import android.view.View
import android.view.ViewTreeObserver
import android.widget.Button
import android.widget.TextView
import java.io.IOException
import kotlin.system.exitProcess

/**
 * 启动门禁：在用户点击同意之前不创建 FlutterEngine。
 * Flutter 引擎与 flutter_compass 会在引擎启动/插件注册时读取传感器列表，
 * 因此必须用原生 Activity 承接隐私弹窗。
 */
class PrivacyConsentActivity : Activity() {
    private var launchingFlutter = false
    private var showingDocument = false

    private enum class ConsentDocument(
        val titleRes: Int,
        val assetPath: String,
    ) {
        USER_AGREEMENT(
            R.string.privacy_document_user_agreement,
            "legal/user_agreement.txt",
        ),
        PRIVACY_POLICY(
            R.string.privacy_document_privacy_policy,
            "legal/privacy_policy.txt",
        ),
    }

    private data class ParsedDocument(
        val version: String?,
        val effectiveDate: String?,
        val body: String,
    )

    private enum class LegalLineKind {
        BODY,
        HEADING,
        STRUCTURED,
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        InstallSessionGuard.verify(this)
        if (PrivacyConsentStore.hasValidConsent(this)) {
            showStartupThenLaunchFlutter()
            return
        }
        showConsent()
    }

    private fun showConsent() {
        showingDocument = false
        setContentView(R.layout.activity_privacy_consent)
        bindConsentCopy()
        findViewById<Button>(R.id.privacy_consent_agree).setOnClickListener {
            PrivacyConsentStore.persistConsent(this)
            showStartupThenLaunchFlutter()
        }
        findViewById<Button>(R.id.privacy_consent_disagree).setOnClickListener {
            exitWithoutConsent()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (showingDocument) {
            showConsent()
        } else {
            exitWithoutConsent()
        }
    }

    private fun bindConsentCopy() {
        val bodyView = findViewById<TextView>(R.id.privacy_consent_body)
        val full = getString(R.string.privacy_consent_body)
        val spannable = SpannableString(full)
        linkify(
            spannable,
            getString(R.string.privacy_consent_link_user_agreement),
            ConsentDocument.USER_AGREEMENT,
        )
        linkify(
            spannable,
            getString(R.string.privacy_consent_link_privacy_policy),
            ConsentDocument.PRIVACY_POLICY,
        )
        bodyView.text = spannable
        bodyView.movementMethod = LinkMovementMethod.getInstance()
        bodyView.highlightColor = Color.TRANSPARENT
    }

    private fun linkify(
        spannable: SpannableString,
        label: String,
        document: ConsentDocument,
    ) {
        var from = 0
        while (true) {
            val start = spannable.indexOf(label, from)
            if (start < 0) return
            val end = start + label.length
            spannable.setSpan(object : ClickableSpan() {
                override fun onClick(widget: View) {
                    showDocument(document)
                }

                override fun updateDrawState(ds: TextPaint) {
                    ds.color = 0xFF1AC4C4.toInt()
                    ds.isFakeBoldText = true
                    ds.isUnderlineText = false
                }
            }, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            from = end
        }
    }

    private fun showDocument(document: ConsentDocument) {
        showingDocument = true
        setContentView(R.layout.activity_privacy_document)
        findViewById<View>(R.id.privacy_document_back).setOnClickListener {
            showConsent()
        }
        findViewById<TextView>(R.id.privacy_document_title).setText(document.titleRes)

        try {
            val raw = assets.open(document.assetPath).bufferedReader(Charsets.UTF_8).use {
                it.readText()
            }
            val parsed = parseDocument(raw)
            val metadata = listOfNotNull(
                parsed.version?.let { getString(R.string.privacy_document_version, it) },
                parsed.effectiveDate?.let {
                    getString(R.string.privacy_document_effective_date, it)
                },
            ).joinToString("   ")
            findViewById<TextView>(R.id.privacy_document_meta).apply {
                text = metadata
                visibility = if (metadata.isEmpty()) View.GONE else View.VISIBLE
            }
            val body = SpannableString(parsed.body)
            val clipboardNoticeStart = parsed.body.indexOf("重要提示：剪切板")
            if (clipboardNoticeStart >= 0) {
                val end = parsed.body.indexOf("\n\n", clipboardNoticeStart)
                    .takeIf { it >= 0 } ?: parsed.body.length
                body.setSpan(
                    StyleSpan(Typeface.BOLD), clipboardNoticeStart, end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
            findViewById<TextView>(R.id.privacy_document_body).text = body
        } catch (_: IOException) {
            findViewById<TextView>(R.id.privacy_document_meta).visibility = View.GONE
            findViewById<TextView>(R.id.privacy_document_body)
                .setText(R.string.privacy_document_load_failed)
        }
    }

    /** Restore paragraphs from the hard line breaks in the legal source. */
    private fun parseDocument(raw: String): ParsedDocument {
        val lines = raw
            .replace('\u000C', '\n')
            .lineSequence()
            .map { line -> line.trim() }
            .toList()
        val title = lines.firstOrNull { it.isNotEmpty() }
        val version = lines
            .firstOrNull { it.startsWith(VERSION_PREFIX) }
            ?.removePrefix(VERSION_PREFIX)
            ?.trim()
        val effectiveDate = lines
            .firstOrNull { it.startsWith(EFFECTIVE_DATE_PREFIX) }
            ?.removePrefix(EFFECTIVE_DATE_PREFIX)
            ?.trim()
        val paragraphs = mutableListOf<String>()
        val current = StringBuilder()

        fun flush() {
            if (current.isNotEmpty()) {
                paragraphs += current.toString()
                current.clear()
            }
        }

        for (line in lines) {
            if (
                line.isEmpty() ||
                line == title ||
                line.startsWith(VERSION_PREFIX) ||
                line.startsWith(EFFECTIVE_DATE_PREFIX)
            ) {
                flush()
                continue
            }

            val kind = legalLineKind(line)
            if (kind != LegalLineKind.BODY) flush()
            current.append(line)
            if (
                kind == LegalLineKind.HEADING ||
                line.endsWithAny('。', '！', '？', '；', '：')
            ) {
                flush()
            }
        }
        flush()

        return ParsedDocument(
            version = version,
            effectiveDate = effectiveDate,
            body = paragraphs.joinToString("\n\n"),
        )
    }

    private fun legalLineKind(line: String): LegalLineKind {
        if (
            SECTION_PATTERN.containsMatchIn(line) ||
            SUBSECTION_PATTERN.containsMatchIn(line)
        ) {
            return LegalLineKind.HEADING
        }
        if (
            NUMBERED_ITEM_PATTERN.containsMatchIn(line) ||
            line.startsWith("· ") ||
            line.startsWith("☐") ||
            line == "重要提示" ||
            line.startsWith("重要提示：") ||
            line.startsWith("重要说明：") ||
            line.startsWith("特别说明：") ||
            FIELD_PREFIXES.any { prefix -> line.startsWith(prefix) }
        ) {
            return LegalLineKind.STRUCTURED
        }
        return LegalLineKind.BODY
    }

    private fun String.endsWithAny(vararg characters: Char): Boolean {
        return isNotEmpty() && characters.contains(last())
    }

    /** 先让同款原生启动页真正绘制一帧，再进入 Flutter，避免中间出现白屏。 */
    private fun showStartupThenLaunchFlutter() {
        if (launchingFlutter) return
        launchingFlutter = true
        val startupView = StartupQuoteOverlay.create(this)
        setContentView(startupView)
        startupView.viewTreeObserver.addOnPreDrawListener(
            object : ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    if (startupView.viewTreeObserver.isAlive) {
                        startupView.viewTreeObserver.removeOnPreDrawListener(this)
                    }
                    startupView.post { launchFlutter() }
                    return true
                }
            },
        )
    }

    private fun launchFlutter() {
        val incomingLink = intent?.data
        startActivity(Intent(this, MainActivity::class.java).apply {
            data = incomingLink
            addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION,
            )
        })
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
        finish()
    }

    private fun exitWithoutConsent() {
        finishAffinity()
        Process.killProcess(Process.myPid())
        exitProcess(0)
    }

    companion object {
        private const val VERSION_PREFIX = "版本号："
        private const val EFFECTIVE_DATE_PREFIX = "生效日期："
        private val SECTION_PATTERN = Regex("^\\d+\\.\\s+\\S")
        private val SUBSECTION_PATTERN = Regex("^\\d+(?:\\.\\d+)+\\s+\\S")
        private val NUMBERED_ITEM_PATTERN = Regex("^（[一二三四五六七八九十百]+）")
        private val FIELD_PREFIXES = listOf(
            "个人信息处理者：",
            "个人信息保护负责人邮箱：",
            "儿童个人信息保护专人邮箱：",
            "个人信息权利请求受理渠道：",
            "响应时限：",
            "个人信息种类：",
            "收集目的：",
            "调用权限：",
            "收集频度：",
            "敏感信息必要性：",
            "对用户权益的影响：",
            "处理场景：",
            "单独同意获取方式：",
            "撤回路径：",
            "权限名称：",
            "使用场景：",
            "是否可关闭：",
            "关闭后的影响：",
            "SDK 名称：",
            "SDK名称：",
            "开发者:",
            "目的：",
            "收集信息范围：",
            "SDK隐私政策链接：",
            "提供方公司全称：",
            "使用目的：",
            "处理的个人信息类型：",
            "隐私政策链接：",
            "敏感信息类型：",
        )
    }
}
