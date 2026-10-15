import 'package:flutter/material.dart';

import 'post_entity_text.dart';

/// 无图笔记：小红书式「大字封面」——浅底、居中粗字、角标引号与装饰线
class PostTextCoverPreview extends StatelessWidget {
  const PostTextCoverPreview({
    super.key,
    required this.content,
    this.padding = const EdgeInsets.fromLTRB(16, 28, 16, 20),
    this.maxLines = 6,

    /// 缩略图（个人主页网格等）：字与装饰略小
    this.compact = false,
    this.topics,
    this.mentions,
    this.onTopicTap,
    this.onMentionTap,
  });

  final String content;
  final EdgeInsetsGeometry padding;
  final int maxLines;
  final bool compact;
  final List<dynamic>? topics;
  final List<dynamic>? mentions;
  final void Function(int topicId, String topicName)? onTopicTap;
  final void Function(int userId, String nickname)? onMentionTap;

  static const Color _bg = Color(0xFFF2EDE4);
  static const Color _bgBorder = Color(0xFFE8E0D6);
  static const Color _quoteTint = Color(0xFFD4C9BC);
  static const Color _textColor = Color(0xFF2C2C2C);

  @override
  Widget build(BuildContext context) {
    final t = content.trim();
    final display = t.isEmpty ? '分享了一条动态' : t;
    final quoteSize = compact ? 36.0 : 56.0;
    final baseFont = compact ? 15.0 : 30.0;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: _bg,
            border: Border.all(color: _bgBorder, width: 0.5),
          ),
        ),
        Positioned(
          left: compact ? 6 : 10,
          top: compact ? 2 : 4,
          child: Text(
            '\u201C',
            style: TextStyle(
              fontSize: quoteSize,
              fontWeight: FontWeight.w900,
              color: _quoteTint,
              height: 1,
            ),
          ),
        ),
        Positioned(
          right: compact ? 10 : 14,
          bottom: compact ? 8 : 12,
          child: Container(
            width: compact ? 14.0 : 20.0,
            height: 2.5,
            decoration: BoxDecoration(
              color: _quoteTint.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, c) {
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: c.maxWidth, maxHeight: c.maxHeight),
                    child: PostEntityText(
                      content: display,
                      topics: topics,
                      mentions: mentions,
                      onTopicTap: onTopicTap,
                      onMentionTap: onMentionTap,
                      textAlign: TextAlign.center,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: baseFont,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                        height: 1.22,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
