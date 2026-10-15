// Regression coverage: old calls must never borrow a new account session.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/bootstrap/startup_gate.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/consultation_call_page.dart';
import 'package:xuanyu/features/message/social_call_incoming_host.dart';
import 'package:xuanyu/features/message/social_call_page.dart';

/// All HTTP is intercepted. No real calls, tokens, or account data are used.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('xuanyu/voice_room_audio'), (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('xuanyu/voice_room_audio'), null);
  });
  // Complete outside each test's FakeAsync zone so subsequent widget tests can
  // subscribe to the same application startup gate reliably.
  StartupGate.markReady();
  late InterceptorsWrapper interceptor;
  final requests = <RequestOptions>[];
  RequestOptions? heldRequest;
  RequestInterceptorHandler? heldHandler;
  var holdIncoming = false;
  var failEnd = false;
  var consultationStatus = 'waiting';
  var socialStatus = 'ringing';
  var failSocialEnd = false;

  void respond(RequestOptions request, RequestInterceptorHandler handler,
      Map<String, dynamic> data) {
    handler.resolve(Response(
      requestOptions: request,
      statusCode: 200,
      data: {'code': 0, 'data': data},
    ));
  }

  setUp(() {
    requests.clear();
    holdIncoming = false;
    failEnd = false;
    consultationStatus = 'waiting';
    socialStatus = 'ringing';
    failSocialEnd = false;
    heldRequest = null;
    heldHandler = null;
    setupApiClientToken('audit-account-a-not-a-real-token');
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      if (request.path.startsWith('/api/consultation/sessions/') &&
          (request.path.endsWith('/end') || request.path.endsWith('/cancel'))) {
        if (failEnd) {
          consultationStatus = 'active';
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
          return;
        }
        consultationStatus = 'ended';
      }
      if (request.path.endsWith('/incoming')) {
        if (holdIncoming) {
          heldRequest = request;
          heldHandler = handler;
        } else {
          respond(request, handler, {'call': null});
        }
      } else if (request.path.startsWith('/api/im/social-call/')) {
        if (request.method == 'POST') {
          if (failSocialEnd) {
            handler.reject(DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError));
            return;
          }
          socialStatus = 'cancelled';
        }
        respond(request, handler, {
          'id': 7001,
          'status': socialStatus,
          'mode': 'voice',
          'isCaller': true,
          'peer': {'nickname': '账号 A 的通话对象'},
        });
      } else {
        respond(request, handler, {
          'id': 7002,
          'status': consultationStatus,
          'teacherId': 9001,
          'teacher': {'nickname': '隔离测试老师'},
          'paymentMethod': 'coin',
          'mode': 'private',
        });
      }
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('取消普通呼叫完成服务端请求后退出通话页', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const SocialCallPage(callId: 7001))),
                  child: const Text('打开通话'),
                ))));
    await tester.tap(find.text('打开通话'));
    await frames(tester);
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await frames(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(requests.any((r) => r.path == '/api/im/social-call/7001/cancel'),
        isTrue);
    expect(find.text('打开通话'), findsOneWidget);
    expect(find.byType(SocialCallPage), findsNothing);
    await finish(tester);
  });

  testWidgets('普通挂断失败提示重试，不悄悄丢失双方通话记录', (tester) async {
    await open(tester, const SocialCallPage(callId: 7001));
    failSocialEnd = true;
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await frames(tester);
    expect(find.text('挂断尚未确认，请检查网络后重试挂断'), findsOneWidget);
    expect(find.text('重试挂断'), findsOneWidget);
    requests.clear();
    await tester.pump(const Duration(seconds: 5));
    expect(requests, isEmpty);
    failSocialEnd = false;
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await frames(tester);
    expect(
        requests.any((r) => r.path == '/api/im/social-call/7001/end'), isTrue);
    await finish(tester);
  });

  testWidgets('普通通话旧页面切号后停止轮询并清除旧联系人', (tester) async {
    await open(tester, const SocialCallPage(callId: 7001));
    setupApiClientToken('audit-account-b-not-a-real-token');
    requests.clear();
    await tester.pump(const Duration(seconds: 2));
    await frames(tester);
    expect(
      requests.any((request) =>
          request.path == '/api/im/social-call/7001' &&
          request.headers['Authorization'] ==
              'Bearer audit-account-b-not-a-real-token'),
      isFalse,
    );
    expect(find.text('账号 A 的通话对象'), findsNothing);
    expect(find.text('账号已切换，请重新进入当前页面'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('私人专线旧页面切号后停止轮询旧咨询', (tester) async {
    await open(tester, const ConsultationCallPage(sessionId: 7002));
    setupApiClientToken('audit-account-b-not-a-real-token');
    requests.clear();
    await tester.pump(const Duration(seconds: 2));
    await frames(tester);
    expect(
      requests.any((request) =>
          request.path == '/api/consultation/sessions/7002' &&
          request.headers['Authorization'] ==
              'Bearer audit-account-b-not-a-real-token'),
      isFalse,
    );
    await finish(tester);
  });

  testWidgets('退出登录后迟到的普通来电被丢弃', (tester) async {
    holdIncoming = true;
    StartupGate.markReady();
    await open(tester, const SocialCallIncomingHost(child: Text('未登录界面')));
    expect(heldHandler, isNotNull);
    setupApiClientToken(null);
    respond(heldRequest!, heldHandler!, {
      'call': {
        'id': 7003,
        'status': 'ringing',
        'mode': 'voice',
        'peer': {'nickname': '旧账号的私密来电'},
      },
    });
    await frames(tester);
    expect(find.text('旧账号的私密来电'), findsNothing);
    await finish(tester);
  });

  testWidgets('切号后旧来电结果不能覆盖新账号来电状态', (tester) async {
    holdIncoming = true;
    StartupGate.markReady();
    await open(tester, const SocialCallIncomingHost(child: Text('首页')));
    final oldRequest = heldRequest!;
    final oldHandler = heldHandler!;
    holdIncoming = false;
    setupApiClientToken('audit-account-b-not-a-real-token');
    await frames(tester);
    respond(oldRequest, oldHandler, {
      'call': {
        'id': 7003,
        'status': 'ringing',
        'mode': 'voice',
        'peer': {'nickname': '旧账号的私密来电'},
      },
    });
    await frames(tester);
    expect(find.text('旧账号的私密来电'), findsNothing);
    expect(
        requests.any((request) =>
            request.path.endsWith('/incoming') &&
            request.headers['Authorization'] ==
                'Bearer audit-account-b-not-a-real-token'),
        isTrue);
    await finish(tester);
  });

  testWidgets('结束请求失败不重新接回，显示重试且重试成功确认结束', (tester) async {
    await open(tester, const ConsultationCallPage(sessionId: 7002));
    failEnd = true;
    await tester.tap(find.text('取消').last);
    await frames(tester);
    await tester.tap(find.text('确认结束'));
    await frames(tester);
    expect(find.text('结束请求未确认，请检查网络并重试结束'), findsOneWidget);
    expect(find.text('重试结束'), findsOneWidget);
    expect(find.text('重新连接'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await frames(tester);
    expect(
        requests.where((request) =>
            request.path.endsWith('/join') ||
            request.path.endsWith('/heartbeat') ||
            request.path.endsWith('/ready')),
        isEmpty);
    failEnd = false;
    await tester.tap(find.text('重试结束'));
    await frames(tester);
    expect(find.text('结束请求未确认，请检查网络并重试结束'), findsNothing);
    expect(find.text('重试结束'), findsNothing);
    expect(requests.where((request) => request.path.endsWith('/end')),
        hasLength(1));
    await finish(tester);
  });
}
