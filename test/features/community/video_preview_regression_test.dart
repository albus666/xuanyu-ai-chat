import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:xuanyu/features/community/video_player_page.dart';

class _Player extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  DataSource? source;
  bool played = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(320, 240),
        duration: const Duration(seconds: 10)));
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;
  @override
  Widget buildView(int playerId) => const SizedBox();
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {
    played = true;
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> dispose(int playerId) async {
    await events.close();
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
}

void main() {
  for (final url in [
    '/tmp/selected-video.mp4',
    'https://example.test/video.mp4'
  ]) {
    testWidgets('视频实际初始化播放器并播放：$url', (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _Player();
      VideoPlayerPlatform.instance = player;
      addTearDown(() {
        VideoPlayerPlatform.instance = original;
      });
      await tester
          .pumpWidget(MaterialApp(home: VideoPlayerPage(videoUrl: url)));
      await tester.pumpAndSettle();
      expect(
          player.source?.sourceType,
          url.startsWith('https')
              ? DataSourceType.network
              : DataSourceType.file);
      expect(player.played, isTrue);
      expect(find.text('视频暂时无法播放'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
