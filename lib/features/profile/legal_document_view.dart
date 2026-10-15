import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'legal_document_parser.dart';

class LegalDocumentView extends StatefulWidget {
  const LegalDocumentView({
    super.key,
    required this.rawText,
    required this.fallbackTitle,
    this.footer,
  });

  final String rawText;
  final String fallbackTitle;
  final List<Widget>? footer;

  @override
  State<LegalDocumentView> createState() => _LegalDocumentViewState();
}

class _LegalDocumentViewState extends State<LegalDocumentView> {
  final Map<String, GlobalKey> _headingKeys = {};

  @override
  Widget build(BuildContext context) {
    final parsed = parseLegalDocument(
      widget.rawText,
      fallbackTitle: widget.fallbackTitle,
    );
    for (final heading in parsed.sectionHeadings) {
      _headingKeys.putIfAbsent(heading.text, GlobalKey.new);
    }

    final preamble = <LegalBlock>[];
    final rest = <LegalBlock>[];
    var seenHeading = false;
    for (final block in parsed.blocks) {
      if (!seenHeading &&
          (block.kind == LegalBlockKind.heading ||
              block.kind == LegalBlockKind.subheading)) {
        seenHeading = true;
      }
      if (seenHeading) {
        rest.add(block);
      } else {
        preamble.add(block);
      }
    }

    final children = <Widget>[
      _HeroHeader(document: parsed),
      if (parsed.sectionHeadings.length >= 3) ...[
        const SizedBox(height: 14),
        _SectionIndex(
          headings: parsed.sectionHeadings,
          onTap: _scrollToHeading,
        ),
      ],
      const SizedBox(height: 8),
      ..._buildBody(preamble),
      ..._buildBody(rest),
      if (widget.footer != null) ...widget.footer!,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: children,
    );
  }

  Future<void> _scrollToHeading(String text) async {
    final context = _headingKeys[text]?.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  List<Widget> _buildBody(List<LegalBlock> blocks) {
    final widgets = <Widget>[];
    var index = 0;
    while (index < blocks.length) {
      final block = blocks[index];
      if (block.kind == LegalBlockKind.field) {
        final fields = <LegalBlock>[];
        while (index < blocks.length &&
            blocks[index].kind == LegalBlockKind.field) {
          fields.add(blocks[index]);
          index += 1;
        }
        for (final card in groupFieldCards(fields)) {
          widgets.add(_FieldCard(fields: card));
        }
        continue;
      }
      if (block.kind == LegalBlockKind.bullet) {
        final items = <String>[];
        while (index < blocks.length &&
            blocks[index].kind == LegalBlockKind.bullet) {
          items.add(blocks[index].text.replaceFirst('· ', ''));
          index += 1;
        }
        widgets.add(_BulletList(items: items));
        continue;
      }

      switch (block.kind) {
        case LegalBlockKind.heading:
          widgets.add(_SectionHeading(
            key: _headingKeys[block.text],
            text: block.text,
          ));
        case LegalBlockKind.subheading:
          widgets.add(_Subheading(text: block.text));
        case LegalBlockKind.notice:
          widgets.add(_NoticeCard(text: block.text));
        case LegalBlockKind.item:
          widgets.add(_ItemLine(text: block.text));
        case LegalBlockKind.body:
          widgets.add(_BodyParagraph(text: block.text));
        case LegalBlockKind.field:
        case LegalBlockKind.bullet:
          break;
      }
      index += 1;
    }
    return widgets;
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.document});

  final ParsedLegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FFFF), Colors.white],
        ),
        border: Border.all(color: const Color(0xFFDCECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '法律文件',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(document.title, style: AppTextStyles.titleLarge),
          if (document.version != null || document.effectiveDate != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (document.version != null)
                  _MetaChip(label: '版本 ${document.version}'),
                if (document.effectiveDate != null)
                  _MetaChip(label: '生效 ${document.effectiveDate}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD7E6EA)),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionIndex extends StatelessWidget {
  const _SectionIndex({
    required this.headings,
    required this.onTap,
  });

  final List<LegalBlock> headings;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.communityDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目录',
            style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final heading in headings)
                ActionChip(
                  onPressed: () => onTap(heading.text),
                  backgroundColor: AppColors.primaryLight,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: Text(
                      heading.text.replaceAll(RegExp(r'\s+'), ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(top: 4, right: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Text(
              text.replaceAll(RegExp(r'\s+'), ' '),
              style: AppTextStyles.titleSmall.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text.replaceAll(RegExp(r'\s+'), ' '),
        style: AppTextStyles.titleSmall.copyWith(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    var title = '重要提示';
    var body = text;
    for (final prefix in ['重要提示：', '重要说明：', '特别说明：', '重要提示', '重要说明', '特别说明']) {
      if (text.startsWith(prefix)) {
        title = prefix.endsWith('：') ? prefix.substring(0, prefix.length - 1) : prefix;
        body = text.substring(prefix.length).trim();
        break;
      }
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB8E8E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.primaryDark,
              fontSize: 14,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LinkedText(
              text: body,
              style: AppTextStyles.bodyMedium.copyWith(
                color: const Color(0xFF245B5E),
                fontWeight: text.startsWith('重要提示：剪切板')
                    ? FontWeight.bold
                    : null,
                height: 1.7,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.fields});

  final List<LegalBlock> fields;

  @override
  Widget build(BuildContext context) {
    final titleField = fields.firstWhere(
      (field) => _cardTitleLabels.contains(field.fieldLabel),
      orElse: () => fields.first,
    );
    final showTitle = _cardTitleLabels.contains(titleField.fieldLabel);
    final rows = showTitle
        ? fields.where((field) => field != titleField).toList()
        : fields;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7EEF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Text(
              titleField.fieldValue,
              style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 8),
          ],
          for (final field in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.fieldLabel ?? '',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _LinkedText(
                    text: field.fieldValue,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _cardTitleLabels = {
  'SDK名称',
  'SDK 名称',
  '权限名称',
  '敏感信息类型',
};

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _LinkedText(
                      text: item,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _LinkedText(
        text: text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          height: 1.7,
        ),
      ),
    );
  }
}

class _BodyParagraph extends StatelessWidget {
  const _BodyParagraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LinkedText(
        text: text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          height: 1.78,
          fontSize: 14.5,
        ),
      ),
    );
  }
}

final _linkPattern = RegExp(
  r'(https?://[^\s\u4e00-\u9fff，。；、）】]+|[\w.+-]+@[\w-]+\.[\w.]+)',
);

class _LinkedText extends StatelessWidget {
  const _LinkedText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _linkPattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final value = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => _openLink(value),
            child: Text(
              value,
              style: style.copyWith(
                color: AppColors.primaryDark,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primaryDark,
              ),
            ),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }

  Future<void> _openLink(String value) async {
    final uri = value.contains('@') && !value.startsWith('http')
        ? Uri(scheme: 'mailto', path: value)
        : Uri.parse(value);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
