import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/message/chat_appearance.dart';
import 'package:xuanyu/features/message/chat_page.dart';
import 'package:xuanyu/features/message/chat_search_page.dart';

void main() {
  testWidgets('聊天记录搜索展示日期和图片视频筛选', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChatSearchPage(conversationId: 12)),
    );

    expect(
        find.byKey(const ValueKey('chat-search-date-filter')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('chat-search-media-filter')), findsOneWidget);
    expect(find.text('日期'), findsOneWidget);
    expect(find.text('图片与视频'), findsOneWidget);
  });

  testWidgets('聊天背景选择器提供实际气泡示例', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showChatAppearancePicker(
                context,
                title: '聊天背景',
                current: 'plain',
                type: ChatAppearancePickerType.background,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('清爽浅灰'), findsOneWidget);
    expect(find.text('青雾渐变'), findsOneWidget);
    expect(find.text('星海柔光'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-appearance-background-plain')),
        findsOneWidget);
  });

  test('置顶字段、即时录音和群聊外观入口保持可用', () {
    final singleSettings =
        File('lib/features/message/single_chat_settings_page.dart')
            .readAsStringSync();
    final chatPage =
        File('lib/features/message/chat_page.dart').readAsStringSync();
    final groupSettings =
        File('lib/features/message/chat_info_page.dart').readAsStringSync();
    final postDetail =
        File('lib/features/community/post_detail_page.dart').readAsStringSync();
    final consultationEntry =
        File('lib/features/message/master_consult_entry_page.dart')
            .readAsStringSync();

    expect(singleSettings, contains("_setConversationFlag('pinned', value)"));
    expect(chatPage, contains('onPointerDown: _onRecordPointerDown'));
    expect(chatPage, contains('onPointerUp: _onRecordPointerUp'));
    expect(chatPage, contains('ImagePicker().pickImage'));
    expect(chatPage, contains('正在发送图片'));
    expect(chatPage, isNot(contains('moderationScope')));
    expect(chatPage, isNot(contains('awaitMediaReview')));
    expect(chatPage, contains("pending['sending'] = true"));
    expect(chatPage, contains('Image.file'));
    expect(chatPage, contains('loadingBuilder:'));
    expect(chatPage, contains('Expanded('));
    expect(chatPage, isNot(contains('Icons.alternate_email_rounded')));
    expect(postDetail, isNot(contains("tooltip: '提到用户'")));
    for (final label in const ['复制', '转发', '收藏', '删除', '多选', '引用']) {
      expect(chatPage, contains("'$label'"));
    }
    for (final removed in const ['提醒', '搜一搜', '连续朗读']) {
      expect(chatPage, isNot(contains("'$removed'")));
    }
    expect(chatPage, contains('/messages/forward'));
    expect(chatPage, contains('/messages/favorite'));
    expect(chatPage, contains('/messages/delete'));
    expect(consultationEntry, contains('ConsultationCenterPage'));
    expect(consultationEntry, isNot(contains('AiMasterChatPage')));
    expect(groupSettings, contains("'置顶聊天'"));
    expect(groupSettings, contains("'聊天背景'"));
    expect(groupSettings, contains("'消息气泡'"));
  });

  test('聊天页通过受权 WebSocket 实时接收会话变化', () {
    final chatPage =
        File('lib/features/message/chat_page.dart').readAsStringSync();

    expect(chatPage, contains('/ws/im/conversations/'));
    expect(chatPage, contains("headers: {'Authorization': authorization}"));
    expect(chatPage, contains("decoded['type'] != 'conversation.changed'"));
    expect(chatPage, contains('_scheduleConversationEventsReconnect'));
    expect(chatPage, contains('await _loadMessages()'));
  });

  test('头像缓存标识忽略临时签名但区分不同头像对象', () {
    const first =
        'https://bucket.oss-cn-beijing.aliyuncs.com/avatar/user-8.jpg?Expires=1&Signature=old';
    const renewed =
        'https://bucket.oss-cn-beijing.aliyuncs.com/avatar/user-8.jpg?Expires=2&Signature=new';
    const another =
        'https://bucket.oss-cn-beijing.aliyuncs.com/avatar/user-9.jpg?Expires=2&Signature=new';

    expect(chatAvatarCacheIdentity(first), chatAvatarCacheIdentity(renewed));
    expect(
      chatAvatarCacheIdentity(first),
      isNot(chatAvatarCacheIdentity(another)),
    );
  });

  test('消息刷新保留稳定消息节点和已有头像地址', () {
    final chatPage =
        File('lib/features/message/chat_page.dart').readAsStringSync();

    expect(chatPage, contains('final existingById'));
    expect(chatPage, contains("incoming['avatarUrl'] = previousAvatar"));
    expect(chatPage, contains("ValueKey('chat-message-\$messageKey')"));
    expect(chatPage, isNot(contains('setState(() => _loading = true)')));
  });
}
