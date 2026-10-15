import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/profile/orders_page.dart';

void main() {
  testWidgets('订单状态本地化且终态记录可以删除', (tester) async {
    var deleted = false;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'DELETE') {
          deleted = options.path == '/api/auth/orders/9';
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {'code': 0, 'data': null},
          ));
          return;
        }
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'code': 0,
            'data': {
              'list': [
                {
                  'id': 9,
                  'orderNo': 'XY202609260001',
                  'type': 'shop_order',
                  'amount': '0.0100',
                  'status': 'cancelled',
                  'subject': '测试商品',
                  'createdAt': '2026-09-26T07:41:00+00:00',
                  'canDelete': true,
                },
              ],
              'hasMore': false,
            },
          },
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(const MaterialApp(home: OrdersPage()));
    await tester.pumpAndSettle();

    expect(find.text('商城订单 · ¥0.01'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('cancelled'), findsNothing);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('商城订单 · ¥0.01'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
