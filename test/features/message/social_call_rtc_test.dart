import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/social_call_page.dart';
import 'package:xuanyu/features/consultation/consultation_call_page.dart';

class SpeechRtc extends Fake implements RtcEngine {
  RtcEngineEventHandler? events;
  final methods = <Symbol>[];
  final parameters = <String>[];
  RtcEngineContext? context;
  ChannelMediaOptions? options;
  @override
  void registerEventHandler(RtcEngineEventHandler handler) => events = handler;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    methods.add(invocation.memberName);
    if (invocation.memberName == #setParameters) {
      parameters.add(invocation.positionalArguments.first as String);
    }
    if (invocation.memberName == #initialize) {
      context = invocation.positionalArguments.first as RtcEngineContext;
    }
    if (invocation.memberName == #joinChannel) {
      options = invocation.namedArguments[#options] as ChannelMediaOptions;
    }
    if (invocation.memberName == #setEnableSpeakerphone) {
      return Future<void>.error(StateError('设备拒绝扬声器切换'));
    }
    return Future<void>.value();
  }
}

class HangingSpeechRtc extends SpeechRtc {
  final shutdown = Completer<void>();
  @override
  Future<void> leaveChannel({LeaveChannelOptions? options}) => shutdown.future;
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
  testWidgets('对方结束语音后不等待挂起的原生释放，立即关闭浮层', (tester) async {
    final rtc = HangingSpeechRtc();
    var ended = false;
    var closes = 0;
    final interceptor = InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {
        'code': 0,
        'data': {
          'status': ended ? 'ended' : 'accepted',
          'type': 'voice',
          'rtcToken': 'fixture',
          'channel': 'fixture',
          'uid': 7,
          'appId': 'fixture',
          'peer': {'nickname': '测试好友'}
        }
      }));
    });
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        home: SocialCallPage(
      callId: 11,
      engineFactory: () => rtc,
      requestMicrophone: () async => true,
      onSessionEnded: () => closes++,
    )));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byTooltip('返回'), findsOneWidget);
    ended = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(closes, 1);
    expect(rtc.shutdown.isCompleted, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    rtc.shutdown.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  for (final role in ['teacher', 'user']) {
    testWidgets('老师发起时$role端不会自动接听或加入语音', (tester) async {
      final rtc = SpeechRtc();
      var accepted = false;
      final paths = <String>[];
      final interceptor = InterceptorsWrapper(onRequest: (r, h) {
        paths.add(r.path);
        if (r.path.endsWith('/accept')) accepted = true;
        final session = {
          'id': 51,
          'status': accepted ? 'accepted' : 'waiting',
          'mode': 'private',
          'initiatorRole': 'teacher',
          'viewerRole': role,
          'isCaller': role == 'teacher',
          'canAnswer': !accepted && role == 'user',
          'paymentMethod': 'coin'
        };
        h.resolve(Response(requestOptions: r, statusCode: 200, data: {
          'code': 0,
          'data': r.path.endsWith('/join')
              ? {
                  'session': session,
                  'rtcToken': 'fixture',
                  'channel': 'fixture',
                  'uid': 7,
                  'appId': 'fixture'
                }
              : session
        }));
      });
      apiClient.interceptors.insert(0, interceptor);
      addTearDown(() => apiClient.interceptors.remove(interceptor));
      await tester.pumpWidget(MaterialApp(
          home: ConsultationCallPage(
              sessionId: 51,
              engineFactory: () => rtc,
              requestMicrophone: () async => true)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(paths.where((p) => p.endsWith('/accept') || p.endsWith('/join')),
          isEmpty);
      expect(rtc.methods, isNot(contains(#joinChannel)));
      if (role == 'user') {
        expect(find.text('拒绝'), findsOneWidget);
        await tester.tap(find.text('接听'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(paths.where((p) => p.endsWith('/accept')), hasLength(1));
        expect(rtc.methods, contains(#joinChannel));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('私人专线音频接通后才确认就绪，扬声器失败不阻止就绪', (tester) async {
    final rtc = SpeechRtc();
    final requests = <RequestOptions>[];
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      final session = {
        'id': 51,
        'status': 'accepted',
        'mode': 'private',
        'paymentMethod': 'coin',
        'teacherId': 9,
        'teacher': {'nickname': '测试老师'}
      };
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/join')
            ? {
                'session': session,
                'rtcToken': 'fixture',
                'channel': 'private-test',
                'uid': 7,
                'appId': 'fixture-app'
              }
            : session
      }));
    });
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        home: ConsultationCallPage(
      sessionId: 51,
      engineFactory: () => rtc,
      requestMicrophone: () async => true,
    )));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(rtc.methods, contains(#joinChannel));
    final profiles = rtc.methods.where((m) => m == #setAudioProfile).length;
    rtc.events!.onAudioRoutingChanged!(3);
    await tester.pump();
    expect(rtc.methods.where((m) => m == #setAudioProfile).length, profiles);
    expect(rtc.parameters.last, contains('"che.audio.agc.enable":true'));

    expect(requests.where((r) => r.path.endsWith('/ready')), isEmpty);
    expect(requests.singleWhere((r) => r.path.endsWith('/join')).data,
        {'deferredReady': true});
    rtc.events!.onJoinChannelSuccess!(
        const RtcConnection(channelId: 'private-test', localUid: 7), 0);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requests.where((r) => r.path.endsWith('/ready')), hasLength(1));
    expect(rtc.methods.where((m) => m == #setAudioProfile), hasLength(1));
    expect(rtc.methods.where((m) => m == #setAINSMode), hasLength(1));
    expect(rtc.methods, isNot(contains(#setVoiceBeautifierPreset)));
    expect(rtc.methods, isNot(contains(#setAudioEffectPreset)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('对方主动挂断立即结束且不显示重连', (tester) async {
    final rtc = SpeechRtc();
    var ended = false;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/end')) ended = true;
      final session = {
        'id': 51,
        'status': ended ? 'ended' : 'active',
        'mode': 'private',
        'endReason': ended ? 'peer_ended' : '',
        'paymentMethod': 'coin'
      };
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/join')
            ? {
                'session': session,
                'rtcToken': 'fixture',
                'channel': 'fixture',
                'uid': 7,
                'appId': 'fixture'
              }
            : session
      }));
    });
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        home: ConsultationCallPage(
            sessionId: 51,
            engineFactory: () => rtc,
            requestMicrophone: () async => true)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    rtc.events!.onUserOffline!(
        const RtcConnection(), 9, UserOfflineReasonType.userOfflineQuit);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(ended, isTrue);
    expect(find.text('对方已经挂断'), findsOneWidget);
    expect(find.text('重新连接'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('老师从等待中的预约进入专线会先接听再加入音频', (tester) async {
    final rtc = SpeechRtc();
    final paths = <String>[];
    var accepted = false;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      if (request.path.endsWith('/accept')) accepted = true;
      final session = {
        'id': 51,
        'viewerRole': 'teacher',
        'status': accepted ? 'accepted' : 'waiting',
        'mode': 'private',
        'paymentMethod': 'coin',
        'teacherId': 9
      };
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/join')
            ? {
                'session': session,
                'rtcToken': 'fixture',
                'channel': 'private-test',
                'uid': 9,
                'appId': 'fixture-app'
              }
            : session,
      }));
    });
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        home: ConsultationCallPage(
            sessionId: 51,
            engineFactory: () => rtc,
            requestMicrophone: () async => true)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(paths.where((p) => p.endsWith('/accept')), hasLength(1));
    expect(paths.indexOf('/api/consultation/sessions/51/accept'),
        lessThan(paths.indexOf('/api/consultation/sessions/51/join')));
    expect(rtc.methods, contains(#joinChannel));
    expect(find.textContaining('正在等待老师'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['voice', 'video']) {
    testWidgets('$mode 接听先加入频道，扬声器切换失败不会中断通话', (tester) async {
      final rtc = SpeechRtc();
      var minimized = false;
      Future<void> Function()? requestBack;
      final serviceCalls = <MethodCall>[];
      const service = MethodChannel('xuanyu/voice_room_audio');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(service,
          (call) async {
        serviceCalls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(service, null));
      final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {
            'id': 1,
            'status': 'accepted',
            'mode': mode,
            'rtcToken': 'test-fixture',
            'channel': 'test-channel',
            'uid': 7,
            'appId': 'test-app',
            'peer': {'nickname': '测试好友'},
          }
        }));
      });
      apiClient.interceptors.insert(0, interceptor);
      addTearDown(() => apiClient.interceptors.remove(interceptor));
      await tester.pumpWidget(MaterialApp(
          home: SocialCallPage(
        callId: 1,
        onMinimize: () => minimized = true,
        onBackReady: (callback) => requestBack = callback,
        engineFactory: () => rtc,
        requestMicrophone: () async => true,
        requestCamera: () async => true,
      )));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(rtc.methods, contains(#joinChannel));
      expect(rtc.methods, isNot(contains(#setEnableSpeakerphone)));
      expect(
          rtc.context?.audioScenario, AudioScenarioType.audioScenarioMeeting);
      expect(rtc.methods, contains(#setParameters));
      expect(rtc.methods, contains(#enableInEarMonitoring));
      expect(rtc.options?.publishMicrophoneTrack, isTrue);
      expect(rtc.options?.publishCameraTrack, mode == 'video');
      rtc.events!.onJoinChannelSuccess!(
          const RtcConnection(channelId: 'test-channel', localUid: 7), 0);
      await tester.pump();
      await tester.pump();
      expect(find.text('通话连接失败，请重试'), findsNothing);
      expect(rtc.methods, contains(#setEnableSpeakerphone));
      if (mode == 'video') {
        await tester.tap(find.byTooltip('翻转摄像头'));
        await tester.pump();
        expect(rtc.methods, contains(#switchCamera));
      }
      final backChoice = requestBack!();
      await tester.pumpAndSettle();
      expect(find.text('继续通话'), findsOneWidget);
      expect(rtc.methods, isNot(contains(#release)));
      await tester.tap(find.text('继续通话'));
      await tester.pumpAndSettle();
      await backChoice;
      await tester.pump();
      expect(minimized, isTrue);
      expect(serviceCalls.where((call) => call.method == 'start'), isNotEmpty);
      expect((serviceCalls.first.arguments as Map)['camera'], mode == 'video');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(serviceCalls.where((call) => call.method == 'stop'), isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(rtc.methods, isNot(contains(#release)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      expect(serviceCalls.where((call) => call.method == 'stop'), isNotEmpty);
    });
  }
}
