import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import '../../core/utils/rtc_audio_activity.dart';

/// 串行播放/停止，避免接听或退出后迟到的初始化重新响铃。
class SocialCallSound {
  SocialCallSound({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new {
    RtcAudioActivity.registerSound(stop);
  }
  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  Future<void> _pending = Future<void>.value();
  bool _disposed = false;
  String? _desired;

  void start({required bool incoming}) {
    final asset =
        incoming ? 'audio/call_incoming.wav' : 'audio/call_ringback.wav';
    if (_disposed || _desired == asset || RtcAudioActivity.active) return;
    _desired = asset;
    _pending = _pending.then((_) async {
      if (_disposed || _desired != asset || RtcAudioActivity.active) return;
      final player = _player ??= _playerFactory();
      await player.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          usageType: incoming
              ? AndroidUsageType.notificationRingtone
              : AndroidUsageType.voiceCommunicationSignalling,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
      await player.setReleaseMode(ReleaseMode.loop);
      if (!_disposed && _desired == asset && !RtcAudioActivity.active) {
        await player.play(AssetSource(asset), volume: .65);
      }
    }).catchError((Object _) {
      // 音频设备异常不阻断接听、挂断和账号隔离。
    });
  }

  Future<void> stop() {
    _desired = null;
    return _pending = _pending.then((_) async {
      await _player?.stop();
    }).catchError((Object _) {});
  }

  Future<void> dispose() async {
    _disposed = true;
    RtcAudioActivity.unregisterSound(stop);
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
