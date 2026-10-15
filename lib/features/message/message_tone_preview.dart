import 'package:audioplayers/audioplayers.dart';
import '../../core/utils/rtc_audio_activity.dart';

/// Uses bundled audio rather than platform alert sounds, which can be silent.
class MessageTonePreview {
  MessageTonePreview({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new {
    RtcAudioActivity.registerSound(_stopForCall);
  }
  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  Future<void> play(String tone) {
    final generation = ++_generation;
    return _pending = _pending.then((_) async {
      if (_disposed || generation != _generation) return;
      await _player?.stop();
      if (tone == 'silent' || RtcAudioActivity.active) return;
      final selected = const {'default', 'gentle', 'clear'}.contains(tone)
          ? tone
          : 'default';
      final player = _player ??= _playerFactory();
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.media,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
      await player.setReleaseMode(ReleaseMode.stop);
      if (!_disposed && generation == _generation && !RtcAudioActivity.active) {
        await player.play(AssetSource('audio/message_$selected.wav'),
            volume: .7);
      }
    }).catchError((Object _) {});
  }

  Future<void> _stopForCall() async {
    ++_generation;
    await _pending;
    await _player?.stop();
  }

  Future<void> dispose() async {
    _disposed = true;
    RtcAudioActivity.unregisterSound(_stopForCall);
    ++_generation;
    await _pending;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
