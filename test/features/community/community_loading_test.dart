import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/community_page.dart';
import 'package:xuanyu/features/community/post_card.dart';

void main() {
  late List<(RequestOptions, RequestInterceptorHandler)> pending;
  late Interceptor interceptor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pending = [];
    interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == '/api/community/feed') {
          pending.add((options, handler));
        } else {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'code': 0,
                'data': {'list': []},
              },
            ),
          );
        }
      },
    );
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() => apiClient.interceptors.remove(interceptor));

  void reply(int index, {int id = 1, int status = 200}) {
    final (options, handler) = pending[index];
    if (status != 200) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: status),
        ),
      );
    } else {
      handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'code': 0,
            'data': {
              'list': [
                {'id': id, 'nickname': '测试作者', 'content': '内容$id'},
              ],
              'hasMore': false,
            },
          },
        ),
      );
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('启动数据在切入社区时复用，刷新和失败期间保留帖子', (tester) async {
    final key = GlobalKey<CommunityPageState>();
    await tester.pumpWidget(MaterialApp(home: CommunityPage(key: key)));
    await settle(tester);
    reply(0);
    await settle(tester);
    expect(find.byType(PostCard), findsOneWidget);
    key.currentState!.refreshIfStale();
    await settle(tester);
    expect(pending.length, 1);

    key.currentState!.refreshFeed();
    await settle(tester);
    expect(find.byType(PostCard), findsOneWidget);
    reply(1, status: 503);
    reply(2);
    reply(3);
    await settle(tester);
    expect(tester.widget<PostCard>(find.byType(PostCard).first).item['id'], 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('刷新响应乱序不能覆盖新内容，权限拒绝立即清空', (tester) async {
    final key = GlobalKey<CommunityPageState>();
    await tester.pumpWidget(MaterialApp(home: CommunityPage(key: key)));
    await settle(tester);
    key.currentState!.refreshFeed();
    await settle(tester);
    reply(1, id: 2);
    reply(2);
    reply(3);
    await settle(tester);
    reply(0, id: 1);
    await settle(tester);
    expect(tester.widget<PostCard>(find.byType(PostCard).first).item['id'], 2);
    key.currentState!.refreshFeed();
    await settle(tester);
    reply(4, status: 403);
    reply(5);
    reply(6);
    await settle(tester);
    expect(find.byType(PostCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关注同城首屏错峰预加载，同一时间只预加载一个列表', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunityPage()));
    await settle(tester);
    expect(pending.length, 1);
    reply(0);
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(pending.length, 2);
    expect(pending[1].$1.queryParameters['tab'], 'following');
    reply(1);
    await settle(tester);
    expect(pending.length, 3);
    expect(pending[2].$1.queryParameters['tab'], 'local');
    reply(2);
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切换账号后旧请求不能把旧帖子放回页面', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunityPage()));
    await settle(tester);
    apiSessionChanges.value++;
    reply(0);
    await settle(tester);
    expect(find.byType(PostCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
