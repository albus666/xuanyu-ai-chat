import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/community/user_search_page.dart';

void main() {
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];

  Map<String, dynamic> users(List<int> ids, {bool more = false}) => {
        'code': 0,
        'data': {
          'list': ids.map((id) => {'userId': id, 'nickname': '用户$id'}).toList(),
          'hasMore': more,
        },
      };
  void resolve(RequestOptions request, RequestInterceptorHandler handler,
          Object? body) =>
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: body));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setupApiClientToken('search-session');
    calls.clear();
    respond = (request, handler) => resolve(request, handler, users([]));
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserSearchPage()));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('新关键词可立即搜索，忽略迟到结果并抑制相同查询重复提交', (tester) async {
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    respond = (request, handler) {
      if (request.queryParameters['keyword'] == '旧词') {
        oldRequest = request;
        oldHandler = handler;
      } else {
        resolve(request, handler, users([2]));
      }
    };
    await open(tester);
    await search(tester, '旧词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(calls, hasLength(1));
    await tester.enterText(find.byType(TextField), '新词');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('用户2'), findsOneWidget);
    oldHandler!.resolve(Response(
        requestOptions: oldRequest!, statusCode: 200, data: users([1])));
    await tester.pumpAndSettle();
    expect(find.text('用户2'), findsOneWidget);
    expect(find.text('用户1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('清空输入使在途结果失效', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pendingHandler;
    respond = (request, handler) {
      pendingRequest = request;
      pendingHandler = handler;
    };
    await open(tester);
    await search(tester, '昵称');
    await tester.enterText(find.byType(TextField), '');
    pendingHandler!.resolve(Response(
        requestOptions: pendingRequest!, statusCode: 200, data: users([1])));
    await tester.pumpAndSettle();
    expect(find.text('输入昵称或ID寻找好友'), findsOneWidget);
    expect(find.text('用户1'), findsNothing);
  });

  for (final malformed in [false, true]) {
    testWidgets(malformed ? '格式错误终止加载并允许重试' : '业务失败显示真实错误而非空搜索',
        (tester) async {
      respond = (request, handler) => resolve(
          request,
          handler,
          malformed
              ? {
                  'code': 0,
                  'data': {'list': '错误格式', 'hasMore': false}
                }
              : {'code': 403, 'message': '当前无法搜索用户'});
      await open(tester);
      await search(tester, '昵称');
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('未找到相关用户'), findsNothing);
      expect(find.text(malformed ? '搜索失败，请重试' : '当前无法搜索用户'), findsOneWidget);
      respond = (request, handler) => resolve(request, handler, users([3]));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('用户3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('分页失败保留已有用户，重试相同页并去重', (tester) async {
    bool failed = false;
    respond = (request, handler) {
      if (request.queryParameters['page'] == 1) {
        resolve(request, handler, users([1], more: true));
      } else if (!failed) {
        failed = true;
        resolve(request, handler, {'code': 500, 'message': '暂时不可用'});
      } else {
        resolve(request, handler, users([1, 2]));
      }
    };
    await open(tester);
    await search(tester, '昵称');
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('用户1'), findsOneWidget);
    expect(find.text('暂时不可用'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls.map((r) => r.queryParameters['page']).toList(), [1, 2, 2]);
    expect(find.text('用户1'), findsOneWidget);
    expect(find.text('用户2'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换账号清除已有结果并拒绝迟到分页和后续搜索', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pendingHandler;
    respond = (request, handler) {
      if (request.queryParameters['page'] == 1) {
        resolve(request, handler, users([1], more: true));
      } else {
        pendingRequest = request;
        pendingHandler = handler;
      }
    };
    await open(tester);
    await search(tester, '昵称');
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pendingHandler, isNotNull);
    setupApiClientToken('different-session');
    await tester.pump();
    pendingHandler!.resolve(Response(
        requestOptions: pendingRequest!, statusCode: 200, data: users([2])));
    await tester.pumpAndSettle();
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(find.text('用户1'), findsNothing);
    expect(find.text('用户2'), findsNothing);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '搜索'))
            .onPressed,
        isNull);
    expect(calls, hasLength(2));
  });
}
