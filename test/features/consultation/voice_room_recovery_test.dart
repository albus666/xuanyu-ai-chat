import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/voice_plaza_room_page.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';

class FakeRoomRtc extends Fake implements RtcEngine {
  final calls = <String>[];
  RtcEngineEventHandler? events;
  Completer<void>? initializeWait;
  final enabledLocalAudio = <bool>[];
  final localMuted = <bool>[];
  final mediaOptions = <ChannelMediaOptions>[];
  @override
  void registerEventHandler(RtcEngineEventHandler eventHandler) {
    events = eventHandler;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    if (invocation.memberName == #updateChannelMediaOptions) {
      mediaOptions
          .add(invocation.positionalArguments.single as ChannelMediaOptions);
    }
    if (invocation.memberName == #muteLocalAudioStream) {
      localMuted.add(invocation.positionalArguments.single as bool);
    }
    if (invocation.memberName == #enableLocalAudio) {
      enabledLocalAudio.add(invocation.positionalArguments.single as bool);
    }
    if (invocation.memberName == #initialize && initializeWait != null) {
      return initializeWait!.future;
    }
    if (invocation.memberName == #joinChannel) {
      scheduleMicrotask(() => events?.onJoinChannelSuccess
          ?.call(const RtcConnection(channelId: 'mock-room', localUid: 7), 0));
    }
    return Future<void>.value();
  }

  int count(String name) => calls.where((c) => c == 'Symbol("$name")').length;
}

class FakeRoomSocket extends Fake implements WebSocket {
  final events = StreamController<dynamic>();
  bool closed = false;
  @override
  set pingInterval(Duration? value) {}
  @override
  StreamSubscription<dynamic> listen(void Function(dynamic)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      events.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    if (!events.isClosed) unawaited(events.close());
  }
}

void main() {
  final overlay = VoiceRoomOverlayController.instance;
  late InterceptorsWrapper interceptor;
  late Map<String, dynamic> room;
  late List<Map<String, dynamic>> messages;
  late FakeRoomRtc rtc;
  late List<FakeRoomSocket> sockets;
  late List<RequestOptions> calls;
  late List<bool> serviceCalls;
  void Function(RequestOptions, RequestInterceptorHandler)? detailOverride;
  void Function(RequestOptions, RequestInterceptorHandler)? joinOverride;
  void Function(RequestOptions, RequestInterceptorHandler)? leaveOverride;
  Completer<WebSocket>? socketWait;
  Completer<Map<int, int>>? permissionWait;
  const permissionChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  void ok(RequestOptions r, RequestInterceptorHandler h, Object? data) =>
      h.resolve(Response(
          requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));
  void denied(RequestOptions r, RequestInterceptorHandler h, int code) =>
      h.resolve(Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': code, 'message': '模拟房间不可用'}));
  Map<String, dynamic> msg(int id) => {
        'id': id,
        'userId': 7,
        'nickname': '测试成员',
        'type': 'text',
        'content': '补回消息$id',
        'isMe': false,
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'visible',
      };
  Map<String, dynamic> getJoin() => {
        'rtcToken': 'fake-test-only',
        'channel': 'mock-room',
        'uid': 7,
        'publisher': (room['members'] as List).any((m) =>
            m['isMe'] == true &&
            (m['role'] == 'owner' || m['micStatus'] == 'speaking')),
      };

  setUp(() {
    if (overlay.roomId != null) overlay.didClose(overlay.roomId!);
    apiClient.options.headers['Authorization'] = 'Bearer fake-room-a';
    room = {
      'id': 1,
      'title': '恢复测试房间',
      'status': 'live',
      'roomType': 'party',
      'members': [
        {
          'userId': 7,
          'isMe': true,
          'role': 'listener',
          'nickname': '本人测试',
          'micStatus': 'none'
        }
      ],
      'owner': {'nickname': '测试房主'},
    };
    messages = [msg(1)];
    rtc = FakeRoomRtc();
    sockets = [];
    calls = [];
    serviceCalls = [];
    detailOverride = null;
    joinOverride = null;
    leaveOverride = null;
    socketWait = null;
    permissionWait = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'requestPermissions') {
        return permissionWait?.future ?? Future.value(<int, int>{7: 1});
      }
      return 1;
    });
    interceptor = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      if (r.path.endsWith('/messages')) {
        final after = r.queryParameters['after_id'] as int? ?? 0;
        return ok(r, h, {
          'list': messages
              .where((m) => (m['id'] as int) > after)
              .take(100)
              .toList(),
          'revokedIds': <int>[]
        });
      }
      if (r.path.endsWith('/join')) {
        if (joinOverride != null) return joinOverride!(r, h);
        return ok(r, h, getJoin());
      }
      if (r.path.endsWith('/leave')) {
        if (leaveOverride != null) return leaveOverride!(r, h);
        return ok(r, h, {});
      }
      if (r.path == '/api/consultation/rooms/1') {
        if (detailOverride != null) return detailOverride!(r, h);
        return ok(r, h, Map<String, dynamic>.from(room));
      }
      h.reject(DioException(requestOptions: r, error: 'unexpected mock path'));
    });
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    apiClient.interceptors.remove(interceptor);
    apiClient.options.headers.remove('Authorization');
    if (overlay.roomId != null) overlay.didClose(overlay.roomId!);
    for (final socket in sockets) {
      await socket.close();
    }
  });
  Future<void> frames(WidgetTester t, {int count = 10}) async {
    for (var i = 0; i < count; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester t) async {
    overlay.open(1);
    await t.pumpWidget(MaterialApp(
        home: VoicePlazaRoomPage(
      roomId: 1,
      rtcEngineFactory: () => rtc,
      audioServiceUpdater: (active, _) async => serviceCalls.add(active),
      roomEventsConnector: (_, __) async {
        if (socketWait != null) return socketWait!.future;
        final socket = FakeRoomSocket();
        sockets.add(socket);
        return socket;
      },
    )));
    await frames(t);
  }

  Future<void> resume(WidgetTester t) async {
    testerState(t).didChangeAppLifecycleState(AppLifecycleState.resumed);
    await frames(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  testWidgets('公开咨询显示全部余额可用时间，预冻结补充不让秒数跳高', (t) async {
    room['mySession'] = {
      'status': 'active',
      'paymentMethod': 'coin',
      'viewerRole': 'user',
      'billedSeconds': 20,
      'remainingSeconds': 60,
      'walletRemainingSeconds': 50108,
    };
    await open(t);
    expect(find.text('公开连麦中 · 20秒 · 余额约50108秒'), findsOneWidget);
    expect(find.text('余额不足两分钟，请及时充值'), findsNothing);
    room['mySession'] = {
      ...Map<String, dynamic>.from(room['mySession'] as Map),
      'remainingSeconds': 360,
      'walletRemainingSeconds': 50107,
    };
    await resume(t);
    expect(find.textContaining('余额约50107秒'), findsOneWidget);
    await finish(t);
  });

  testWidgets('公开咨询不足两分钟显示充值入口，充值后撤下提醒', (t) async {
    room['mySession'] = {
      'status': 'active',
      'paymentMethod': 'coin',
      'viewerRole': 'user',
      'billedSeconds': 20,
      'remainingSeconds': 60,
      'walletRemainingSeconds': 119,
    };
    await open(t);
    expect(find.text('余额不足两分钟，请及时充值'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '充值'), findsOneWidget);
    room['mySession'] = {
      ...Map<String, dynamic>.from(room['mySession'] as Map),
      'walletRemainingSeconds': 720,
    };
    await resume(t);
    expect(find.text('余额不足两分钟，请及时充值'), findsNothing);
    await finish(t);
  });

  testWidgets('房间音频路由切换恢复3A，释放后迟到回调不改旧引擎', (t) async {
    await open(t);
    final profiles = rtc.count('setAudioProfile');
    final before = rtc.count('setParameters');
    final routeChanged = rtc.events!.onAudioRoutingChanged!;
    routeChanged(3);
    await frames(t);
    expect(rtc.count('setParameters'), before + 1);
    expect(rtc.count('setAudioProfile'), profiles);
    await finish(t);
    final disposed = rtc.count('setParameters');
    routeChanged(3);
    await frames(t);
    expect(rtc.count('setParameters'), disposed);
  });

  for (final publisher in [false, true]) {
    testWidgets('${publisher ? '上麦' : '旁听'}入房明确恢复播放和发布状态', (t) async {
      if (publisher) (room['members'] as List).first['role'] = 'owner';
      await open(t);
      expect(rtc.enabledLocalAudio.last, publisher);
      expect(rtc.localMuted.last, true);
      expect(rtc.count('muteAllRemoteAudioStreams'), greaterThan(0));
      expect(rtc.count('setEnableSpeakerphone'), greaterThan(0));
      expect(rtc.count('adjustPlaybackSignalVolume'), greaterThan(0));
      await finish(t);
    });
  }
  testWidgets('切号清空房间成员消息并断开RTC与事件连接', (t) async {
    await open(t);
    expect(rtc.count('joinChannel'), 1);
    apiClient.options.headers['Authorization'] = 'Bearer fake-room-b';
    apiSessionChanges.value++;
    await frames(t);
    expect(find.text('恢复测试房间'), findsNothing);
    expect(find.textContaining('补回消息1'), findsNothing);
    expect(overlay.hasActiveRoom, isFalse);
    expect(rtc.count('release'), 1);
    expect(sockets.single.closed, isTrue);
    final before = calls.length;
    await resume(t);
    expect(calls.length, before);
    await finish(t);
  });
  testWidgets('WS重连成功立即补回断网期间消息不等15秒轮询', (t) async {
    await open(t);
    messages.add(msg(2));
    await sockets.first.close();
    await t.pump(const Duration(seconds: 1));
    await frames(t);
    expect(sockets.length, 2);
    expect(find.byKey(const ValueKey('room-message-2')), findsOneWidget);
    await finish(t);
  });
  testWidgets('消息一次超过100条恢复时连续补页', (t) async {
    await open(t);
    messages = List.generate(205, (i) => msg(i + 1));
    await resume(t);
    expect(
        calls.where((r) =>
            r.path.endsWith('/messages') &&
            r.queryParameters['after_id'] == 201),
        isNotEmpty);
    await finish(t);
  });
  testWidgets('resume等待进行中的权威刷新后才恢复音频', (t) async {
    await open(t);
    final blocked = <(RequestOptions, RequestInterceptorHandler)>[];
    detailOverride = (r, h) => blocked.add((r, h));
    await t.pump(const Duration(seconds: 15));
    final before = rtc.count('enableAudio');
    await resume(t);
    expect(rtc.count('enableAudio'), before, reason: '权威房间状态未返回不能恢复旧音频');
    detailOverride = null;
    room['status'] = 'closed';
    for (final call in blocked) {
      ok(call.$1, call.$2, room);
    }
    await frames(t);
    expect(overlay.hasActiveRoom, isFalse);
    expect(rtc.count('enableAudio'), before);
    await finish(t);
  });
  testWidgets('权威详情业务403清除不可见房间并停止恢复', (t) async {
    await open(t);
    detailOverride = (r, h) => denied(r, h, 403);
    await resume(t);
    expect(overlay.hasActiveRoom, isFalse);
    expect(find.text('恢复测试房间'), findsNothing);
    expect(rtc.count('release'), 1);
    await finish(t);
  });
  testWidgets('退出业务失败不关闭悬浮房间可重试', (t) async {
    await open(t);
    leaveOverride = (r, h) => denied(r, h, 409);
    var leaving = overlay.requestClose();
    await frames(t);
    await leaving;
    expect(overlay.hasActiveRoom, isTrue);
    expect(rtc.count('release'), 0);
    leaveOverride = null;
    leaving = overlay.requestClose();
    await frames(t);
    await leaving;
    expect(overlay.hasActiveRoom, isFalse);
    await finish(t);
  });
  testWidgets('私人通话暂停房间音频后resume不擅自重连', (t) async {
    await open(t);
    expect(await overlay.suspendAudio(), isTrue);
    final before = calls.where((r) => r.path.endsWith('/join')).length;
    await resume(t);
    expect(calls.where((r) => r.path.endsWith('/join')).length, before);
    final resuming = overlay.resumeAudio();
    await frames(t);
    await resuming;
    expect(calls.where((r) => r.path.endsWith('/join')).length, before + 1);
    await finish(t);
  });
  testWidgets('缩小再恢复不发送leave不重复加入RTC', (t) async {
    await open(t);
    final joins = calls.where((r) => r.path.endsWith('/join')).length;
    overlay.minimize();
    overlay.restore();
    await resume(t);
    expect(calls.where((r) => r.path.endsWith('/leave')), isEmpty);
    expect(calls.where((r) => r.path.endsWith('/join')).length, joins);
    expect(rtc.count('joinChannel'), 1);
    await finish(t);
  });
  testWidgets('切号后迟到join不会创建RTC或重启事件连接', (t) async {
    late RequestOptions request;
    late RequestInterceptorHandler handler;
    joinOverride = (r, h) {
      request = r;
      handler = h;
    };
    await open(t);
    apiClient.options.headers['Authorization'] = 'Bearer fake-room-b';
    apiSessionChanges.value++;
    ok(request, handler, getJoin());
    await frames(t);
    expect(rtc.count('initialize'), 0);
    expect(sockets, isEmpty);
    expect(find.text('恢复测试房间'), findsNothing);
    await finish(t);
  });
  testWidgets('切号后迟到WebSocket立即关闭不回挂', (t) async {
    socketWait = Completer<WebSocket>();
    await open(t);
    apiClient.options.headers['Authorization'] = 'Bearer fake-room-b';
    apiSessionChanges.value++;
    final delayed = FakeRoomSocket();
    sockets.add(delayed);
    socketWait!.complete(delayed);
    await frames(t);
    expect(delayed.closed, isTrue);
    expect(rtc.count('release'), 1);
    await finish(t);
  });
  testWidgets('旧房间迟到关闭响应不能关掉新打开的同ID房间', (t) async {
    await open(t);
    late RequestOptions request;
    late RequestInterceptorHandler handler;
    detailOverride = (r, h) {
      request = r;
      handler = h;
    };
    await t.pump(const Duration(seconds: 15));
    overlay.didClose(1);
    overlay.open(1);
    ok(request, handler, {...room, 'status': 'closed'});
    await frames(t);
    expect(overlay.hasActiveRoom, isTrue);
    await finish(t);
  });
  testWidgets('并发点击退出只发一次leave', (t) async {
    await open(t);
    late RequestOptions request;
    late RequestInterceptorHandler handler;
    leaveOverride = (r, h) {
      request = r;
      handler = h;
    };
    final first = overlay.requestClose();
    final second = overlay.requestClose();
    await frames(t);
    expect(calls.where((r) => r.path.endsWith('/leave')).length, 1);
    ok(request, handler, {});
    await frames(t);
    await first;
    await second;
    await finish(t);
  });
  testWidgets('恢复发现被移出房间立即释放RTC且不重新join', (t) async {
    await open(t);
    final joins = calls.where((r) => r.path.endsWith('/join')).length;
    room['members'] = <dynamic>[];
    await resume(t);
    expect(overlay.hasActiveRoom, isFalse);
    expect(rtc.count('release'), 1);
    expect(calls.where((r) => r.path.endsWith('/join')).length, joins);
    expect(find.text('恢复测试房间'), findsNothing);
    await finish(t);
  });
  testWidgets('恢复详情网络失败不使用旧数据重启RTC下一次可重试', (t) async {
    await open(t);
    final before = rtc.count('enableAudio');
    detailOverride = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await resume(t);
    expect(rtc.count('enableAudio'), before);
    expect(overlay.hasActiveRoom, isTrue);
    detailOverride = null;
    await resume(t);
    expect(rtc.count('enableAudio'), greaterThan(before));
    await finish(t);
  });
  testWidgets('初次房间读取失败有真实重试且仅成功后加入RTC', (t) async {
    detailOverride = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await open(t);
    expect(rtc.count('joinChannel'), 0);
    expect(find.text('重试加载'), findsOneWidget);
    detailOverride = null;
    await t.tap(find.text('重试加载'));
    await frames(t);
    expect(rtc.count('joinChannel'), 1);
    expect(find.text('恢复测试房间'), findsOneWidget);
    await finish(t);
  });
  testWidgets('旧页面dispose不会停止新一代同ID房间音频服务', (t) async {
    await open(t);
    expect(serviceCalls.last, isTrue);
    overlay.didClose(1);
    overlay.open(1);
    final before = serviceCalls.length;
    await finish(t);
    expect(serviceCalls.length, before);
    expect(overlay.hasActiveRoom, isTrue);
    expect(rtc.count('release'), 1);
  });
  testWidgets('新一代同ID房间已开时旧账号清理不停止新音频服务', (t) async {
    await open(t);
    overlay.didClose(1);
    overlay.open(1);
    final before = serviceCalls.length;
    apiSessionChanges.value++;
    await frames(t);
    expect(serviceCalls.length, before);
    expect(overlay.hasActiveRoom, isTrue);
    expect(rtc.count('release'), 1);
    await finish(t);
  });
  testWidgets('RTC初始化迟到不能在切号后继续加入频道', (t) async {
    rtc.initializeWait = Completer<void>();
    await open(t);
    expect(rtc.count('initialize'), 1);
    apiSessionChanges.value++;
    rtc.initializeWait!.complete();
    await frames(t);
    expect(rtc.count('joinChannel'), 0);
    expect(serviceCalls.where((active) => active), isEmpty);
    expect(rtc.count('release'), 1);
    await finish(t);
  });
  testWidgets('续期返回听众凭证立即停止旧麦克风发流', (t) async {
    (room['members'] as List).first['role'] = 'owner';
    await open(t);
    final joins = rtc.count('joinChannel');
    joinOverride = (r, h) => ok(r, h, {...getJoin(), 'publisher': false});
    rtc.events!.onRequestToken!(const RtcConnection());
    await frames(t);
    expect(rtc.count('renewToken'), 1);
    expect(rtc.enabledLocalAudio.last, isFalse);
    expect(rtc.mediaOptions.last.publishMicrophoneTrack, isFalse);
    expect(rtc.mediaOptions.last.clientRoleType,
        ClientRoleType.clientRoleAudience);
    expect(rtc.count('joinChannel'), joins);
    await finish(t);
  });
  testWidgets('续期请求迟到不会将旧token写入切号后连接', (t) async {
    await open(t);
    late RequestOptions request;
    late RequestInterceptorHandler handler;
    joinOverride = (r, h) {
      request = r;
      handler = h;
    };
    rtc.events!.onRequestToken!(const RtcConnection());
    await frames(t);
    apiClient.options.headers['Authorization'] = 'Bearer fake-room-b';
    apiSessionChanges.value++;
    ok(request, handler, getJoin());
    await frames(t);
    expect(request.headers['Authorization'], 'Bearer fake-room-a');
    expect(rtc.count('renewToken'), 0);
    expect(rtc.count('release'), 1);
    await finish(t);
  });
  testWidgets('重复resume只共用一次权威恢复请求不重复join', (t) async {
    await open(t);
    late RequestOptions request;
    late RequestInterceptorHandler handler;
    var detailCount = 0;
    detailOverride = (r, h) {
      detailCount++;
      request = r;
      handler = h;
    };
    testerState(t).didChangeAppLifecycleState(AppLifecycleState.resumed);
    testerState(t).didChangeAppLifecycleState(AppLifecycleState.resumed);
    await frames(t);
    expect(detailCount, 1);
    detailOverride = null;
    ok(request, handler, room);
    await frames(t);
    expect(rtc.count('joinChannel'), 1);
    await finish(t);
  });
  testWidgets('慢网跨过两次轮询只追赶一轮避免resume无限等待', (t) async {
    await open(t);
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    detailOverride = (r, h) => pending.add((r, h));
    final before = rtc.count('enableAudio');
    await resume(t);
    expect(pending.length, 1);

    // 第一轮耗时超过15秒，轮询要求再读一次最新状态。
    await t.pump(const Duration(seconds: 16));
    ok(pending[0].$1, pending[0].$2, {...room, 'title': '慢网第一轮'});
    await frames(t);
    expect(pending.length, 2);
    expect(rtc.count('enableAudio'), before);

    // 追赶轮也超过15秒，不能因此不断续接第三、第四轮饿死resume。
    await t.pump(const Duration(seconds: 16));
    ok(pending[1].$1, pending[1].$2, {...room, 'title': '慢网最新权威状态'});
    await frames(t);
    expect(pending.length, 2);
    expect(find.text('慢网最新权威状态'), findsOneWidget);
    expect(rtc.count('enableAudio'), before + 1);

    // 未跟上的变更由后续正常轮询接手，不能永久停止同步。
    await t.pump(const Duration(seconds: 15));
    expect(pending.length, 3);
    detailOverride = null;
    ok(pending[2].$1, pending[2].$2, {...room, 'title': '后续轮询仍更新'});
    await frames(t);
    expect(find.text('后续轮询仍更新'), findsOneWidget);
    await finish(t);
  });
  testWidgets('恢复权威席位已下麦时只切听众不继续旧发言身份', (t) async {
    (room['members'] as List).first['role'] = 'owner';
    await open(t);
    expect(rtc.count('joinChannel'), 1);
    (room['members'] as List).first['role'] = 'listener';
    await resume(t);
    expect(rtc.enabledLocalAudio.last, isFalse);
    expect(rtc.count('renewToken'), 1);
    expect(rtc.count('joinChannel'), 1);
    await finish(t);
  });
  testWidgets('麦克风授权弹窗期间切号后不再join或启动RTC', (t) async {
    (room['members'] as List).first['role'] = 'owner';
    permissionWait = Completer<Map<int, int>>();
    await open(t);
    apiSessionChanges.value++;
    permissionWait!.complete({7: 1});
    await frames(t);
    expect(calls.where((r) => r.path.endsWith('/join')), isEmpty);
    expect(rtc.count('initialize'), 0);
    await finish(t);
  });
  testWidgets('结束房间确认弹窗切号后确认不借新账号离房', (t) async {
    (room['members'] as List).first['role'] = 'owner';
    await open(t);
    final leaving = overlay.requestClose();
    await frames(t);
    expect(find.text('结束房间？'), findsOneWidget);
    apiClient.options.headers['Authorization'] = 'Bearer fake-room-b';
    apiSessionChanges.value++;
    await frames(t);
    await t.tap(find.text('结束'));
    await frames(t);
    await leaving;
    expect(calls.where((r) => r.path.endsWith('/leave')), isEmpty);
    await finish(t);
  });
}

WidgetsBindingObserver testerState(WidgetTester tester) =>
    tester.state(find.byType(VoicePlazaRoomPage)) as WidgetsBindingObserver;
