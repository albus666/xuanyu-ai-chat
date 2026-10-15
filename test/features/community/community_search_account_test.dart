import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/community_search_page.dart';

void main() {
  late InterceptorsWrapper fake;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];
  void reply(RequestOptions r, RequestInterceptorHandler h, Object data) =>
      h.resolve(Response(requestOptions: r, statusCode: 200, data: data));
  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    setupApiClientToken('search-test-a');
    calls.clear();
    respond = (r, h) => reply(r, h, {
          'code': 0,
          'data': {'list': [], 'hasMore': false}
        });
    fake = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      respond(r, h);
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() {
    apiClient.interceptors.remove(fake);
    setupApiClientToken(null);
  });

  Future<void> search(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('历史按账号保存且切号立即清空旧结果', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('community_search_history_v1', ['旧公共记录']);
    await tester.pumpWidget(const MaterialApp(home: CommunitySearchPage()));
    await tester.pumpAndSettle();
    expect(find.text('旧公共记录'), findsNothing);
    await search(tester, '账号甲关键词');
    expect(
        prefs.getStringList('community_search_history_v1_user_77'), ['账号甲关键词']);
    await prefs.setInt(AppConstants.keyUserId, 88);
    setupApiClientToken('search-test-b');
    await tester.pumpAndSettle();
    expect(find.text('账号甲关键词'), findsNothing);
    expect(find.text('暂无历史记录'), findsOneWidget);
    await search(tester, '账号乙关键词');
    expect(
        prefs.getStringList('community_search_history_v1_user_88'), ['账号乙关键词']);
    await prefs.setInt(AppConstants.keyUserId, 77);
    setupApiClientToken('search-test-a-again');
    await tester.pumpAndSettle();
    expect(find.text('账号甲关键词'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('community_search_history_v1_user_77'), isNull);
    expect(
        prefs.getStringList('community_search_history_v1_user_88'), ['账号乙关键词']);
    expect(prefs.getStringList('community_search_history_v1'), ['旧公共记录']);
  });

  testWidgets('业务拒绝显示重试且重试沿用已提交关键词', (tester) async {
    respond = (r, h) => reply(r, h, {'code': 503, 'message': '搜索暂不可用'});
    await tester.pumpWidget(const MaterialApp(home: CommunitySearchPage()));
    await tester.pumpAndSettle();
    await search(tester, '原词');
    expect(find.text('搜索暂不可用'), findsOneWidget);
    expect(find.text('未找到相关帖子'), findsNothing);
    await tester.enterText(find.byType(TextField), '尚未提交');
    respond = (r, h) => reply(r, h, {
          'code': 0,
          'data': {'list': [], 'hasMore': false}
        });
    await tester.tap(find.text('重试搜索'));
    await tester.pumpAndSettle();
    expect(calls.last.queryParameters['keyword'], '原词');
    expect(find.text('未找到相关帖子'), findsOneWidget);
  });

  testWidgets('返回结构异常结束加载并显示可重试错误', (tester) async {
    respond = (r, h) => reply(r, h, {
          'code': 0,
          'data': {'list': 'invalid'}
        });
    await tester.pumpWidget(const MaterialApp(home: CommunitySearchPage()));
    await tester.pumpAndSettle();
    await search(tester, '关键词');
    expect(find.text('重试搜索'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('用户'));
    await tester.pumpAndSettle();
    expect(find.text('重试搜索'), findsOneWidget);
  });

  testWidgets('用户分页失败保留第一页且重试同一页并去重', (tester) async {
    var failSecond = true;
    respond = (r, h) {
      final page = r.queryParameters['page'];
      if (r.path.endsWith('/post/search')) {
        reply(r, h, {
          'code': 0,
          'data': {'list': [], 'hasMore': false}
        });
      } else if (page == 2 && failSecond) {
        reply(r, h, {'code': 503, 'message': '下一页暂不可用'});
      } else {
        reply(r, h, {
          'code': 0,
          'data': {
            'list': [
              {'userId': 1, 'nickname': '用户甲'},
              if (page == 2) {'userId': 2, 'nickname': '用户乙'},
            ],
            'hasMore': page == 1
          }
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(home: CommunitySearchPage()));
    await tester.pumpAndSettle();
    await search(tester, '用户');
    await tester.tap(find.widgetWithText(Tab, '用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('用户甲'), findsOneWidget);
    expect(find.text('下一页暂不可用'), findsOneWidget);
    failSecond = false;
    await tester.tap(find.text('重试搜索'));
    await tester.pumpAndSettle();
    expect(find.text('用户甲'), findsOneWidget);
    expect(find.text('用户乙'), findsOneWidget);
    expect(
        calls
            .where((r) => r.path.endsWith('/user/search'))
            .map((r) => r.queryParameters['page']),
        [1, 2, 2]);
  });
}
