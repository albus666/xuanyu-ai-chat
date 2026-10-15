import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/rtc_audio_activity.dart';
import 'package:xuanyu/core/utils/rtc_speech.dart';
import 'package:xuanyu/features/message/message_tone_preview.dart';
import 'package:xuanyu/features/message/social_call_sound.dart';

class _Rtc extends Fake implements RtcEngine {
  bool configured = false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setAudioProfile) configured = true;
    return Future<void>.value();
  }
}

class _Player extends Fake implements AudioPlayer {
  int contexts = 0;
  int plays = 0;
  int stops = 0;
  Completer<void>? contextPending;
  @override
  Future<void> setAudioContext(AudioContext context) async {
    contexts++;
    await contextPending?.future;
  }

  @override
  Future<void> play(Source source,
          {double? volume,
          double? balance,
          AudioContext? ctx,
          Duration? position,
          PlayerMode? mode}) async =>
      plays++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test('通话期间提示音不创建播放器或更改模式，挂断后恢复播放', () async {
    final rtc = _Rtc();
    final player = _Player();
    final sound = MessageTonePreview(playerFactory: () => player);
    addTearDown(sound.dispose);
    addTearDown(() => releaseRtcEngine(rtc));
    await configureRtcSpeech(rtc);
    await sound.play('default');
    expect(player.contexts, 0);
    expect(player.plays, 0);
    await releaseRtcEngine(rtc);
    await sound.play('default');
    expect(player.contexts, 1);
    expect(player.plays, 1);
  });

  test('迟到的播放器初始化先排空，再配置RTC且不播放旧提示音', () async {
    final rtc = _Rtc();
    final player = _Player()..contextPending = Completer<void>();
    final sound = MessageTonePreview(playerFactory: () => player);
    addTearDown(sound.dispose);
    addTearDown(() => releaseRtcEngine(rtc));
    final playing = sound.play('gentle');
    await Future<void>.delayed(Duration.zero);
    expect(player.contexts, 1);
    final connecting = configureRtcSpeech(rtc);
    await Future<void>.delayed(Duration.zero);
    expect(RtcAudioActivity.active, isTrue);
    expect(rtc.configured, isFalse);
    player.contextPending!.complete();
    await Future.wait([playing, connecting]);
    expect(player.plays, 0);
    expect(player.stops, greaterThanOrEqualTo(1));
    expect(rtc.configured, isTrue);
  });

  test('多条音频连接中释放一条不解除其余通话的保护', () async {
    final first = _Rtc(), second = _Rtc();
    addTearDown(() => releaseRtcEngine(first));
    addTearDown(() => releaseRtcEngine(second));
    await configureRtcSpeech(first);
    await configureRtcSpeech(second);
    await releaseRtcEngine(first);
    expect(RtcAudioActivity.active, isTrue);
    await releaseRtcEngine(second);
    expect(RtcAudioActivity.active, isFalse);
  });

  test('语音匹配中收到其他来电不会启动响铃播放器', () async {
    final rtc = _Rtc();
    final player = _Player();
    final sound = SocialCallSound(playerFactory: () => player);
    addTearDown(sound.dispose);
    addTearDown(() => releaseRtcEngine(rtc));
    await configureRtcSpeech(rtc);
    sound.start(incoming: true);
    await Future<void>.delayed(Duration.zero);
    expect(player.contexts, 0);
    expect(player.plays, 0);
    await releaseRtcEngine(rtc);
    sound.start(incoming: true);
    await Future<void>.delayed(Duration.zero);
    expect(player.plays, 1);
  });
}
