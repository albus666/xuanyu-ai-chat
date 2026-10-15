import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/shop/shop_after_sale_page.dart';

Map<String, dynamic> record(int id, String status) => {
      'id': id,
      'orderNo': 'ORDER-$id',
      'type': 'refund',
      'status': status,
      'reason': '测试原因',
    };

void main() {
  setUp(() => setupApiClientToken('synthetic-after-sale-user'));
  tearDown(() {
    dismissAllAppToasts();
    setupApiClientToken(null);
  });

  void intercept(InterceptorsWrapper fake) {
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
  }

  void respond(RequestOptions request, RequestInterceptorHandler handler,
      List<Map<String, dynamic>> items) {
    handler.resolve(Response(
      requestOptions: request,
      statusCode: 200,
      data: {'code': 0, 'data': {'list': items}},
    ));
  }

  testWidgets('终态记录可删除，处理中保留取消入口', (tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    intercept(InterceptorsWrapper(onRequest: (r, h) => respond(r, h, [
      record(1, 'rejected'), record(2, 'completed'), record(3, 'cancelled'),
      record(4, 'pending'), record(5, 'approved'),
    ])));
    await tester.pumpWidget(const MaterialApp(home: ShopAfterSalePage()));
    await tester.pumpAndSettle();
    expect(find.text('删除记录'), findsNWidgets(3));
    expect(find.text('取消申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认删除后移除且重新打开不再显示，取消确认不发送请求', (tester) async {
    var items = [record(1, 'rejected')];
    var deletes = 0;
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') {
        expect(r.path, '/api/shop/after-sales/1');
        deletes++;
        items = [];
      }
      respond(r, h, items);
    }));
    await tester.pumpWidget(const MaterialApp(home: ShopAfterSalePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.textContaining('ORDER-1'), findsOneWidget);
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.textContaining('ORDER-1'), findsNothing);
    expect(find.text('暂无售后申请'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const MaterialApp(home: ShopAfterSalePage(key: ValueKey('reopen'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('ORDER-1'), findsNothing);
  });

  testWidgets('删除失败保留记录并允许重试', (tester) async {
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') {
        h.reject(DioException(requestOptions: r, response: Response(
          requestOptions: r, statusCode: 409,
          data: {'message': '售后申请仍在处理中，暂不能删除'},
        )));
      } else {
        respond(r, h, [record(1, 'rejected')]);
      }
    }));
    await tester.pumpWidget(const MaterialApp(home: ShopAfterSalePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ORDER-1'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除记录')).onPressed, isNotNull);
    expect(find.text('售后申请仍在处理中，暂不能删除'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('删除请求未完成时防重复提交', (tester) async {
    var deletes = 0;
    RequestOptions? pending;
    RequestInterceptorHandler? handler;
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') {
        deletes++;
        pending = r;
        handler = h;
      } else {
        respond(r, h, [record(1, 'cancelled')]);
      }
    }));
    await tester.pumpWidget(const MaterialApp(home: ShopAfterSalePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除记录')).onPressed, isNull);
    respond(pending!, handler!, []);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('确认弹窗期间切号不能删除旧账号记录', (tester) async {
    var deletes = 0;
    intercept(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') deletes++;
      final next = r.headers['Authorization'] == 'Bearer synthetic-next-user';
      respond(r, h, [record(next ? 2 : 1, 'rejected')]);
    }));
    await tester.pumpWidget(const MaterialApp(home: ShopAfterSalePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    setupApiClientToken('synthetic-next-user');
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.textContaining('ORDER-1'), findsNothing);
    expect(find.textContaining('ORDER-2'), findsOneWidget);
  });
}
