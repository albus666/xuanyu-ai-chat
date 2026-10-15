import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/shop/shop_logistics_page.dart';

void main() {
  testWidgets('订单物流页展示当前位置和运输轨迹', (tester) async {
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.endsWith('/api/shop/orders/9/logistics')) {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'company': '顺丰速运',
                'trackingNo': 'SF123456789',
                'status': '派送中',
                'currentLocation': '北京市朝阳区',
                'trackingAvailable': true,
                'message': '',
                'externalQueryUrl':
                    'https://m.kuaidi100.com/result.jsp?nu=SF123456789',
                'events': [
                  {
                    'time': '2026-09-12 10:20:00',
                    'description': '快件正在派送，请保持电话畅通',
                    'location': '北京市朝阳区',
                    'status': '派送中',
                  },
                  {
                    'time': '2026-09-11 18:10:00',
                    'description': '快件已到达北京转运中心',
                    'location': '北京市',
                    'status': '运输中',
                  },
                ],
              },
            },
          ));
          return;
        }
        handler.reject(DioException(
          requestOptions: options,
          message: 'unexpected request: ${options.path}',
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(const MaterialApp(
      home: ShopLogisticsPage(order: {'id': 9}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('物流详情'), findsOneWidget);
    expect(find.text('派送中'), findsOneWidget);
    expect(find.text('北京市朝阳区'), findsOneWidget);
    expect(find.text('快件正在派送，请保持电话畅通'), findsOneWidget);
    expect(find.text('快件已到达北京转运中心'), findsOneWidget);
    expect(find.text('通过快递100查询最新轨迹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
