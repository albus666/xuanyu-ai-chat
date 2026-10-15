import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/pages/voice/voice_match/controller.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/fortune/voice_room_page.dart';
import 'package:xuanyu/features/fortune/matched_voice_overlay.dart';
import 'package:xuanyu/features/community/user_profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceApi implements HttpClientAdapter {
  final requests = <String>[];
  String matchStatus = 'waiting';
  String roomStatus = 'ongoing';
  Completer<ResponseBody>? pendingJoin;
  Completer<ResponseBody>? pendingStatus;
  ResponseBody body(Object data) => ResponseBody.fromString(
        jsonEncode({'code': 0, 'data': data}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(o.path);
    if (o.path == '/api/voice-match/join' && pendingJoin != null)
      return pendingJoin!.future;
    if (o.path == '/api/voice-match/status' && pendingStatus != null)
      return pendingStatus!.future;
    if (o.path.startsWith('/api/voice-match/'))
      return body({'status': matchStatus, 'roomId': 'test-room'});
    if (o.path == '/api/voice-room/join')
      return body({
        'rtcToken': 'fixture',
        'channel': 'test-room',
        'uid': 7,
        'appId': 'fixture-app',
        'peer': {'nickname': '测试好友', 'user_id': 9},
        'match': {'title': '五行同频，容易聊得来', 'reason': '旧提示'},
      });
    if (o.path == '/api/voice-room/status') return body({'status': roomStatus});
    if (o.path == '/api/auth/me') return body({'userId': 7, 'nickname': '自己'});
    if (o.path == '/api/community/user/9/profile')
      return body({'userId': 9, 'nickname': '测试好友', 'following': false});
    return body({});
  }

  @override
  void close({bool force = false}) {}
}

class VoiceRtc extends Fake implements RtcEngine {
  RtcEngineEventHandler? events;
  final calls = <Symbol>[];
  final invocations = <Invocation>[];
  RtcEngineContext? context;
  ChannelMediaOptions? options;
  @override
  void registerEventHandler(RtcEngineEventHandler handler) {
    events = handler;
  }

  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName);
    invocations.add(i);
    if (i.memberName == #initialize)
      context = i.positionalArguments.first as RtcEngineContext;
    if (i.memberName == #joinChannel)
      options = i.namedArguments[#options] as ChannelMediaOptions;
    return Future<void>.value();
  }
}

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
  late VoiceApi api;
  late HttpClientAdapter original;
  setUp(() {
    SharedPreferences.setMockInitialValues({'user_id': 7});
    original = apiClient.httpClientAdapter;
    api = VoiceApi();
    apiClient.httpClientAdapter = api;
  });
  tearDown(() {
    MatchedVoiceOverlay.instance.close();
    apiClient.httpClientAdapter = original;
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> finish(WidgetTester tester, Future<void> operation) async {
    var done = false;
    operation.whenComplete(() => done = true);
    for (var i = 0; i < 100 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done, true, reason: 'API operation did not finish');
    await operation;
  }

  Future<void> room(WidgetTester tester, VoiceRtc Function() factory) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: VoiceRoomPage(
            roomId: 'test-room',
            engineFactory: factory,
            requestMicrophone: () async => true,
          ),
        ),
      ),
    );
    await flush(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  }

  testWidgets('已匹配后关闭匹配页不会取消正在浮窗的通话', (tester) async {
    api.matchStatus = 'matched';
    final completion = Completer<void>();
    final controller = VoiceMatchController(
        requestMicrophone: () async => true,
        openRoom: (_) => completion.future);
    final joining = controller.startMatch();
    await flush(tester);
    controller.onClose();
    await flush(tester);
    expect(api.requests, isNot(contains('/api/voice-match/cancel')));
    completion.complete();
    await joining;
  });

  testWidgets('取消过程中迟到的匹配结果不会重新进房', (tester) async {
    api.pendingJoin = Completer<ResponseBody>();
    var opens = 0;
    final c = VoiceMatchController(
      requestMicrophone: () async => true,
      openRoom: (_) async {
        opens++;
      },
    );
    final started = c.startMatch();
    await flush(tester);
    await finish(tester, c.cancelMatch());
    api.pendingJoin!.complete(
      api.body({'status': 'matched', 'roomId': 'late-room'}),
    );
    await finish(tester, started);
    expect(opens, 0);
    expect(c.state, VoiceMatchState.idle);
    expect(api.requests.where((p) => p.endsWith('/cancel')).length, 2);
    c.onClose();
  });

  testWidgets('匹配过期停止等待并明确提示', (tester) async {
    final c = VoiceMatchController(requestMicrophone: () async => true);
    await finish(tester, c.startMatch());
    expect(c.state, VoiceMatchState.matching);
    api.matchStatus = 'expired';
    await finish(tester, c.pollStatus());
    expect(c.state, VoiceMatchState.idle);
    expect(c.error, contains('匹配已结束'));
    await tester.pump(const Duration(seconds: 4));
    expect(api.requests.where((p) => p.endsWith('/status')).length, 1);
    c.onClose();
  });

  testWidgets('轮询不重叠且匹配成功立即进入房间', (tester) async {
    final entered = Completer<void>();
    final left = Completer<void>();
    final c = VoiceMatchController(
      requestMicrophone: () async => true,
      openRoom: (_) {
        entered.complete();
        return left.future;
      },
    );
    await finish(tester, c.startMatch());
    api.pendingStatus = Completer<ResponseBody>();
    final first = c.pollStatus();
    await flush(tester);
    await finish(tester, c.pollStatus());
    expect(api.requests.where((p) => p.endsWith('/status')).length, 1);
    api.pendingStatus!.complete(
      api.body({'status': 'matched', 'roomId': 'ready'}),
    );
    await flush(tester);
    expect(entered.isCompleted, true);
    left.complete();
    await finish(tester, first);
    c.onClose();
  });

  testWidgets('只在对方进频道后显示通话并计时，重连恢复状态', (tester) async {
    final rtc = VoiceRtc();
    await room(tester, () => rtc);
    expect(rtc.context!.appId, 'fixture-app');
    expect(
        rtc.calls,
        containsAll([
          #enableAudio,
          #muteAllRemoteAudioStreams,
          #adjustPlaybackSignalVolume,
          #adjustRecordingSignalVolume
        ]));
    expect(rtc.options!.publishMicrophoneTrack, true);
    expect(rtc.options!.autoSubscribeAudio, true);
    const conn = RtcConnection(channelId: 'test-room', localUid: 7);
    rtc.events!.onJoinChannelSuccess!(conn, 0);
    await flush(tester);
    expect(rtc.calls, contains(#setEnableSpeakerphone));
    expect(find.text('等待对方接通…'), findsOneWidget);
    expect(find.textContaining('通话中'), findsNothing);
    rtc.events!.onUserJoined!(conn, 9, 0);
    await flush(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('通话中 00:02'), findsOneWidget);
    rtc.events!.onUserOffline!(
      conn,
      9,
      UserOfflineReasonType.userOfflineDropped,
    );
    await flush(tester);
    expect(find.text('对方已离开或掉线'), findsOneWidget);
    rtc.events!.onUserJoined!(conn, 9, 0);
    await flush(tester);
    expect(find.textContaining('通话中'), findsOneWidget);
    rtc.events!.onRequestToken!(conn);
    await flush(tester);
    expect(rtc.calls, contains(#renewToken));
    await close(tester);
    expect(rtc.calls, containsAll([#leaveChannel, #release]));
    expect(api.requests, contains('/api/voice-room/leave'));
  });

  testWidgets('超时释放引擎且不再显示重试，迟到回调不能重开连接', (tester) async {
    final old = VoiceRtc();
    await room(tester, () => old);
    await tester.pump(const Duration(seconds: 21));
    await flush(tester);
    expect(find.textContaining('连接超时'), findsOneWidget);
    expect(old.calls, contains(#release));
    expect(find.text('重试'), findsNothing);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    old.events!.onJoinChannelSuccess!(const RtcConnection(), 0);
    await flush(tester);
    expect(find.textContaining('连接超时'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    await close(tester);
  });

  testWidgets('服务端结束房间后停止音频并提示返回', (tester) async {
    final rtc = VoiceRtc();
    await room(tester, () => rtc);
    rtc.events!.onJoinChannelSuccess!(const RtcConnection(), 0);
    await flush(tester);
    api.roomStatus = 'ended';
    await tester.pump(const Duration(seconds: 3));
    await flush(tester);
    expect(find.text('对方已结束通话，请返回重新匹配'), findsOneWidget);
    expect(rtc.calls, contains(#release));
    await close(tester);
  });
  testWidgets('语音只显示双头像、关注和浮窗，音频处理在切换设备后保留', (tester) async {
    final rtc = VoiceRtc();
    await room(tester, () => rtc);
    const conn = RtcConnection(channelId: 'test-room', localUid: 7);
    rtc.events!.onJoinChannelSuccess!(conn, 0);
    rtc.events!.onUserJoined!(conn, 9, 0);
    await flush(tester);
    expect(find.byType(CircleAvatar), findsNWidgets(2));
    expect(find.text('一对一语音'), findsNothing);
    expect(find.text('私聊'), findsNothing);
    expect(find.text('主页'), findsNothing);
    expect(find.textContaining('五行同频'), findsNothing);
    expect(rtc.context!.audioScenario, AudioScenarioType.audioScenarioMeeting);
    final parameters =
        rtc.invocations.where((i) => i.memberName == #setParameters);
    expect(parameters.first.positionalArguments.first,
        contains('"che.audio.aec.enable":true'));
    expect(
        rtc.invocations
            .where((i) => i.memberName == #enableInEarMonitoring)
            .every((i) => i.namedArguments[#enabled] == false),
        true);
    final before = parameters.length;
    rtc.events!.onAudioRoutingChanged!(3);
    await flush(tester);
    expect(rtc.invocations.where((i) => i.memberName == #setParameters).length,
        greaterThan(before));
    // A duplicate local stream is never treated as the other participant.
    rtc.events!.onUserJoined!(conn, 7, 0);
    await flush(tester);
    rtc.events!.onUserOffline!(
        conn, 7, UserOfflineReasonType.userOfflineDropped);
    await flush(tester);
    expect(find.textContaining('通话中'), findsOneWidget);
    await close(tester);
  });

  testWidgets('打开主页自动浮窗，恢复复用通话，系统返回需要确认', (tester) async {
    final rtc = VoiceRtc();
    final rootKey = GlobalKey<NavigatorState>();
    final overlay = MatchedVoiceOverlay.instance;
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
              navigatorKey: rootKey,
              navigatorObservers: [MatchedVoiceBackNavigatorObserver()],
              home: const Scaffold(body: Text('匹配页')),
              builder: (_, child) => MatchedVoiceOverlayHost(
                  rootNavigatorKey: rootKey,
                  engineFactory: () => rtc,
                  requestMicrophone: () async => true,
                  child: child!),
            )));
    unawaited(overlay.open('test-room'));
    await flush(tester);
    const conn = RtcConnection(channelId: 'test-room', localUid: 7);
    rtc.events!.onJoinChannelSuccess!(conn, 0);
    rtc.events!.onUserJoined!(conn, 9, 0);
    await flush(tester);
    await tester.tap(find.byTooltip('浮窗'));
    await flush(tester);
    expect(overlay.minimized, true);
    expect(rtc.calls, isNot(contains(#release)));
    await tester.tap(find.byType(CircleAvatar));
    await flush(tester);
    expect(overlay.minimized, false);
    await tester.tap(find.byType(CircleAvatar).last);
    await flush(tester);
    expect(overlay.minimized, true);
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(rtc.calls, isNot(contains(#leaveChannel)));
    overlay.restore();
    await flush(tester);
    await rootKey.currentState!.maybePop();
    await flush(tester);
    expect(find.text('是否退出语音聊天？'), findsOneWidget);
    await tester.tap(find.text('继续通话'));
    await flush(tester);
    expect(overlay.roomId, 'test-room');
    expect(overlay.minimized, true);
    expect(rtc.calls.where((c) => c == #joinChannel).length, 1);
    overlay.restore();
    await flush(tester);
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await flush(tester);
    expect(rtc.calls, isNot(contains(#leaveChannel)));
    await tester.tap(find.text('退出'));
    await flush(tester);
    expect(overlay.roomId, isNull);
    expect(rtc.calls.where((c) => c == #release).length, 1);
    await close(tester);
  });
}
