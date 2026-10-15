import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/community/post_entity_text.dart';

void main() {
  test('解析带空格话题和 Emoji 网名时保留真实 ID', () {
    final segments = parsePostEntitySegments(
      '今天聊 #情绪 修复 和 @小鹿✨ 一起走走',
      topics: const [
        {'id': 12, 'name': '情绪 修复'},
      ],
      mentions: const [
        {'userId': 35, 'nickname': '小鹿✨'},
      ],
    );

    final topic =
        segments.singleWhere((segment) => segment.type == PostEntityType.topic);
    final mention = segments
        .singleWhere((segment) => segment.type == PostEntityType.mention);
    expect(topic.text, '#情绪 修复');
    expect(topic.id, 12);
    expect(mention.text, '@小鹿✨');
    expect(mention.id, 35);
  });

  testWidgets('话题和提及使用不同颜色并可触发对应 ID', (tester) async {
    int? tappedTopicId;
    int? tappedUserId;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PostEntityText(
          content: '看看 #今日心情 和 @星河',
          topics: const [
            {'id': 7, 'name': '今日心情'},
          ],
          mentions: const [
            {'userId': 9, 'nickname': '星河'},
          ],
          onTopicTap: (id, _) => tappedTopicId = id,
          onMentionTap: (id, _) => tappedUserId = id,
        ),
      ),
    ));

    final textWidget = tester.widget<Text>(find.byType(Text));
    final root = textWidget.textSpan! as TextSpan;
    final topic = root.children!
        .whereType<TextSpan>()
        .singleWhere((span) => span.text == '#今日心情');
    final mention = root.children!
        .whereType<TextSpan>()
        .singleWhere((span) => span.text == '@星河');

    expect(topic.style?.color, const Color(0xFF1AC4C4));
    expect(mention.style?.color, const Color(0xFF7B74D6));
    (topic.recognizer as TapGestureRecognizer).onTap!();
    (mention.recognizer as TapGestureRecognizer).onTap!();
    expect(tappedTopicId, 7);
    expect(tappedUserId, 9);
  });
}
