import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only fake for video_player's already-resolved platform implementation.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';
import 'package:xuanyu/features/virtual_goods/virtual_gift_effect.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final played = <int>[];
  final disposed = <int>[];
  final volumes = <double>[];
  int created = 0;

  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<int?> create(DataSource dataSource) async {
    final id = ++created;
    streams[id] = StreamController<VideoEvent>();
    positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes.add(volume);
  @override
  Future<void> play(int playerId) async => played.add(playerId);
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;
  @override
  Widget buildView(int playerId) =>
      ColoredBox(key: ValueKey('test_video_$playerId'), color: Colors.blueGrey);
  @override
  Future<void> dispose(int playerId) async => disposed.add(playerId);

  void initialize(
    int id, {
    Duration duration = const Duration(seconds: 4),
    Size size = const Size(640, 360),
  }) {
    streams[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: duration,
      size: size,
    ));
  }

  Future<void> close() async {
    for (final stream in streams.values) {
      await stream.close();
    }
  }
}

void main() {
  late _VideoPlatform video;
  late VideoPlayerPlatform previousVideo;
  var completions = 0;
  var chatTaps = 0;
  const simple = <String, dynamic>{
    'giftName': '心光',
    'senderName': '向日葵',
    'receiverName': '青禾',
    'quantity': 1,
    'effectDurationMs': 1200,
  };
  const videoPayload = <String, dynamic>{
    ...simple,
    'tier': 'large',
    'effectVideoUrl': 'https://example.invalid/synthetic-gift.mp4',
  };

  setUp(() async {
    completions = 0;
    chatTaps = 0;
    previousVideo = VideoPlayerPlatform.instance;
    video = _VideoPlatform();
    VideoPlayerPlatform.instance = video;
    SharedPreferences.setMockInitialValues({});
    await AppSettingsStore.instance
        .initialize(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    await video.close();
    VideoPlayerPlatform.instance = previousVideo;
  });

  Future<void> showGift(
    WidgetTester tester, {
    Map<String, dynamic> payload = simple,
    bool reduced = false,
    double scale = 1,
    Size size = const Size(390, 844),
    bool preview = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size,
            disableAnimations: reduced,
            textScaler: TextScaler.linear(scale)),
        child: Scaffold(
            body: Stack(fit: StackFit.expand, children: [
          Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () => chatTaps++,
                child: const Text('聊天室'),
              )),
          VirtualGiftEffect(
            key: const ValueKey('effect'),
            payload: payload,
            preview: preview,
            onCompleted: () => completions++,
          ),
        ])),
      ),
    ));
    await tester.pump();
  }

  Future<void> removeGift(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> flushNativeDisposal(WidgetTester tester) async {
    // StreamSubscription.cancel can await the SDK's shared completed Future,
    // created outside fakeAsync. Drain that real-zone future before assertions.
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  testWidgets('三个礼物逐次播放，完成三次后才退出', (tester) async {
    await showGift(tester, payload: {...simple, 'quantity': 3}, reduced: true);
    await tester.pump(VirtualGiftEffect.reducedMotionDuration);
    expect(completions, 0);
    await tester.pump(VirtualGiftEffect.reducedMotionDuration);
    expect(completions, 0);
    await tester.pump(VirtualGiftEffect.reducedMotionDuration);
    expect(completions, 1);
  });

  testWidgets('图片程序特效完整播放后只回调一次并展示双方和数量', (tester) async {
    await showGift(tester);
    expect(find.text('心光 ×1'), findsOneWidget);
    expect(find.text('向日葵 → 青禾'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 650));
    expect(completions, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('视频等待不消耗礼物时长，按实际视频进度完成而非配置时长', (tester) async {
    await showGift(tester, payload: videoPayload);
    await tester.pump(const Duration(seconds: 4));
    expect(
        find.byKey(const ValueKey('virtual_gift_preparing')), findsOneWidget);
    expect(completions, 0);
    expect(video.played, isEmpty);
    video.initialize(1);
    await tester.pump();
    await tester.pump();
    expect(video.played, [1]);
    video.positions[1] = const Duration(milliseconds: 1500);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(completions, 0);
    expect(find.byKey(const ValueKey('test_video_1')), findsOneWidget);
    video.positions[1] = const Duration(seconds: 4);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(completions, 0);
    expect(find.byKey(const ValueKey('test_video_1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 110));
    final fade =
        tester.widget<Opacity>(find.byKey(const ValueKey('virtual_gift_exit')));
    expect(fade.opacity, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 120));
    await flushNativeDisposal(tester);
    expect(completions, 1);
    expect(video.disposed, [1]);
    expect(video.volumes.every((value) => value == 0), isTrue);
    await removeGift(tester);
  });

  testWidgets('视频初始化超时降级后重新给图片完整展示时间', (tester) async {
    await showGift(tester, payload: videoPayload);
    await tester.pump(VirtualGiftEffect.videoPrepareTimeout);
    await tester.pump();
    await flushNativeDisposal(tester);
    expect(find.byKey(const ValueKey('virtual_gift_artwork')), findsOneWidget);
    expect(completions, 0);
    expect(video.disposed, [1]);
    await tester.pump(const Duration(milliseconds: 700));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('初始化期间跳过可点击且迟到视频不再播放', (tester) async {
    await showGift(tester, payload: videoPayload);
    await tester.tap(find.byKey(const ValueKey('virtual_gift_skip')));
    await tester.pump();
    expect(completions, 1);
    video.initialize(1);
    await tester.pump(const Duration(seconds: 6));
    await flushNativeDisposal(tester);
    expect(video.played, isEmpty);
    expect(video.disposed, [1]);
    expect(completions, 1);
    expect(tester.takeException(), isNull);
    await removeGift(tester);
  });

  testWidgets('准备期间销毁取消计时和回调，不推进已离开的队列', (tester) async {
    await showGift(tester, payload: videoPayload);
    await removeGift(tester);
    video.initialize(1);
    await tester.pump(const Duration(seconds: 7));
    await flushNativeDisposal(tester);
    expect(video.disposed, [1]);
    expect(video.played, isEmpty);
    expect(completions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('解码错误降级程序动画而不是空白结束', (tester) async {
    await showGift(tester, payload: videoPayload);
    video.streams[1]!.addError(PlatformException(
        code: 'VideoError', message: 'synthetic decoding failure'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('virtual_gift_artwork')), findsOneWidget);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(completions, 1);
    expect(tester.takeException(), isNull);
    await removeGift(tester);
  });

  testWidgets('播放卡住有超时降级，不永久堵住礼物队列', (tester) async {
    await showGift(tester, payload: videoPayload);
    video.initialize(1, duration: const Duration(seconds: 20));
    await tester.pump();
    await tester.pump();
    await tester.pump(VirtualGiftEffect.videoStallTimeout);
    await tester.pump();
    expect(find.byKey(const ValueKey('virtual_gift_artwork')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('系统减少动态效果只显示短静态提示，不创建视频和图片动画', (tester) async {
    await showGift(tester, payload: videoPayload, reduced: true);
    await flushNativeDisposal(tester);
    expect(video.created, 0);
    expect(find.byKey(const ValueKey('virtual_gift_artwork')), findsNothing);
    expect(find.text('心光 ×1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 750));
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('应用自己的减少动态开关同样不启动视频', (tester) async {
    SharedPreferences.setMockInitialValues({'app_setting_reduceMotion': true});
    await AppSettingsStore.instance
        .initialize(await SharedPreferences.getInstance());
    await showGift(tester, payload: videoPayload, preview: true);
    expect(video.created, 0);
    expect(find.byKey(const ValueKey('virtual_gift_artwork')), findsNothing);
    await tester.pump(VirtualGiftEffect.reducedMotionDuration);
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('播放途中系统切换减少动态时立即停止视频', (tester) async {
    await showGift(tester, payload: videoPayload);
    video.initialize(1);
    await tester.pump();
    await tester.pump();
    await showGift(tester, payload: videoPayload, reduced: true);
    await flushNativeDisposal(tester);
    expect(video.disposed, [1]);
    expect(video.created, 1);
    await tester.pump(VirtualGiftEffect.reducedMotionDuration);
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('局部视频保留上方聊天室且contain不裁切主体', (tester) async {
    await showGift(tester, payload: videoPayload);
    video.initialize(1);
    await tester.pump();
    await tester.pump();
    final stage =
        tester.getRect(find.byKey(const ValueKey('virtual_gift_stage')));
    expect(stage.top, greaterThan(180));
    expect(stage.height, lessThanOrEqualTo(844 * .66));
    final fitting = tester.widget<FittedBox>(
        find.byKey(const ValueKey('virtual_gift_video_contain')));
    expect(fitting.fit, BoxFit.contain);
    await tester.tap(find.text('聊天室'));
    expect(chatTaps, 1);
    await tester.tap(find.byKey(const ValueKey('virtual_gift_skip')));
    await tester.pump();
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('竖屏视频舞台足够高且准备播放降级均不跳位', (tester) async {
    await showGift(tester, payload: videoPayload);
    final before =
        tester.getRect(find.byKey(const ValueKey('virtual_gift_stage')));
    video.initialize(1, size: const Size(720, 1280));
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('virtual_gift_stage'))),
        before);
    final viewport = tester
        .getSize(find.byKey(const ValueKey('virtual_gift_video_contain')));
    expect(viewport.height, greaterThan(400));
    video.streams[1]!.addError(PlatformException(
        code: 'VideoError', message: 'synthetic playback failure'));
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('virtual_gift_stage'))),
        before);
    expect(find.byKey(const ValueKey('virtual_gift_artwork')), findsOneWidget);
    await removeGift(tester);
  });

  testWidgets('入场特效使用称号和昵称而非礼物数量与默认好友', (tester) async {
    await showGift(tester, payload: const {
      'effectName': '星河入场',
      'nickname': '向日葵',
      'effectType': 'moon_gate',
      'effectDurationMs': 1200,
    });
    expect(find.text('星河入场'), findsOneWidget);
    expect(find.text('向日葵 来了'), findsOneWidget);
    expect(find.textContaining('好友'), findsNothing);
    expect(find.textContaining('一份心意'), findsNothing);
    expect(find.textContaining('×1'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('连击显示订单数与累计数量且不套用单笔限额', (tester) async {
    await showGift(tester, payload: {
      ...simple,
      'quantity': 1980,
      'comboCount': 2,
    });
    expect(find.text('心光 ×1980'), findsOneWidget);
    expect(find.text('连击 ×2'), findsOneWidget);
    await removeGift(tester);
  });

  testWidgets('连续切换不同礼物时旧视频迟到不会抢播放或推进新礼物', (tester) async {
    await showGift(tester, payload: videoPayload);
    await showGift(tester, payload: {...videoPayload, 'giftName': '新心光'});
    video.initialize(1);
    video.initialize(2);
    await tester.pump();
    await tester.pump();
    await flushNativeDisposal(tester);
    expect(video.disposed, [1]);
    expect(video.played, [2]);
    expect(completions, 0);
    expect(find.text('新心光 ×1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('virtual_gift_skip')));
    await tester.pump();
    await flushNativeDisposal(tester);
    expect(video.disposed, [1, 2]);
    expect(completions, 1);
    await removeGift(tester);
  });

  testWidgets('窄屏横屏大字号小中大礼物均无布局溢出', (tester) async {
    for (final size in [const Size(280, 568), const Size(568, 240)]) {
      for (final tier in ['small', 'medium', 'large']) {
        await showGift(tester,
            size: size,
            scale: 2.4,
            payload: {...simple, 'tier': tier, 'giftName': '一份很长很长的星河心意'});
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('virtual_gift_skip')));
        await tester.pump();
        await removeGift(tester);
      }
    }
  });
}
