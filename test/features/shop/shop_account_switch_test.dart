import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/shop/shop_address_page.dart';
import 'package:xuanyu/features/shop/shop_checkout_page.dart';
import 'package:xuanyu/features/shop/shop_orders_page.dart';

Response<dynamic> _response(RequestOptions request, Object? data) =>
    Response<dynamic>(
      requestOptions: request,
      statusCode: 200,
      data: {'code': 0, 'data': data},
    );

void main() {
  tearDown(() => setupApiClientToken(null));

  testWidgets('商城订单切号后旧响应不能覆盖新账号订单', (tester) async {
    setupApiClientToken('orders-old');
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final auth = request.headers['Authorization']?.toString() ?? '';
      if (auth.contains('orders-old')) {
        oldRequest = request;
        oldHandler = handler;
        return;
      }
      handler.resolve(_response(request, {
        'list': [
          {
            'id': 2,
            'orderNo': 'NEW-2',
            'status': 'completed',
            'payAmount': '2.00',
            'items': [
              {'productName': '新账号商品'},
            ],
          },
        ],
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(const MaterialApp(home: ShopOrdersPage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldHandler, isNotNull);
    setupApiClientToken('orders-new');
    await tester.pump(const Duration(milliseconds: 100));
    oldHandler!.resolve(_response(oldRequest!, {
      'list': [
        {
          'id': 1,
          'orderNo': 'OLD-1',
          'status': 'completed',
          'payAmount': '1.00',
          'items': [
            {'productName': '旧账号商品'},
          ],
        },
      ],
    }));
    await tester.pumpAndSettle();

    expect(find.text('新账号商品'), findsOneWidget);
    expect(find.text('旧账号商品'), findsNothing);
  });

  testWidgets('收货地址切号后只展示新账号地址', (tester) async {
    setupApiClientToken('address-old');
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final auth = request.headers['Authorization']?.toString() ?? '';
      if (auth.contains('address-old')) {
        oldRequest = request;
        oldHandler = handler;
        return;
      }
      handler.resolve(_response(request, {
        'list': [
          {
            'id': 2,
            'recipient': '新账号收件人',
            'mobile': '13800000002',
            'fullAddress': '新账号地址',
          },
        ],
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(const MaterialApp(home: ShopAddressPage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldHandler, isNotNull);
    setupApiClientToken('address-new');
    await tester.pump(const Duration(milliseconds: 100));
    oldHandler!.resolve(_response(oldRequest!, {
      'list': [
        {
          'id': 1,
          'recipient': '旧账号收件人',
          'mobile': '13800000001',
          'fullAddress': '旧账号地址',
        },
      ],
    }));
    await tester.pumpAndSettle();

    expect(find.text('新账号收件人'), findsOneWidget);
    expect(find.text('旧账号收件人'), findsNothing);
  });

  testWidgets('结算页切号后作废旧购物车并禁止继续提交', (tester) async {
    setupApiClientToken('checkout-old');
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/addresses')) {
        handler.resolve(_response(request, {'list': <Object>[]}));
        return;
      }
      if (request.path.endsWith('/preview')) {
        handler.resolve(_response(request, {
          'items': [
            {'productName': '旧购物车商品', 'quantity': 1, 'price': '1.00'},
          ],
          'goodsAmount': '1.00',
          'freightAmount': '0.00',
          'payAmount': '1.00',
        }));
        return;
      }
      handler.next(request);
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(
      const MaterialApp(home: ShopCheckoutPage(cartItemIds: [7])),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧购物车商品'), findsOneWidget);

    setupApiClientToken('checkout-new');
    await tester.pumpAndSettle();

    expect(find.text('账号已切换，请返回商城重新结算'), findsOneWidget);
    expect(find.text('旧购物车商品'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '提交订单'))
          .onPressed,
      isNull,
    );
  });
}
