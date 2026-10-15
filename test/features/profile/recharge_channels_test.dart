import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/profile/recharge_page.dart';

void main() {
  testWidgets('未配置微信仍展示入口，点击提示且不切换支付渠道', (tester) async {
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {
          'channels': ['alipay']
        }
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: RechargePage()));
    await tester.pumpAndSettle();
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);
    await tester.ensureVisible(find.text('微信支付'));
    await tester.tap(find.text('微信支付'));
    await tester.pump();
    expect(find.text('上线后才可申请微信支付'), findsOneWidget);
    final alipay = find
        .ancestor(of: find.text('支付宝'), matching: find.byType(GestureDetector))
        .first;
    expect(
        find.descendant(
            of: alipay, matching: find.byIcon(Icons.check_circle_rounded)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('正在加载支付方式…'), findsNothing);
  });

  testWidgets('已配置支付宝也只提示上线后申请，确认充值不创建支付订单', (tester) async {
    var creates = 0;
    final fake = InterceptorsWrapper(
      onRequest: (request, handler) {
        if (request.path.endsWith('/create')) creates++;
        handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'channels': ['alipay', 'wechat'],
              },
            },
          ),
        );
      },
    );
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: RechargePage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('支付宝'));
    await tester.tap(find.text('支付宝'));
    await tester.pump();
    expect(find.text('上线后才可申请支付宝支付'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.ensureVisible(find.text('确认支付并充值'));
    await tester.tap(find.text('确认支付并充值'));
    await tester.pump();
    expect(find.text('上线后才可申请支付宝支付'), findsOneWidget);
    expect(creates, 0);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('未配置任何支付渠道时禁用充值，不创建订单', (tester) async {
    var creates = 0;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/create')) creates++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {'channels': []}
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: RechargePage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.ensureVisible(find.text('确认支付并充值'));
    await tester.tap(find.text('确认支付并充值'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('支付宝'));
    await tester.tap(find.text('支付宝'));
    await tester.pump();
    expect(find.text('上线后才可申请支付宝支付'), findsOneWidget);
    expect(creates, 0);
    expect(find.text('充值暂不可用，请稍后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('支付渠道加载失败可重试恢复，失败时不能充值', (tester) async {
    var loads = 0;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      loads++;
      if (loads == 1) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      } else {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {
            'channels': ['alipay']
          }
        }));
      }
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: RechargePage()));
    await tester.pumpAndSettle();
    expect(find.text('支付方式加载失败，请重试'), findsOneWidget);
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('支付方式加载失败，请重试'), findsNothing);
  });
}
