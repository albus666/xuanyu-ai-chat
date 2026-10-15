import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_page.dart';

void main() {
  testWidgets('短文字气泡收缩，已读只在自己气泡右下方显示', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'user_id': 1});
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'list': [
                  {
                    'id': 1,
                    'senderId': 1,
                    'nickname': '我',
                    'content': '您好',
                    'type': 'text',
                    'read': true,
                    'createdAt': '2026-09-21T08:00:00',
                  },
                  {
                    'id': 2,
                    'senderId': 1,
                    'nickname': '我',
                    'content': '还没读',
                    'type': 'text',
                    'read': false,
                    'createdAt': '2026-09-21T08:01:00',
                  },
                  {
                    'id': 3,
                    'senderId': 2,
                    'nickname': '对方',
                    'content': '收到',
                    'type': 'text',
                    'read': true,
                    'createdAt': '2026-09-21T08:02:00',
                  },
                  {
                    'id': 4,
                    'senderId': 1,
                    'nickname': '我',
                    'content': '这是一条用于验证长文字正常换行且不会越过屏幕边缘的消息。' * 3,
                    'type': 'text',
                    'read': false,
                    'createdAt': '2026-09-21T08:03:00',
                  },
                ],
              },
            },
          ),
        );
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    await tester.pumpWidget(
      const MaterialApp(home: ChatPage(conversationId: 12, title: '聊天')),
    );
    await tester.pumpAndSettle();
    Finder bubbleFor(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius is BorderRadius &&
            w.constraints?.maxWidth == 390 * .7,
      ),
    );
    for (final text in ['您好', '还没读', '收到']) {
      expect(bubbleFor(text), findsOneWidget);
      expect(tester.getSize(bubbleFor(text)).width, lessThan(130));
    }
    expect(find.text('已读'), findsOneWidget);
    expect(find.text('未读'), findsNothing);
    final receipt = tester.getRect(find.text('已读'));
    final bubble = tester.getRect(bubbleFor('您好'));
    expect(receipt.top, greaterThanOrEqualTo(bubble.bottom));
    expect((receipt.right - bubble.right).abs(), lessThan(4));
    expect(tester.widget<Text>(find.text('已读')).style!.fontSize, 10);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
