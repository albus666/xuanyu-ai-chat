import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/message/message_tone_preview.dart';

class TonePlayer extends Fake implements AudioPlayer {
  final assets = <String>[];
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    assets.add((source as AssetSource).path);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> setAudioContext(AudioContext context) async {}
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
}

void main() {
  test('三种提示音播放不同文件，静音停止已有试听', () async {
    final player = TonePlayer();
    final preview = MessageTonePreview(playerFactory: () => player);
    for (final tone in ['default', 'gentle', 'clear']) {
      await preview.play(tone);
    }
    expect(player.assets, [
      'audio/message_default.wav',
      'audio/message_gentle.wav',
      'audio/message_clear.wav'
    ]);
    await preview.play('silent');
    expect(player.assets.length, 3);
    expect(player.stops, 3);
    await preview.dispose();
    expect(player.disposed, true);
  });
  test('快速切换只播放最后选项，退出后不迟到播放', () async {
    final player = TonePlayer();
    final preview = MessageTonePreview(playerFactory: () => player);
    final first = preview.play('gentle');
    final last = preview.play('clear');
    await Future.wait([first, last]);
    expect(player.assets, ['audio/message_clear.wav']);
    final pending = preview.play('default');
    await preview.dispose();
    await pending;
    expect(player.assets, ['audio/message_clear.wav']);
  });
}
