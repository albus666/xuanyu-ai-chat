import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/shop/goodwill_echo_page.dart';

Map<String, dynamic> record(int id, [String status = 'approved']) => {
      'id': id,
      'campaignTitle': '申请$id',
      'description': '善意记录$id',
      'status': status,
      'orderId': status == 'approved' ? 100 + id : null,
      'evidenceUrls': [''],
    };

void respond(RequestOptions r, RequestInterceptorHandler h,
    List<Map<String, dynamic>> items,
    {int code = 0}) {
  h.resolve(Response(requestOptions: r, statusCode: 200, data: {
    'code': code,
    'message': code == 0 ? 'success' : '删除失败，请重试',
    'data': {'list': r.path.endsWith('/campaigns') ? [] : items},
  }));
}

void main() {
  setUp(() => setupApiClientToken('synthetic-goodwill-user'));
  tearDown(() {
    dismissAllAppToasts();
    setupApiClientToken(null);
  });
  void intercept(InterceptorsWrapper fake) {
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
  }

  Future<void> openDelete(WidgetTester tester) async {
    await tester.ensureVisible(find.text('删除记录').first);
    await tester.tap(find.text('删除记录').first);
    await tester.pumpAndSettle();
  }

  testWidgets('四种状态都能删除，窄屏操作区完整显示且待审核仍可取消', (tester) async {
    tester.view.physicalSize = const Size(320, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    intercept(InterceptorsWrapper(
        onRequest: (r, h) => respond(r, h, [
              record(1),
              record(2, 'pending'),
              record(3, 'rejected'),
              record(4, 'cancelled'),
            ])));
    await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
    await tester.pumpAndSettle();
    expect(find.text('删除记录'), findsNWidgets(4));
    expect(find.text('取消申请'), findsOneWidget);
    expect(find.text('查看赠礼订单'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认删除并持久移除，取消确认不发请求，赠礼订单入口保留', (tester) async {
    var items = [record(1)];
    var deletes = 0;
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') {
        expect(r.path, '/api/shop/goodwill/applications/1');
        deletes++;
        items = [];
      }
      respond(r, h, items);
    }));
    await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
    await tester.pumpAndSettle();
    await openDelete(tester);
    expect(find.textContaining('已生成的赠礼订单不受影响'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await openDelete(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('申请1'), findsNothing);
    expect(find.text('查看赠礼订单'), findsOneWidget);
    await tester.pumpWidget(
        const MaterialApp(home: GoodwillEchoPage(key: ValueKey('reopen'))));
    await tester.pumpAndSettle();
    expect(find.text('申请1'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  for (final transportError in [true, false]) {
    testWidgets('删除${transportError ? '网络' : '业务'}失败保留记录并恢复操作', (tester) async {
      intercept(InterceptorsWrapper(onRequest: (r, h) {
        if (r.method == 'DELETE' && transportError) {
          h.reject(DioException(requestOptions: r));
        } else {
          respond(r, h, [record(1)], code: r.method == 'DELETE' ? 500 : 0);
        }
      }));
      await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
      await tester.pumpAndSettle();
      await openDelete(tester);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('申请1'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '删除记录'))
              .onPressed,
          isNotNull);
      expect(find.text('删除失败，请重试'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('删除请求未完成时禁止重复提交', (tester) async {
    var deletes = 0;
    RequestOptions? pending;
    RequestInterceptorHandler? handler;
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') {
        deletes++;
        pending = r;
        handler = h;
      } else {
        respond(r, h, [record(1)]);
      }
    }));
    await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
    await tester.pumpAndSettle();
    await openDelete(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '删除中…'))
            .onPressed,
        isNull);
    respond(pending!, handler!, []);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('确认期间切换账号不会删除旧记录或污染新列表', (tester) async {
    var deletes = 0;
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') deletes++;
      final next = r.headers['Authorization'] == 'Bearer synthetic-next-user';
      respond(r, h, [record(next ? 2 : 1)]);
    }));
    await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
    await tester.pumpAndSettle();
    await openDelete(tester);
    setupApiClientToken('synthetic-next-user');
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.text('申请1'), findsNothing);
    expect(find.text('申请2'), findsOneWidget);
  });
}
