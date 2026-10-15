import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/core/utils/rtc_speech.dart';
import 'package:xuanyu/features/message/social_call_overlay.dart';
import 'package:xuanyu/features/consultation/consultation_call_overlay.dart';
import 'package:xuanyu/features/fortune/matched_voice_overlay.dart';

class ShutdownRtc extends Fake implements RtcEngine {
  final calls = <Symbol>[];
  final stuck = Completer<void>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    if (invocation.memberName == #leaveChannel) return stuck.future;
    return Future<void>.value();
  }
}

class ProcessingRtc extends ShutdownRtc {
  final parameters = <String>[];
  final modes = <AudioAinsMode>[];
  bool unsupportedAins = false;
  @override
  Future<void> setParameters(String value) async => parameters.add(value);
  @override
  Future<void> setAINSMode(
      {required bool enabled, required AudioAinsMode mode}) async {
    expect(enabled, isTrue);
    modes.add(mode);
    if (unsupportedAins) throw AgoraRtcException(code: -4);
  }
}

void main() {
  test('启用完整3A和均衡降噪，路由变化不重复初始化AI或音频场景', () async {
    final rtc = ProcessingRtc();
    await configureRtcSpeech(rtc);
    await configureRtcSpeech(rtc);
    await restoreRtcSpeechProcessing(rtc);
    expect(rtc.modes, [AudioAinsMode.ainsModeBalanced]);
    expect(rtc.calls.where((c) => c == #setAudioProfile), hasLength(1));
    expect(rtc.parameters, hasLength(2));
    for (final value in rtc.parameters) {
      expect(value, contains('"che.audio.aec.enable":true'));
      expect(value, contains('"che.audio.ans.enable":true'));
      expect(value, contains('"che.audio.agc.enable":true'));
    }
  });
  test('设备不支持AI降噪仍保留标准3A，不阻断通话初始化', () async {
    final rtc = ProcessingRtc()..unsupportedAins = true;
    await configureRtcSpeech(rtc);
    expect(rtc.parameters.single, contains('"che.audio.agc.enable":true'));
    await restoreRtcSpeechProcessing(rtc);
    expect(rtc.parameters, hasLength(2));
    expect(rtc.modes, hasLength(1));
  });
  test('重复初始化和路由恢复不会重设通话中的音频配置', () async {
    final rtc = ShutdownRtc();
    await configureRtcSpeech(rtc);
    await configureRtcSpeech(rtc);
    await restoreRtcSpeechProcessing(rtc);
    expect(rtc.calls.where((c) => c == #setAudioProfile), hasLength(1));
    expect(rtc.calls.where((c) => c == #setParameters), hasLength(2));
  });
  testWidgets('原生退出挂起也会先静音，再尝试释放且结束清理等待', (tester) async {
    final rtc = ShutdownRtc();
    var completed = false;
    unawaited(releaseRtcEngine(rtc).then((_) => completed = true));
    await tester.pump();
    expect(rtc.calls.take(3),
        [#muteLocalAudioStream, #muteAllRemoteAudioStreams, #leaveChannel]);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(rtc.calls, contains(#release));
    expect(completed, isTrue);
    rtc.stuck.complete();
    await tester.pump();
  });
  testWidgets('通话结束后各层根返回拦截全部解除', (tester) async {
    final social = SocialCallOverlay.instance;
    final private = ConsultationCallOverlay.instance;
    final matched = MatchedVoiceOverlay.instance;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [
        SocialCallBackNavigatorObserver(),
        ConsultationBackNavigatorObserver(),
        MatchedVoiceBackNavigatorObserver()
      ],
      home: const Scaffold(body: Text('首页')),
    ));
    for (final type in ['social', 'private', 'matched']) {
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('我的咨询')))));
      await tester.pumpAndSettle();
      if (type == 'social') unawaited(social.open(11));
      if (type == 'private') unawaited(private.open(12));
      if (type == 'matched') unawaited(matched.open('13'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('我的咨询'), findsOneWidget);
      social.close();
      private.close();
      matched.close();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('我的咨询'), findsNothing);
    }
  });
  test('多次结束回调只关闭一次，避免销毁页面时重新通知返回拦截器', () async {
    final social = SocialCallOverlay();
    final private = ConsultationCallOverlay();
    final matched = MatchedVoiceOverlay();
    var notifications = 0;
    for (final c in [social, private, matched]) {
      c.addListener(() => notifications++);
    }
    final a = social.open(12);
    final b = private.open(13);
    final c = matched.open('14');
    social.close();
    private.close();
    matched.close();
    final closedCount = notifications;
    social.close();
    private.close();
    matched.close();
    expect(notifications, closedCount);
    await Future.wait([a, b, c]);
    social.dispose();
    private.dispose();
    matched.dispose();
  });
}
