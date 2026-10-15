import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/galaxy_match_portal.dart';

Widget _host({
  double revolutionSeconds = 420,
  bool active = true,
  bool tickerEnabled = true,
  bool reducedMotion = false,
  double textScale = 1,
  VoidCallback? destiny,
  VoidCallback? voice,
}) =>
    MaterialApp(
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: TickerMode(
              enabled: tickerEnabled,
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: 369 / 170,
                  child: GalaxyMatchPortal(
                    active: active,
                    revolutionSeconds: revolutionSeconds,
                    onDestinyTap: destiny ?? () {},
                    onVoiceTap: voice ?? () {},
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );

double _elapsed(WidgetTester tester) => tester
    .state<GalaxyMatchPortalState>(find.byType(GalaxyMatchPortal))
    .debugElapsedSeconds;

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('左右入口分别触发且背景图层不拦截点击', (tester) async {
    var destiny = 0;
    var voice = 0;
    await tester.pumpWidget(_host(
      destiny: () => destiny++,
      voice: () => voice++,
    ));
    await tester.tap(find.text('缘分匹配'));
    expect([destiny, voice], [1, 0]);
    await tester.tap(find.text('语音匹配'));
    expect([destiny, voice], [1, 1]);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('${width.toInt()}宽大字仍能看到并点击两侧完整标题', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var destiny = 0;
      var voice = 0;
      await tester.pumpWidget(_host(
        textScale: 1.6,
        destiny: () => destiny++,
        voice: () => voice++,
      ));
      final card = tester.getRect(find.byType(GalaxyMatchPortal));
      for (final title in ['缘分匹配', '语音匹配']) {
        final text = find.text(title);
        expect(text, findsOneWidget);
        final rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(card.left));
        expect(rect.right, lessThanOrEqualTo(card.right + .01));
        expect(rect.bottom, lessThanOrEqualTo(card.bottom + .01));
        await tester.tap(text);
      }
      expect([destiny, voice], [1, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('$width 宽度两侧文字完整且位于星系上方', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(textScale: 1.6));
      final art =
          tester.getRect(find.byKey(const ValueKey('galaxy-art-region')));
      for (final copy in ['缘分匹配', '语音匹配', '遇见与你同频的人', '让声音替你先认识对方']) {
        expect(tester.getRect(find.text(copy)).bottom, lessThan(art.top));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('后台速度改变后按新速度继续旋转且相位不跳变', (tester) async {
    await tester.pumpWidget(_host(revolutionSeconds: 60));
    await tester.pump(const Duration(seconds: 1));
    final state =
        tester.state<GalaxyMatchPortalState>(find.byType(GalaxyMatchPortal));
    final angle = state.debugAngleRadians;
    expect(angle, closeTo(2 * math.pi / 60, 1e-8));
    await tester.pumpWidget(_host(revolutionSeconds: 120));
    expect(state.debugAngleRadians, angle);
    await tester.pump(const Duration(seconds: 1));
    expect(state.debugAngleRadians - angle, closeTo(2 * math.pi / 120, 1e-8));
  });

  test('无效速度回退默认值，合法速度正确采样', () {
    for (final value in [0.0, -1.0, 9.0, 3601.0, double.nan, double.infinity]) {
      expect(GalaxyMotionSample.sample(1, periodSeconds: value).angleRadians,
          closeTo(2 * math.pi / 420, 1e-8));
    }
    for (final value in [10.0, 60.5, 3600.0]) {
      expect(
          GalaxyMotionSample.sample(value, periodSeconds: value).angleRadians,
          closeTo(2 * math.pi, 1e-8));
    }
  });

  for (final reason in ['active', 'TickerMode', 'reduce']) {
    testWidgets('$reason暂停后不累计等待时间且恢复不跳帧', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump(const Duration(milliseconds: 100));
      expect(_elapsed(tester), greaterThan(0));
      await tester.pumpWidget(_host(
        active: reason != 'active',
        tickerEnabled: reason != 'TickerMode',
        reducedMotion: reason == 'reduce',
      ));
      final paused = _elapsed(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(_elapsed(tester), paused);
      await tester.pumpWidget(_host());
      expect(_elapsed(tester), closeTo(paused, .1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_elapsed(tester), greaterThan(paused));
      expect(_elapsed(tester) - paused, lessThan(.3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('后台暂停后前台继续且销毁后无遗留ticker', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = _elapsed(tester);
    await tester.pump(const Duration(minutes: 5));
    expect(_elapsed(tester), paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_elapsed(tester), closeTo(paused, .1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_elapsed(tester), greaterThan(paused));
    expect(_elapsed(tester) - paused, lessThan(.3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('初始减少动态时静止且不影响入口', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(
      reducedMotion: true,
      voice: () => calls++,
    ));
    final start = _elapsed(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(_elapsed(tester), start);
    await tester.tap(find.text('语音匹配'));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  test('星系420秒一周且跨周相位连续', () {
    final a = GalaxyMotionSample.sample(0).angleRadians;
    final b = GalaxyMotionSample.sample(1).angleRadians;
    expect(b - a, closeTo(2 * math.pi / 420, 1e-8));
    final turn = GalaxyMotionSample.sample(420).angleRadians;
    expect(math.cos(turn), closeTo(math.cos(a), 1e-8));
    expect(math.sin(turn), closeTo(math.sin(a), 1e-8));
    final left = GalaxyMotionSample.sample(419.999).angleRadians;
    final right = GalaxyMotionSample.sample(420.001).angleRadians;
    expect((math.cos(left) - math.cos(right)).abs(), lessThan(.001));
    expect((math.sin(left) - math.sin(right)).abs(), lessThan(.001));
  });

  test('长时星光淡入淡出不突变', () {
    var changedStars = false;
    final initial = GalaxyMotionSample.sample(0).starOpacities;
    for (var i = 0; i <= 3600; i++) {
      final sample = GalaxyMotionSample.sample(i.toDouble());
      final next = GalaxyMotionSample.sample(i + .001);
      for (var j = 0; j < sample.starOpacities.length; j++) {
        expect(sample.starOpacities[j], inInclusiveRange(0, 1));
        expect((sample.starOpacities[j] - next.starOpacities[j]).abs(),
            lessThan(.01));
        if ((sample.starOpacities[j] - initial[j]).abs() > .02) {
          changedStars = true;
        }
      }
    }
    expect(changedStars, isTrue);
  });
}
