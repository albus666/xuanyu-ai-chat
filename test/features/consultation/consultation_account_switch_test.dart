import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/consultation_history_page.dart';
import 'package:xuanyu/features/consultation/consultation_payment_setting_page.dart';

Response<dynamic> _response(RequestOptions request, Object? data) =>
    Response<dynamic>(
      requestOptions: request,
      statusCode: 200,
      data: {'code': 0, 'data': data},
    );

void main() {
  tearDown(() => setupApiClientToken(null));

  testWidgets('支付设置切号后立即加载新账号，旧响应不能回填', (tester) async {
    setupApiClientToken('payment-old');
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    var newLoads = 0;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path != '/api/consultation/payment-setting') {
        handler.next(request);
        return;
      }
      final auth = request.headers['Authorization']?.toString() ?? '';
      if (auth.contains('payment-old')) {
        oldRequest = request;
        oldHandler = handler;
        return;
      }
      newLoads++;
      handler.resolve(_response(request, {
        'coinEnabled': false,
        'preferredMethod': 'coin',
        'alipay': {'available': false, 'signed': false, 'status': 'unsigned'},
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(
      const MaterialApp(home: ConsultationPaymentSettingPage()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldHandler, isNotNull);

    setupApiClientToken('payment-new');
    await tester.pump(const Duration(milliseconds: 100));
    expect(newLoads, 1);

    oldHandler!.resolve(_response(oldRequest!, {
      'coinEnabled': true,
      'preferredMethod': 'coin',
      'alipay': {'available': true, 'signed': false, 'status': 'unsigned'},
    }));
    await tester.pumpAndSettle();

    expect(find.text('未开通 · 按实际时长结算并释放余款'), findsOneWidget);
    expect(find.text('已开通 · 连接前余额须满足至少5分钟'), findsNothing);
  });

  testWidgets('咨询记录切号后清空旧列表并只展示新账号记录', (tester) async {
    setupApiClientToken('history-old');
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final auth = request.headers['Authorization']?.toString() ?? '';
      if (auth.contains('history-old') &&
          request.path == '/api/consultation/sessions') {
        oldRequest = request;
        oldHandler = handler;
        return;
      }
      final isAppointment = request.path.endsWith('/appointments');
      handler.resolve(_response(request, {
        'list': isAppointment
            ? <Object>[]
            : [
                {
                  'id': 22,
                  'status': 'ended',
                  'mode': 'private',
                  'peer': {'nickname': '新账号咨询'},
                },
              ],
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(
      const MaterialApp(home: ConsultationHistoryPage()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldHandler, isNotNull);

    setupApiClientToken('history-new');
    await tester.pump(const Duration(milliseconds: 100));
    oldHandler!.resolve(_response(oldRequest!, {
      'list': [
        {
          'id': 11,
          'status': 'ended',
          'mode': 'private',
          'peer': {'nickname': '旧账号咨询'},
        },
      ],
    }));
    await tester.pumpAndSettle();

    expect(find.text('新账号咨询'), findsOneWidget);
    expect(find.text('旧账号咨询'), findsNothing);
  });
}
