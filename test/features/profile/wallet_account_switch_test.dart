import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/profile/balance_page.dart';
import 'package:xuanyu/features/profile/recharge_page.dart';
import 'package:xuanyu/features/profile/withdraw_page.dart';
import 'package:xuanyu/features/consultation/teacher_income_page.dart';

Response<dynamic> _response(RequestOptions request, Object? data) =>
    Response<dynamic>(
      requestOptions: request,
      statusCode: 200,
      data: {'code': 0, 'data': data},
    );

void main() {
  tearDown(() => setupApiClientToken(null));

  testWidgets('钱包切号后只显示新账号余额和流水', (tester) async {
    setupApiClientToken('wallet-old');
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final auth = request.headers['Authorization']?.toString() ?? '';
      if (auth.contains('wallet-old') && request.path.endsWith('/balance')) {
        oldRequest = request;
        oldHandler = handler;
        return;
      }
      if (request.path.endsWith('/balance')) {
        handler.resolve(_response(request, {
          'balance': '22.00',
          'frozenAmount': '0',
        }));
      } else {
        handler.resolve(_response(request, {
          'list': [
            {
              'id': 2,
              'type': 'recharge',
              'amount': '2.00',
              'remark': '新账号充值',
            },
          ],
          'hasMore': false,
        }));
      }
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(const MaterialApp(home: BalancePage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldHandler, isNotNull);
    setupApiClientToken('wallet-new');
    await tester.pump(const Duration(milliseconds: 100));
    oldHandler!.resolve(_response(oldRequest!, {
      'balance': '99.00',
      'frozenAmount': '0',
    }));
    await tester.pumpAndSettle();

    expect(find.text('22.00 币'), findsOneWidget);
    expect(find.text('99.00 币'), findsNothing);
    expect(find.text('新账号充值'), findsOneWidget);
  });

  testWidgets('充值订单请求期间切号，不得唤起旧流程支付', (tester) async {
    setupApiClientToken('recharge-old');
    var creates = 0;
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pendingHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path == '/api/auth/order/create') {
        creates++;
        pendingRequest = request;
        pendingHandler = handler;
        return;
      }
      handler.resolve(_response(
          request,
          request.path == '/api/auth/payment/channels'
              ? {
                  'channels': ['alipay']
                }
              : {}));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: RechargePage()));
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.ensureVisible(find.text('确认支付并充值'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认支付并充值'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('确认购买玄遇币？'), findsNothing);
    expect(creates, 1);
    setupApiClientToken('recharge-new');
    await tester.pump();
    pendingHandler!.resolve(_response(pendingRequest!, {
      'payMode': 'app',
      'alipayOrderString': 'isolated-test-order',
    }));
    await tester.pumpAndSettle();
    expect(creates, 1);
    expect(find.text('账号已切换，请返回后重新进入充值页'), findsOneWidget);
  });

  testWidgets('充值按钮直接唤起支付宝且连续点击只创建一单', (tester) async {
    setupApiClientToken('direct-recharge');
    var creates = 0;
    var payments = 0;
    const channel = MethodChannel('com.jarvanmo/tobias');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'pay') payments++;
      return {'resultStatus': '6001'};
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path == '/api/auth/order/create') {
        creates++;
        expect((request.data as Map)['amount'], '12.00');
      }
      handler.resolve(_response(
          request,
          request.path == '/api/auth/payment/channels'
              ? {
                  'channels': ['alipay']
                }
              : {
                  'payMode': 'app',
                  'alipayOrderString': 'isolated-test-order'
                }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: RechargePage()));
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.ensureVisible(find.text('确认支付并充值'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认支付并充值'));
    await tester.tap(find.text('确认支付并充值'));
    await tester.pumpAndSettle();
    expect(creates, 1);
    expect(payments, 1);
    expect(find.text('确认购买玄遇币？'), findsNothing);
    expect(find.textContaining('需支付'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('退款页切号后只使用新账号可退额度', (tester) async {
    setupApiClientToken('refund-old');
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final auth = request.headers['Authorization']?.toString() ?? '';
      if (auth.contains('refund-old')) {
        oldRequest = request;
        oldHandler = handler;
        return;
      }
      handler.resolve(_response(request, {
        'balance': '12.00',
        'maxRefundAmount': '6.00',
        'orders': <Object>[],
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(const MaterialApp(home: WithdrawPage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldHandler, isNotNull);
    setupApiClientToken('refund-new');
    await tester.pump(const Duration(milliseconds: 100));
    oldHandler!.resolve(_response(oldRequest!, {
      'balance': '99.00',
      'maxRefundAmount': '88.00',
      'orders': <Object>[],
    }));
    await tester.pumpAndSettle();

    expect(find.textContaining('可用 12.00 币 · 最多可退 6.00 币'), findsOneWidget);
    expect(find.textContaining('99.00'), findsNothing);
  });

  testWidgets('收益提现弹窗期间切号，不得用新账号提交旧申请', (tester) async {
    setupApiClientToken('income-old');
    var withdrawals = 0;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') {
        withdrawals++;
        handler.resolve(_response(request, <String, Object?>{}));
        return;
      }
      final auth = request.headers['Authorization']?.toString() ?? '';
      handler.resolve(_response(request, {
        'settlement': {
          'availableAmount': auth.contains('income-old') ? '100.00' : '0.00',
          'minimumWithdrawal': '1.00',
        },
        'list': <Object>[],
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));

    await tester.pumpWidget(const MaterialApp(home: TeacherIncomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请提现'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我确认收款信息真实，并同意平台结算与依法纳税规则'));
    await tester.pumpAndSettle();

    setupApiClientToken('income-new');
    await tester.pump();
    await tester.tap(find.text('提交申请'));
    await tester.pumpAndSettle();

    expect(withdrawals, 0);
  });
}
