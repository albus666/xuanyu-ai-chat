import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/team_home_page.dart';

void main() {
  for (final failDelete in [false, true]) {
    testWidgets(failDelete ? '资料删除失败保留条目并提示' : '资料删除先确认，成功后立即移除',
        (tester) async {
      var deletes = 0;
      final fake = InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method == 'DELETE') {
          deletes++;
          expect(request.path, '/api/im/team/3/resource/31');
          if (failDelete) {
            handler.reject(DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError));
            return;
          }
        }
        final data = request.path.endsWith('/info')
            ? {'isMember': true, 'canManage': true}
            : request.path.contains('/team/conversation/')
                ? {'teamId': 3, 'isMember': true, 'canManage': true}
                : request.path.endsWith('/resources')
                    ? {
                        'list': [
                          {
                            'id': 31,
                            'title': '回归测试资料',
                            'type': 'text',
                            'content': '测试正文',
                            'visibility': 'members'
                          }
                        ],
                        'hasMore': false
                      }
                    : {'list': [], 'hasMore': false};
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'code': 0, 'data': data}));
      });
      apiClient.interceptors.insert(0, fake);
      addTearDown(() => apiClient.interceptors.remove(fake));
      await tester.pumpWidget(const MaterialApp(
          home: TeamHomePage(conversationId: 88, initialName: '测试部落')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('回归测试资料'), 400);
      final tile = find.ancestor(
          of: find.text('回归测试资料'), matching: find.byType(ExpansionTile));
      Future<void> openDelete() async {
        final menu = find.descendant(
            of: tile, matching: find.byType(PopupMenuButton<String>));
        await tester.ensureVisible(menu);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
      }

      await openDelete();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      expect(find.text('回归测试资料'), findsOneWidget);
      await openDelete();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text('回归测试资料'), failDelete ? findsOneWidget : findsNothing);
      expect(find.text(failDelete ? '删除失败' : '资料已删除'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
