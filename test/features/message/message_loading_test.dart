import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/message_page.dart';

void main() {
  late Interceptor fake;
  late List<(RequestOptions, RequestInterceptorHandler)> pending;

  setUp(() {
    pending = [];
    apiClient.options.headers['Authorization'] = 'test-message-session';
    fake = InterceptorsWrapper(
      onRequest: (options, handler) {
        pending.add((options, handler));
      },
    );
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() {
    apiClient.interceptors.remove(fake);
    apiClient.options.headers.remove('Authorization');
  });

  void reply(int index, {String? title, bool fail = false, int unread = 2}) {
    final (options, handler) = pending[index];
    if (fail) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        data: {
          'code': 0,
          'data': {
            'list': [
              if (title != null)
                {
                  'conversationId': 12,
                  'type': 'single',
                  'title': title,
                  'lastMessage': '测试消息',
                },
            ],
            'unreadCount': unread,
          },
        },
      ),
    );
  }

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('五个独立接口并行，会话不等待计数，重复刷新共用在途请求', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MessagePage()));
    await flush(tester);
    expect(
      pending.map((item) => item.$1.path).toSet(),
      containsAll([
        '/api/im/conversations',
        '/api/im/chat/applies',
        '/api/im/group/join-applies',
        '/api/im/group/invites',
        '/api/community/notifications/unread-count',
      ]),
    );
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final pendingRefresh = refresh.onRefresh();
    await flush(tester);
    expect(pending.length, 6); // Five sections plus party presence.
    final conversation = pending.indexWhere(
      (item) => item.$1.path == '/api/im/conversations',
    );
    reply(conversation, title: '优先显示的会话');
    await flush(tester);
    expect(find.text('优先显示的会话'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    for (var i = 0; i < pending.length; i++) {
      if (i != conversation) {
        reply(i, fail: pending[i].$1.path == '/api/im/chat/applies');
      }
    }
    await flush(tester);
    await pendingRefresh;
    expect(find.text('优先显示的会话'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切号立即清空，新账号先返回时旧账号响应不能覆盖', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MessagePage()));
    await flush(tester);
    final oldCount = pending.length;
    apiSessionChanges.value++;
    await flush(tester);
    expect(pending.length, oldCount * 2);
    for (var i = oldCount; i < pending.length; i++) {
      reply(
        i,
        title: pending[i].$1.path == '/api/im/conversations' ? '新账号会话' : null,
      );
    }
    await flush(tester);
    for (var i = 0; i < oldCount; i++) {
      reply(
        i,
        title: pending[i].$1.path == '/api/im/conversations' ? '旧账号会话' : null,
      );
    }
    await flush(tester);
    expect(find.text('新账号会话'), findsOneWidget);
    expect(find.text('旧账号会话'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('删除成功后之前发出的刷新不能恢复会话', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MessagePage()));
    await flush(tester);
    for (var i = 0; i < pending.length; i++) {
      reply(
        i,
        title: pending[i].$1.path == '/api/im/conversations' ? '待删除会话' : null,
      );
    }
    await flush(tester);
    final start = pending.length;
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await flush(tester);
    await tester.longPress(find.text('待删除会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await flush(tester);
    final deletion = pending.indexWhere(
      (item) => item.$1.path.endsWith('/delete'),
    );
    expect(deletion, greaterThanOrEqualTo(0));
    reply(deletion);
    await flush(tester);
    for (var i = start; i < deletion; i++) {
      reply(
        i,
        title: pending[i].$1.path == '/api/im/conversations' ? '待删除会话' : null,
      );
    }
    await flush(tester);
    await refresh;
    expect(find.text('待删除会话'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('消息页每15秒更新预约通知未读数且不重载会话列表', (tester) async {
    var badge = 0;
    await tester.pumpWidget(MaterialApp(
        home: MessagePage(onBadgeChanged: (value) => badge = value)));
    await flush(tester);
    for (var i = 0; i < pending.length; i++) {
      reply(i, unread: 0);
    }
    await flush(tester);
    final previous = pending.length;
    await tester.pump(const Duration(seconds: 15));
    await flush(tester);
    final newRequests =
        pending.skip(previous).map((item) => item.$1.path).toList();
    expect(newRequests, contains('/api/community/notifications/unread-count'));
    expect(newRequests, isNot(contains('/api/im/conversations')));
    for (var i = previous; i < pending.length; i++) {
      reply(i, unread: pending[i].$1.path.endsWith('/unread-count') ? 5 : 0);
    }
    await flush(tester);
    expect(badge, 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
