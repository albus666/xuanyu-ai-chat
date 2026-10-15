import 'package:xuanyu/features/consultation/consultation_call_overlay.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/consultation/private_line_checkout_page.dart';
import 'package:xuanyu/features/consultation/consultation_call_page.dart';

void main() {
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) createSession;
  late void Function(RequestOptions, RequestInterceptorHandler) paymentSetting;
  late List<Map<String, dynamic>> existingSessions;
  late Map<String, dynamic> sessionDetail;
  late Object walletBalance;
  final calls = <RequestOptions>[];

  void ok(
      RequestOptions request, RequestInterceptorHandler handler, Object data) {
    handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {'code': 0, 'data': data}));
  }

  setUp(() {
    calls.clear();
    existingSessions = [];
    walletBalance = 100;
    sessionDetail = {
      'id': 51,
      'status': 'waiting',
      'teacherId': 9,
      'mode': 'private',
      'paymentMethod': 'coin'
    };
    apiClient.options.headers['Authorization'] = 'isolated-checkout-account-a';
    createSession = (r, h) => ok(r, h, {'id': 51});
    paymentSetting = (r, h) => ok(r, h, {
          'coinEnabled': true,
          'preferredMethod': 'coin',
          'alipay': {'available': false, 'signed': false},
        });
    interceptor = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      if (r.path.endsWith('/payment-setting')) return paymentSetting(r, h);
      if (r.path.endsWith('/wallet/balance')) {
        return ok(r, h, {'balance': walletBalance});
      }
      if (r.path.endsWith('/config')) return ok(r, h, {'freezeMinutes': 5});
      if (r.path.endsWith('/sessions') && r.method == 'POST') {
        return createSession(r, h);
      }
      if (r.path.endsWith('/sessions')) {
        return ok(r, h, {'list': existingSessions});
      }
      return ok(r, h, sessionDetail);
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    ConsultationCallOverlay.instance.close();
    dismissAllAppToasts();
    apiClient.interceptors.remove(interceptor);
    apiClient.options.headers.remove('Authorization');
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester,
      {Future<void> Function()? beforeEnter}) async {
    tester.view.physicalSize = const Size(440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [ConsultationBackNavigatorObserver()],
      builder: (_, child) => ConsultationCallOverlayHost(child: child!),
      home: const Scaffold(),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => PrivateLineCheckoutPage(
              teacherId: 9,
              teacher: const {
                'nickname': '测试老师',
                'privatePricePerMin': 2,
                'serviceStatus': 'online'
              },
              beforeEnterCall: beforeEnter,
            )));
    await frames(tester);
  }

  Future<void> agree(WidgetTester tester) async {
    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
  }

  int getPosts() => calls
      .where((r) => r.method == 'POST' && r.path.endsWith('/sessions'))
      .length;
  FilledButton button(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton).last);

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('支付状态仍加载时不能发起或跳去开通', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    paymentSetting = (r, h) {
      pendingRequest = r;
      pending = h;
    };
    await open(tester);
    expect(button(tester).onPressed, isNull);
    ok(pendingRequest!, pending!, {'coinEnabled': true});
    await frames(tester);
    await finish(tester);
  });

  testWidgets('支付配置业务失败保留错误并允许重试，不冒充未开通', (tester) async {
    paymentSetting = (r, h) => h.resolve(Response(
        requestOptions: r,
        statusCode: 200,
        data: {'code': 503, 'message': '支付状态暂时不可用'}));
    await open(tester);
    expect(find.text('重试加载'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
    expect(find.text('先开通玄遇币支付'), findsNothing);
    await finish(tester);
  });

  testWidgets('函数内防重入，同一帧重复点击只提交一次', (tester) async {
    final pending = <MapEntry<RequestOptions, RequestInterceptorHandler>>[];
    createSession = (r, h) => pending.add(MapEntry(r, h));
    await open(tester, beforeEnter: () async => throw StateError('模拟进入失败'));
    await agree(tester);
    final start = button(tester).onPressed!;
    start();
    start();
    await frames(tester);
    expect(getPosts(), 1);
    for (final request in pending) {
      ok(request.key, request.value, {'id': 51});
    }
    await frames(tester);
    await finish(tester);
  });

  testWidgets('公开咨询冲突直接提示下麦，不进入创建结果待确认状态', (tester) async {
    createSession = (r, h) => h.resolve(Response(
        requestOptions: r,
        statusCode: 200,
        data: {'code': 409, 'message': '您正在公开咨询中，请下麦后点击。'}));
    await open(tester);
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(find.text('您正在公开咨询中，请下麦后点击。'), findsOneWidget);
    expect(find.textContaining('尚未确认创建结果'), findsNothing);
    expect(getPosts(), 1);
    await finish(tester);
  });

  testWidgets('业务拒绝即使夹带id也不得进入通话', (tester) async {
    var entered = 0;
    createSession =
        (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200, data: {
              'code': 403,
              'message': '不可发起咨询',
              'data': {'id': 51}
            }));
    await open(tester, beforeEnter: () async {
      entered++;
      throw StateError('不得调用');
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(entered, 0);
    await finish(tester);
  });

  testWidgets('创建期间切号，迟到成功不执行房间回调也不跳转', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    var entered = 0;
    createSession = (r, h) {
      pendingRequest = r;
      pending = h;
    };
    await open(tester, beforeEnter: () async {
      entered++;
      throw StateError('不得调用');
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    apiClient.options.headers['Authorization'] = 'isolated-checkout-account-b';
    apiSessionChanges.value++;
    ok(pendingRequest!, pending!, {'id': 51});
    await frames(tester);
    expect(entered, 0);
    expect(find.text('账号已切换，请返回后重新进入'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('已创建但进入失败，重试仅复用同一咨询不再POST', (tester) async {
    var entered = 0;
    await open(tester, beforeEnter: () async {
      entered++;
      throw StateError('模拟进入失败');
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(getPosts(), 1);
    expect(entered, 2);
    await finish(tester);
  });

  testWidgets('创建500结果不确定，再点仅核对状态不重复创建', (tester) async {
    createSession = (r, h) => h.reject(DioException(
        requestOptions: r,
        response: Response(requestOptions: r, statusCode: 500),
        type: DioExceptionType.badResponse));
    await open(tester);
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(getPosts(), 1);
    expect(calls.any((r) => r.path.endsWith('/sessions') && r.method == 'GET'),
        isTrue);
    await finish(tester);
  });

  testWidgets('配置失败重试成功恢复原支付方式且不创建咨询', (tester) async {
    paymentSetting = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await open(tester);
    expect(find.text('重试加载'), findsOneWidget);
    paymentSetting = (r, h) => ok(r, h, {'coinEnabled': true});
    await tester.tap(find.text('重试加载'));
    await frames(tester);
    expect(find.text('发起私人专线'), findsOneWidget);
    expect(getPosts(), 0);
    await finish(tester);
  });

  testWidgets('钱包畸形余额禁止继续支付而不是当作未知余额放行', (tester) async {
    walletBalance = 'NaN';
    await open(tester);
    expect(find.text('重试加载'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
    expect(getPosts(), 0);
    await finish(tester);
  });

  testWidgets('未确认计费规则不创建咨询', (tester) async {
    await open(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(getPosts(), 0);
    expect(find.text('请先确认服务与计费规则'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('超时后核对找到同一咨询，只恢复原id并固定请求账号', (tester) async {
    var entered = 0;
    createSession = (r, h) => h.reject(
        DioException(requestOptions: r, type: DioExceptionType.receiveTimeout));
    await open(tester, beforeEnter: () async {
      entered++;
      throw StateError('模拟进入失败');
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    existingSessions = [sessionDetail];
    button(tester).onPressed!();
    await frames(tester);
    expect(entered, 1);
    expect(find.text('继续进入咨询'), findsOneWidget);
    button(tester).onPressed!();
    await frames(tester);
    expect(getPosts(), 1);
    expect(
        calls.any((r) => r.path.endsWith('/sessions/51') && r.method == 'GET'),
        isTrue);
    expect(
        calls.every(
            (r) => r.headers['Authorization'] == 'isolated-checkout-account-a'),
        isTrue);
    await finish(tester);
  });

  testWidgets('结果待确认时不能误进其它老师房间付款方式或结束咨询', (tester) async {
    var entered = 0;
    createSession = (r, h) => h.reject(
        DioException(requestOptions: r, type: DioExceptionType.receiveTimeout));
    await open(tester, beforeEnter: () async {
      entered++;
      throw StateError('不得进入');
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    existingSessions = [
      {...sessionDetail, 'teacherId': 10},
      {...sessionDetail, 'mode': 'private_mic'},
      {...sessionDetail, 'roomId': 99},
      {...sessionDetail, 'paymentMethod': 'alipay'},
      {...sessionDetail, 'status': 'ended'},
    ];
    button(tester).onPressed!();
    await frames(tester);
    expect(entered, 0);
    expect(getPosts(), 1);
    expect(find.text('核对咨询状态'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('已创建咨询若已结束，继续进入不复活且不再创建', (tester) async {
    var entered = 0;
    await open(tester, beforeEnter: () async {
      entered++;
      throw StateError('模拟进入失败');
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    sessionDetail['status'] = 'ended';
    button(tester).onPressed!();
    await frames(tester);
    expect(entered, 1);
    expect(getPosts(), 1);
    expect(button(tester).onPressed, isNull);
    expect(find.text('请返回查看咨询记录'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('房间进入回调执行期间切号，完成后不跳入旧账号通话', (tester) async {
    final callback = Completer<void>();
    await open(tester, beforeEnter: () => callback.future);
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    apiClient.options.headers['Authorization'] = 'isolated-checkout-account-b';
    apiSessionChanges.value++;
    callback.complete();
    await frames(tester);
    expect(find.byType(ConsultationCallPage), findsNothing);
    expect(find.text('账号已切换，请返回后重新进入'), findsOneWidget);
    expect(getPosts(), 1);
    await finish(tester);
  });

  testWidgets('成功但会话id畸形按未知结果处理，不能盲重试创建', (tester) async {
    createSession = (r, h) => ok(r, h, {'id': 0});
    await open(tester);
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(find.text('核对咨询状态'), findsOneWidget);
    button(tester).onPressed!();
    await frames(tester);
    expect(getPosts(), 1);
    await finish(tester);
  });

  testWidgets('正常确认成功按返回id进入通话页面且只提交一次', (tester) async {
    var entered = 0;
    await open(tester, beforeEnter: () async {
      entered++;
    });
    await agree(tester);
    button(tester).onPressed!();
    await frames(tester);
    expect(entered, 1);
    expect(getPosts(), 1);
    expect(
        tester
            .widget<ConsultationCallPage>(find.byType(ConsultationCallPage))
            .sessionId,
        51);
    await tester.binding.handlePopRoute();
    await frames(tester);
    expect(find.text('继续通话'), findsOneWidget);
    await tester.tap(find.text('继续通话'));
    await frames(tester);
    expect(ConsultationCallOverlay.instance.minimized, isTrue);
    expect(ConsultationCallOverlay.instance.sessionId, 51);
    ConsultationCallOverlay.instance.restore();
    await frames(tester);
    expect(ConsultationCallOverlay.instance.minimized, isFalse);
    await finish(tester);
  });

  testWidgets('支付加载途中切号，迟到支付状态不恢复旧账号表单', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    paymentSetting = (r, h) {
      pendingRequest = r;
      pending = h;
    };
    await open(tester);
    apiClient.options.headers['Authorization'] = 'isolated-checkout-account-b';
    apiSessionChanges.value++;
    ok(pendingRequest!, pending!, {'coinEnabled': true});
    await frames(tester);
    expect(find.text('账号已切换，请返回后重新进入'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(button(tester).onPressed, isNull);
    expect(getPosts(), 0);
    await finish(tester);
  });
}
