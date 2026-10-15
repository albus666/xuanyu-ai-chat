import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/shop/shop_checkout_page.dart';
import 'package:xuanyu/features/shop/shop_presale_notice.dart';
import 'package:xuanyu/features/shop/shop_orders_page.dart';

const presale = <String, dynamic>{
  'batch': '慢半拍首批',
  'payment': 'full',
  'state': 'open',
  'limit': 2,
  'startAt': '2026-10-01T00:00:00Z',
  'endAt': '2026-10-20T00:00:00Z',
  'shipBy': '2026-11-01T10:00:00Z',
};

void main() {
  tearDown(() => setupApiClientToken(null));

  test('发货时间固定展示北京时间', () {
    expect(shopPresaleTime('2026-11-01T10:00:00Z'), '2026-11-01 18:00');
    expect(shopPresaleTime('2026-11-01T18:00:00+08:00'), '2026-11-01 18:00');
  });

  testWidgets('320宽大字预售告知保留原承诺和延期说明', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: Scaffold(
          body: SingleChildScrollView(
              child: ShopPresaleNotice(
        data: {
          ...presale,
          'overdue': true,
          'delayNote': '包装补货中，预计发货时间已更新',
          'revisedShipAt': '2026-11-03T10:00:00Z'
        },
        order: true,
      ))),
    )));
    expect(find.textContaining('原承诺最晚发货：2026-11-01 18:00'), findsOneWidget);
    expect(find.textContaining('更新预计：2026-11-03 18:00'), findsOneWidget);
    expect(find.text('预售已逾期 · 可申请退款'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未确认预售不能提交，确认后携带报价与幂等编号', (tester) async {
    setupApiClientToken('synthetic-presale-user');
    final creates = <Map>[];
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      Object data = {};
      if (request.path.endsWith('/addresses')) {
        data = {
          'list': [
            {'id': 1, 'recipient': '测试', 'fullAddress': '合成地址'}
          ]
        };
      } else if (request.path.endsWith('/preview')) {
        data = {
          'presale': presale,
          'quoteToken': 'signed-synthetic-quote',
          'payAmount': '19.90',
          'goodsAmount': '19.90',
          'items': [
            {'skuId': 1, 'productName': '测试周边', 'quantity': 1, 'price': '19.90'}
          ]
        };
      } else if (request.path.endsWith('/payment-methods')) {
        data = {
          'list': [
            {'code': 'wechat', 'name': '微信支付'}
          ]
        };
      } else if (request.path == '/api/shop/orders' &&
          request.method == 'POST') {
        creates.add(Map.from(request.data as Map));
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionTimeout));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'code': 0, 'data': data}));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(
        home: ShopCheckoutPage(items: [
      {'skuId': 1, 'quantity': 1}
    ])));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, '提交订单');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 180);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    if (find.text('微信支付').evaluate().isNotEmpty) {
      await tester.tap(find.text('微信支付').last);
      await tester.pumpAndSettle();
    }
    expect(creates, hasLength(1));
    expect(creates.first['presaleAccepted'], true);
    expect(creates.first['quoteToken'], 'signed-synthetic-quote');
    expect(creates.first['requestId'], isNotEmpty);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    if (find.text('微信支付').evaluate().isNotEmpty) {
      await tester.tap(find.text('微信支付').last);
      await tester.pumpAndSettle();
    }
    expect(creates, hasLength(2));
    expect(creates.last['requestId'], creates.first['requestId']);
    await tester.pump(const Duration(seconds: 3));
    setupApiClientToken('switched-user');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('超时付款显示退款处理中而非已退款', (tester) async {
    setupApiClientToken('synthetic-order-user');
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {
          'list': [
            {
              'id': 1,
              'orderNo': 'synthetic-late',
              'status': 'refund_pending',
              'payAmount': '19.90',
              'presale': presale,
              'items': [
                {'productName': '测试周边'}
              ]
            }
          ]
        }
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: ShopOrdersPage()));
    await tester.pumpAndSettle();
    expect(find.text('超时付款退款中'), findsOneWidget);
    expect(find.textContaining('到账以支付渠道确认为准'), findsOneWidget);
    expect(find.text('立即付款'), findsNothing);
  });
}
