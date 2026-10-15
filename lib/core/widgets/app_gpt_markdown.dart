import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 应用内统一 Markdown 渲染：基于 [gpt_markdown]（表格、代码块带复制、LaTeX 等），替代 `flutter_markdown`。
///
/// **重点样式（接近常见 Web / 笔记高亮）**
/// - 行内反引号 `` `术语` ``：琥珀色标签底 + 描边（gpt_markdown 中反引号走高亮管线）。
/// - `==高亮==`：预处理为反引号，与上同款。
/// - **`**加粗**`（默认开启）**：模型最常用；在**非** ` ``` ` 代码块内转为行内高亮，与反引号同款标签样式（否则用户几乎看不到效果）。
/// - **`<br>` / `<br/>`**：转为真实换行（模型混用 HTML 时常出现）。
class AppGptMarkdown extends StatelessWidget {
  const AppGptMarkdown({
    super.key,
    required this.data,
    this.selectionArea = false,
    this.followLinkColor = true,
    this.bodyStyle,
    this.enableEqualsHighlight = true,
    this.enableBoldHighlight = true,
  });

  final String data;
  final bool selectionArea;

  /// 为 true 时链接使用主题色，与正文区分更明显。
  final bool followLinkColor;

  /// 正文基础样式；标题、链接等在其上叠加。
  final TextStyle? bodyStyle;

  /// 是否将 `==重点==` 转为行内高亮（与 `` `...` `` 同款样式）。
  final bool enableEqualsHighlight;

  /// 是否将 `**重点**` 转为同款标签高亮（跳过 ``` 围栏内文本）。
  final bool enableBoldHighlight;

  static void openLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 将 `==内容==` 转为 `` `内容` ``；内含反引号则不改。
  static String _applyEqualsHighlight(String markdown) {
    return markdown.replaceAllMapped(RegExp(r'==([^=\n]+?)=='), (m) {
      final inner = m[1]!;
      if (inner.contains('`')) return m[0]!;
      return '`$inner`';
    });
  }

  /// 将 `**内容**` 转为 `` `内容` ``（与反引号共用 [highlightBuilder]）；内含反引号则不改。
  /// 跳过 `[文本](链接)` 整段，避免破坏 Markdown 链接。
  static String _applyBoldAsHighlight(String markdown) {
    final linkLike = RegExp(r'\[[^\]]*\]\([^\)]*\)');
    return markdown.splitMapJoin(
      linkLike,
      onMatch: (m) => m[0]!,
      onNonMatch: (s) => s.replaceAllMapped(RegExp(r'\*\*([^*]+?)\*\*'), (m) {
        final inner = m[1]!.trim();
        if (inner.isEmpty || inner.contains('`')) return m[0]!;
        return '`$inner`';
      }),
    );
  }

  /// 将 HTML 换行 `<br>` / `<br/>` 转为换行符（模型常混用 HTML 与 Markdown；**不**改 ``` 代码块内文本）。
  static String _applyHtmlLineBreaks(String chunk) {
    return chunk.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  }

  /// 在排除 ```…``` 代码块后的正文里做 HTML 换行、== / ** → 行内高亮预处理。
  static String preprocessVisualEmphasis(
    String markdown, {
    bool equals = true,
    bool bold = true,
  }) {
    if (markdown.isEmpty) return markdown;
    final fence = RegExp(r'```[\s\S]*?```', multiLine: true);
    final buf = StringBuffer();
    var start = 0;
    for (final m in fence.allMatches(markdown)) {
      buf.write(_transformOutsideFences(markdown.substring(start, m.start), equals: equals, bold: bold));
      buf.write(m.group(0));
      start = m.end;
    }
    buf.write(_transformOutsideFences(markdown.substring(start), equals: equals, bold: bold));
    return buf.toString();
  }

  static String _transformOutsideFences(
    String chunk, {
    required bool equals,
    required bool bold,
  }) {
    var s = _applyHtmlLineBreaks(chunk);
    if (equals) s = _applyEqualsHighlight(s);
    if (bold) s = _applyBoldAsHighlight(s);
    return s;
  }

  /// 表格占满可用宽度、列均分并自动换行，避免库默认的横向滚动。
  static Widget _tableNoHorizontalScroll(
    BuildContext context,
    List<CustomTableRow> rows,
    TextStyle textStyle,
    GptMarkdownConfig config,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final n = rows.first.fields.length;
    if (n == 0) return const SizedBox.shrink();

    return Table(
      border: TableBorder.all(
        color: AppColors.divider.withValues(alpha: 0.55),
        width: 0.5,
      ),
      columnWidths: {for (var i = 0; i < n; i++) i: const FlexColumnWidth(1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final row in rows)
          TableRow(
            decoration: row.isHeader
                ? const BoxDecoration(color: AppColors.cardBackground)
                : null,
            children: [
              for (final field in row.fields)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Align(
                    alignment: switch (field.alignment) {
                      TextAlign.center => Alignment.center,
                      TextAlign.right => Alignment.centerRight,
                      _ => Alignment.centerLeft,
                    },
                    child: MdWidget(
                      context,
                      field.data.trim(),
                      false,
                      config: config.copyWith(
                        style: textStyle,
                        textAlign: field.alignment,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final base = bodyStyle ??
        AppTextStyles.bodyMedium.copyWith(height: 1.62, color: AppColors.textPrimary);
    final textColor = base.color ?? AppColors.textPrimary;

    final mdSource = preprocessVisualEmphasis(
      data,
      equals: enableEqualsHighlight,
      bold: enableBoldHighlight,
    );

    final gptTheme = GptMarkdownThemeData(
      brightness: brightness,
      h1: AppTextStyles.titleLarge.copyWith(height: 1.35, color: textColor),
      h2: AppTextStyles.titleMedium.copyWith(height: 1.35, color: textColor),
      h3: AppTextStyles.titleSmall.copyWith(height: 1.35, color: textColor),
      h4: AppTextStyles.titleSmall.copyWith(fontSize: (base.fontSize ?? 15) + 1, color: textColor),
      h5: base.copyWith(fontWeight: FontWeight.w600),
      h6: base.copyWith(fontWeight: FontWeight.w600, fontSize: (base.fontSize ?? 15) - 0.5),
      linkColor: AppColors.primary,
      linkHoverColor: AppColors.primary,
      hrLineColor: AppColors.divider,
      highlightColor: AppColors.accentGold.withValues(alpha: 0.28),
      autoAddDividerLineAfterH1: false,
    );

    Widget md = GptMarkdown(
      mdSource,
      style: base,
      followLinkColor: followLinkColor,
      onLinkTap: (url, _) => openLink(url),
      highlightBuilder: (ctx, highlightedText, style) {
        final fs = style.fontSize ?? base.fontSize ?? 15;
        final merged = base.merge(style).copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFB45309),
              height: 1.35,
              background: null,
              fontSize: fs,
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.goldLight.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(highlightedText, style: merged),
            ),
          ),
        );
      },
      tableBuilder: (ctx, tableRows, textStyle, cfg) =>
          _tableNoHorizontalScroll(ctx, tableRows, textStyle, cfg),
    );
    md = GptMarkdownTheme(gptThemeData: gptTheme, child: md);
    if (selectionArea) {
      md = SelectionArea(child: md);
    }
    return md;
  }
}
