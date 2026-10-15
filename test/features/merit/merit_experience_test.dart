import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/models/merit_skins.dart';
import 'package:xuanyu/features/merit/pages/merit_home_page.dart';
import 'package:xuanyu/features/merit/services/merit_auto_knock.dart';
import 'package:xuanyu/features/merit/services/merit_prayer_feedback_service.dart';
import 'package:xuanyu/features/merit/services/muyu_knock_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('new wooden fish saves start in calm mode with soft volume', () {
    final data = MeritSaveData();

    expect(data.experienceMode, MeritExperienceMode.calm);
    expect(data.soundVolume, 0.52);
    expect(data.autoKnockIntervalMs, meritDefaultAutoKnockIntervalMs);
  });

  test('wooden fish experience preferences survive save round trip', () {
    final data = MeritSaveData(
      experienceMode: MeritExperienceMode.sleep,
      soundVolume: 0.48,
      autoKnockIntervalMs: 190,
    );

    final restored = MeritSaveData.fromJson(data.toJson());

    expect(restored.experienceMode, MeritExperienceMode.sleep);
    expect(restored.soundVolume, 0.48);
    expect(restored.autoKnockIntervalMs, 190);
  });

  test('legacy saves migrate to calm mode', () {
    final restored = MeritSaveData.fromJson(const {
      'totalTaps': 12,
      'soundEnabled': true,
    });

    expect(restored.experienceMode, MeritExperienceMode.calm);
    expect(restored.soundVolume, 0.52);
  });

  test('only the cloud-water calming wooden fish skin remains', () {
    const skins = MeritSkinDef.defaults;

    expect(skins, hasLength(1));
    expect(skins.single.name, '云水静心');
    expect(skins.single.asset, contains('muyu_cloud_wave_v3'));
    expect(skins.single.stickAsset, contains('stick_cloud_wave_v3'));
    expect(skins.first.unlockReincarnation, 0);
  });

  test('rapid wooden fish taps automatically become quieter', () {
    final relaxed = MuyuKnockSound.volumeForGap(0.52, gapMs: 500);
    final rapid = MuyuKnockSound.volumeForGap(0.52, gapMs: 60);

    expect(rapid, lessThan(relaxed));
    expect(rapid, lessThan(0.25));
  });

  test('automatic wooden fish uses a fast rhythm with prayer feedback', () {
    final data = MeritSaveData();
    expect(meritAutoKnockIntervalFor(data).inMilliseconds, 280);
    setMeritKnocksPerSecond(data, 6);
    expect(meritAutoKnockIntervalFor(data).inMilliseconds, 167);
    expect(meritPrayerFeedbackTexts.length, greaterThanOrEqualTo(8));
    expect(meritPrayerFeedbackTexts, contains('平安顺遂'));
    expect(meritPrayerFeedbackTexts, contains('所愿皆安'));
  });

  testWidgets('automatic knocking starts immediately and shows feedback',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => const MaterialApp(home: MeritHomePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final knockArea = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '敲击木鱼区域',
    );
    expect(knockArea, findsOneWidget);
    final knockRect = tester.getRect(knockArea);
    await tester.tapAt(Offset(knockRect.left + 12, knockRect.top + 12));
    await tester.pump();
    expect(find.text('平安顺遂'), findsOneWidget);
    expect(find.text('今日已敲 1 次'), findsOneWidget);

    await tester.tap(find.text('自动敲击'));
    await tester.pump();
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('所愿皆安'), findsOneWidget);
    expect(find.text('今日已敲 2 次'), findsOneWidget);

    await tester.pump(
      const Duration(milliseconds: meritDefaultAutoKnockIntervalMs),
    );
    expect(find.text('心安自在'), findsOneWidget);
    expect(find.text('今日已敲 3 次'), findsOneWidget);

    await tester.tap(find.text('停止'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
