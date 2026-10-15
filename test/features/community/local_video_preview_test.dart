import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:xuanyu/features/community/local_video_preview.dart';
import 'package:xuanyu/features/community/post_composer_support_pages.dart';
import 'package:xuanyu/features/community/post_publish_settings_page.dart';
import 'package:xuanyu/features/community/video_player_page.dart';

class _Frames extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final sources = <DataSource>[];
  final seeks = <Duration>[];
  final disposed = <int>[];
  int plays = 0;
  bool fail = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (fail) throw StateError('Unsupported video');
    sources.add(options.dataSource);
    final id = sources.length;
    final events = StreamController<VideoEvent>();
    streams[id] = events;
    events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(320, 240)));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Widget buildView(int playerId) =>
      ColoredBox(key: ValueKey('decoded-frame-$playerId'), color: Colors.green);
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await streams[playerId]?.close();
  }
}

void main() {
  late VideoPlayerPlatform original;
  late _Frames frames;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    frames = _Frames();
    VideoPlayerPlatform.instance = frames;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = original;
  });

  testWidgets('本地视频显示解码画面，静音暂停且跳过片头黑帧', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 150,
                height: 150,
                child: LocalVideoPreview(path: '/selected.mp4')))));
    await tester.pumpAndSettle();
    expect(frames.sources.single.sourceType, DataSourceType.file);
    expect(frames.seeks.single, const Duration(milliseconds: 500));
    expect(frames.plays, 0);
    expect(find.byKey(const ValueKey('decoded-frame-1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(frames.disposed, [1]);
  });

  testWidgets('作品预览展示同一视频并能点击实际播放', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: PostPreviewPage(
            content: '',
            images: [],
            videoPath: '/selected.mp4',
            settings: PostPublishSettings())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('decoded-frame-1')), findsOneWidget);
    await tester.tap(find.byType(LocalVideoPreview));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerPage), findsOneWidget);
    expect(frames.sources.length, 2);
    expect(frames.plays, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('更换视频销毁旧播放器并加载新视频', (tester) async {
    Widget page(String path) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 150,
                height: 150,
                child: LocalVideoPreview(path: path))));
    await tester.pumpWidget(page('/first.mp4'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('/second.mp4'));
    await tester.pumpAndSettle();
    expect(frames.sources.last.uri, contains('second.mp4'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(frames.disposed, [1]);
    expect(find.byKey(const ValueKey('decoded-frame-2')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('解码失败显示提示，避免始终无说明黑屏', (tester) async {
    frames.fail = true;
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 150,
                height: 150,
                child: LocalVideoPreview(path: '/bad.mp4')))));
    await tester.pumpAndSettle();
    expect(find.text('画面加载失败，点击重试播放'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
