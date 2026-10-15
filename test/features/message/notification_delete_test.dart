import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/notification_list_page.dart';

void main() {
  testWidgets('删除通知按来源调用接口，取消删除保持原通知', (tester) async {
    final deleted = <String>[];
    final interceptor = InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') deleted.add(r.path);
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {
        'code': 0,
        'data': r.method == 'DELETE'
            ? null
            : {
                'list': r.path.endsWith('system-notifications')
                    ? [
                        {
                          'id': 1,
                          'typeText': '预约通知',
                          'title': '测试系统通知',
                          'content': '测试内容',
                          'read': false
                        }
                      ]
                    : [],
                'unreadCount': 0
              }
      }));
    });
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    await tester.pumpWidget(const MaterialApp(home: NotificationListPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除通知'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('测试系统通知'), findsOneWidget);
    await tester.tap(find.byTooltip('删除通知'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleted, ['/api/community/system-notifications/1']);
    expect(find.text('测试系统通知'), findsNothing);
  });
}
