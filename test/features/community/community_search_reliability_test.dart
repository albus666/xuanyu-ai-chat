import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/community_search_page.dart';
import 'package:xuanyu/features/community/post_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('社区搜索忽略旧关键词迟到结果', (tester) async {
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    Response<dynamic> result(RequestOptions request, int id) => Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'code': 0,
            'data': {
              'list': [
                {
                  'id': id,
                  'userId': 7,
                  'nickname': '测试用户',
                  'content': '结果$id',
                  'mediaUrls': [],
                  'topics': [],
                  'mentions': []
                }
              ]
            }
          },
        );
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.queryParameters['keyword'] == '旧关键词') {
        oldRequest = request;
        oldHandler = handler;
      } else {
        handler.resolve(result(request, 2));
      }
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: CommunitySearchPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    oldHandler!.resolve(result(oldRequest!, 1));
    await tester.pumpAndSettle();
    final cards = tester.widgetList<PostCard>(find.byType(PostCard));
    expect(cards.map((card) => card.item['id']), [2]);
  });

  for (final swipe in [false, true]) {
    testWidgets(swipe ? '滑动到用户标签自动搜索' : '切换标签沿用已提交关键词，不混入尚未提交的输入',
        (tester) async {
      final userKeywords = <String>[];
      final fake = InterceptorsWrapper(onRequest: (request, handler) {
        if (request.path.endsWith('/user/search')) {
          userKeywords.add(request.queryParameters['keyword'] as String);
        }
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {'list': []}
        }));
      });
      apiClient.interceptors.insert(0, fake);
      addTearDown(() => apiClient.interceptors.remove(fake));
      await tester.pumpWidget(const MaterialApp(home: CommunitySearchPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '已提交');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      if (swipe) {
        await tester.drag(find.byType(TabBarView), const Offset(-750, 0));
      } else {
        await tester.enterText(find.byType(TextField), '未提交');
        await tester.tap(find.text('用户'));
      }
      await tester.pumpAndSettle();
      expect(userKeywords, ['已提交']);
    });
  }
}
