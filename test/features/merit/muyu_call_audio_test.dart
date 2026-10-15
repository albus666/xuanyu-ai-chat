import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/rtc_audio_activity.dart';
import 'package:xuanyu/features/merit/services/muyu_knock_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('通话中木鱼不预加载或播放，通话外设置仅作用于木鱼播放器', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final globals = <MethodCall>[];
    final players = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'), (call) async {
      globals.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global/events'),
        (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'), (call) async {
      players.add(call);
      if (call.method == 'create') {
        final id = (call.arguments as Map)['playerId'];
        messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null);
      }
      return null;
    });

    final owner = Object();
    addTearDown(() => RtcAudioActivity.release(owner));
    await RtcAudioActivity.acquire(owner);
    await MuyuKnockSound.ensureReady();
    MuyuKnockSound.playHit();
    await Future<void>.delayed(Duration.zero);
    expect(players, isEmpty);
    expect(globals, isEmpty);

    RtcAudioActivity.release(owner);
    await MuyuKnockSound.ensureReady();
    expect(players.where((call) => call.method == 'setAudioContext'),
        hasLength(3));
    expect(globals.where((call) => call.method == 'setAudioContext'), isEmpty);

    players.clear();
    await RtcAudioActivity.acquire(owner);
    expect(players.where((call) => call.method == 'stop'), hasLength(3));
    players.clear();
    MuyuKnockSound.playHit();
    await MuyuKnockSound.ensureReady();
    await Future<void>.delayed(Duration.zero);
    expect(players, isEmpty);
  });
}
