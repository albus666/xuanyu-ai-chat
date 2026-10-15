import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

const kPostTopicColor = AppColors.primary;
const kPostMentionColor = Color(0xFF7B74D6);

enum PostEntityType { text, topic, mention }

class PostEntitySegment {
  const PostEntitySegment({
    required this.text,
    required this.type,
    this.id,
    this.name,
  });

  final String text;
  final PostEntityType type;
  final int? id;
  final String? name;
}

class _KnownPostEntity {
  const _KnownPostEntity({
    required this.token,
    required this.type,
    required this.id,
    required this.name,
  });

  final String token;
  final PostEntityType type;
  final int id;
  final String name;
}

List<PostEntitySegment> parsePostEntitySegments(
  String content, {
  List<dynamic>? topics,
  List<dynamic>? mentions,
}) {
  if (content.isEmpty) return const [];

  final known = <_KnownPostEntity>[];
  for (final raw in topics ?? const <dynamic>[]) {
    if (raw is! Map) continue;
    final id = (raw['id'] as num?)?.toInt();
    final name = raw['name']?.toString().trim() ?? '';
    if (id == null || name.isEmpty) continue;
    known.add(_KnownPostEntity(
      token: '#$name',
      type: PostEntityType.topic,
      id: id,
      name: name,
    ));
  }
  for (final raw in mentions ?? const <dynamic>[]) {
    if (raw is! Map) continue;
    final id = (raw['userId'] as num?)?.toInt();
    final name = (raw['nickname'] ?? raw['name'])?.toString().trim() ?? '';
    if (id == null || name.isEmpty) continue;
    known.add(_KnownPostEntity(
      token: '@$name',
      type: PostEntityType.mention,
      id: id,
      name: name,
    ));
  }
  known.sort((a, b) => b.token.length.compareTo(a.token.length));

  final segments = <PostEntitySegment>[];
  var plainStart = 0;
  var index = 0;
  while (index < content.length) {
    final marker = content[index];
    if (marker != '#' && marker != '@') {
      index++;
      continue;
    }

    _KnownPostEntity? entity;
    for (final candidate in known) {
      if (candidate.token[0] != marker ||
          !content.startsWith(candidate.token, index)) {
        continue;
      }
      final end = index + candidate.token.length;
      if (end == content.length || _isEntityBoundary(content[end])) {
        entity = candidate;
        break;
      }
    }

    var end = index + 1;
    if (entity != null) {
      end = index + entity.token.length;
    } else {
      while (end < content.length &&
          !_isEntityBoundary(content[end]) &&
          content[end] != '#' &&
          content[end] != '@') {
        end++;
      }
      if (end == index + 1) {
        index++;
        continue;
      }
    }

    if (index > plainStart) {
      segments.add(PostEntitySegment(
        text: content.substring(plainStart, index),
        type: PostEntityType.text,
      ));
    }
    segments.add(PostEntitySegment(
      text: content.substring(index, end),
      type: entity?.type ??
          (marker == '#' ? PostEntityType.topic : PostEntityType.mention),
      id: entity?.id,
      name: entity?.name,
    ));
    index = end;
    plainStart = end;
  }

  if (plainStart < content.length) {
    segments.add(PostEntitySegment(
      text: content.substring(plainStart),
      type: PostEntityType.text,
    ));
  }
  return segments;
}

bool _isEntityBoundary(String value) {
  return RegExp(r'[\s，。！？、；：,.!?;:）)】\]}]').hasMatch(value);
}

class PostEntityText extends StatefulWidget {
  const PostEntityText({
    super.key,
    required this.content,
    this.topics,
    this.mentions,
    this.style,
    this.topicColor = kPostTopicColor,
    this.mentionColor = kPostMentionColor,
    this.maxLines,
    this.overflow,
    this.textAlign = TextAlign.start,
    this.trailing,
    this.onTopicTap,
    this.onMentionTap,
  });

  final String content;
  final List<dynamic>? topics;
  final List<dynamic>? mentions;
  final TextStyle? style;
  final Color topicColor;
  final Color mentionColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign textAlign;
  final InlineSpan? trailing;
  final void Function(int topicId, String topicName)? onTopicTap;
  final void Function(int userId, String nickname)? onMentionTap;

  @override
  State<PostEntityText> createState() => _PostEntityTextState();
}

class _PostEntityTextState extends State<PostEntityText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    final segments = parsePostEntitySegments(
      widget.content,
      topics: widget.topics,
      mentions: widget.mentions,
    );
    for (final segment in segments) {
      final isTopic = segment.type == PostEntityType.topic;
      final isMention = segment.type == PostEntityType.mention;
      GestureRecognizer? recognizer;
      if (isTopic && segment.id != null && widget.onTopicTap != null) {
        final tap = TapGestureRecognizer()
          ..onTap = () => widget.onTopicTap!(segment.id!, segment.name!);
        _recognizers.add(tap);
        recognizer = tap;
      } else if (isMention &&
          segment.id != null &&
          widget.onMentionTap != null) {
        final tap = TapGestureRecognizer()
          ..onTap = () => widget.onMentionTap!(segment.id!, segment.name!);
        _recognizers.add(tap);
        recognizer = tap;
      }
      spans.add(TextSpan(
        text: segment.text,
        recognizer: recognizer,
        style: isTopic
            ? TextStyle(
                color: widget.topicColor,
                fontWeight: FontWeight.w600,
              )
            : isMention
                ? TextStyle(
                    color: widget.mentionColor,
                    fontWeight: FontWeight.w600,
                  )
                : null,
      ));
    }
    if (widget.trailing != null) spans.add(widget.trailing!);

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
    );
  }
}

/// 信息流正文在末行内显示“展开”，避免独占一行破坏阅读节奏。
class ExpandablePostEntityText extends StatefulWidget {
  const ExpandablePostEntityText({
    super.key,
    required this.content,
    this.topics,
    this.mentions,
    required this.style,
    this.maxLines = 4,
    this.mentionColor = kPostMentionColor,
    this.onTopicTap,
    this.onMentionTap,
  });

  final String content;
  final List<dynamic>? topics;
  final List<dynamic>? mentions;
  final TextStyle style;
  final int maxLines;
  final Color mentionColor;
  final void Function(int topicId, String topicName)? onTopicTap;
  final void Function(int userId, String nickname)? onMentionTap;

  @override
  State<ExpandablePostEntityText> createState() =>
      _ExpandablePostEntityTextState();
}

class _ExpandablePostEntityTextState extends State<ExpandablePostEntityText> {
  late final TapGestureRecognizer _toggleRecognizer;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _toggleRecognizer = TapGestureRecognizer()
      ..onTap = () => setState(() => _expanded = !_expanded);
  }

  @override
  void dispose() {
    _toggleRecognizer.dispose();
    super.dispose();
  }

  bool _fits(String text, double width, String suffix) {
    final painter = TextPainter(
      text: TextSpan(text: '$text$suffix', style: widget.style),
      maxLines: widget.maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    return !painter.didExceedMaxLines;
  }

  String _collapsedContent(double width) {
    const suffix = '… 展开';
    if (_fits(widget.content, width, '')) return widget.content;
    final codePoints = widget.content.runes.toList(growable: false);
    var low = 0;
    var high = codePoints.length;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final candidate = String.fromCharCodes(codePoints.take(mid));
      if (_fits(candidate, width, suffix)) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return String.fromCharCodes(codePoints.take(low)).trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsed = _collapsedContent(constraints.maxWidth);
        final canExpand = collapsed != widget.content;
        final shownContent = _expanded ? widget.content : collapsed;
        return PostEntityText(
          content: shownContent,
          topics: widget.topics,
          mentions: widget.mentions,
          style: widget.style,
          mentionColor: widget.mentionColor,
          maxLines: _expanded ? null : widget.maxLines,
          overflow: _expanded ? TextOverflow.clip : TextOverflow.clip,
          onTopicTap: widget.onTopicTap,
          onMentionTap: widget.onMentionTap,
          trailing: canExpand
              ? TextSpan(
                  text: _expanded ? '  收起' : '… 展开',
                  recognizer: _toggleRecognizer,
                  style: const TextStyle(
                    color: AppColors.communityAccent,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
        );
      },
    );
  }
}
