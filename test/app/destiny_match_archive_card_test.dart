import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/pages/home/destiny_match/controller.dart';
import 'package:xuanyu/app/pages/home/destiny_match/archive_card_background.dart';
import 'package:xuanyu/app/pages/home/destiny_match/view.dart';

class _ArchiveCardTestController extends DestinyMatchController {
  @override
  void onReady() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mediaSaveChannel = MethodChannel('xuanyu/media_save');
  final savedImages = <Map<Object?, Object?>>[];

  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    savedImages.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mediaSaveChannel, (call) async {
      expect(call.method, 'savePng');
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      savedImages.add(arguments);
      return 'photos://saved.png';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mediaSaveChannel, null);
    Get.reset();
  });

  testWidgets('命灵档案卡展示真实字段并能完全隐藏出生日期', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = _ArchiveCardTestController()
      ..archiveReady = true
      ..privacyReady = true
      ..myBirth = '2000-01-01'
      ..minglingTitle = '你好，我是戊午'
      ..minglingTemperament = '稳重担当 · 重视承诺'
      ..minglingAssetPath = 'assets/mingling_v2/wu_full_v3.png'
      ..xishen = '喜神 火'
      ..yongshen = '用神 火'
      ..ziweiPattern = '府相朝垣'
      ..zodiac = '蛇'
      ..constellation = '摩羯';
    Get.put<DestinyMatchController>(controller);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => const GetMaterialApp(home: DestinyMatchPage()),
      ),
    );
    // 卡片会等本地人物图解码完成再整体显示；真实图片解码需离开假时钟。
    await tester.runAsync(() => precacheImage(
          AssetImage(controller.minglingAssetPath!),
          tester.element(find.byType(DestinyMatchPage)),
        ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ArchiveCardBackground), findsOneWidget);
    expect(find.text('你好，我是戊午'), findsOneWidget);
    expect(find.text('稳重担当 · 重视承诺'), findsOneWidget);
    expect(find.text('喜神 火'), findsOneWidget);
    expect(find.text('用神 火'), findsOneWidget);
    expect(find.text('紫微格局 府相朝垣'), findsOneWidget);
    expect(find.text('生肖 蛇'), findsOneWidget);
    expect(find.text('摩羯座'), findsOneWidget);
    expect(find.text('2000-01-01'), findsOneWidget);
    expect(
      (await rootBundle.load(controller.minglingAssetPath!)).lengthInBytes,
      greaterThan(0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('destiny-archive-card-save')));
    // PNG 编码在引擎线程完成，同时推进测试区内的方法通道回调。
    for (var attempt = 0;
        attempt < 100 && controller.savingArchiveCard;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.savingArchiveCard, false);
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsNothing);
    expect(find.text('卡片尚未准备好，请稍后重试'), findsNothing);
    expect(find.text('卡片生成失败'), findsNothing);
    expect(savedImages, hasLength(1));
    expect(savedImages.single['bytes'], isA<Uint8List>());
    expect(
      (savedImages.single['bytes']! as Uint8List).length,
      greaterThan(1000),
    );
    expect(savedImages.single['fileName'], startsWith('xuanyu_destiny_card_'));
    expect(find.text('已保存到相册（包含出生日期）'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('隐藏出生日期'));
    await tester.pumpAndSettle();

    expect(find.text('2000-01-01'), findsNothing);
    expect(find.bySemanticsLabel('显示出生日期'), findsOneWidget);
    expect(find.text('隐藏日期'), findsNothing);
    expect(savedImages, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('destiny-archive-card-save')));
    // PNG 编码在引擎线程完成，同时推进测试区内的方法通道回调。
    for (var attempt = 0;
        attempt < 100 && controller.savingArchiveCard;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.savingArchiveCard, false);
    await tester.pumpAndSettle();
    expect(savedImages, hasLength(2));
    expect(find.text('已保存到相册（出生日期已隐藏）'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mediaSaveChannel, (call) async {
      savedImages.add(Map<Object?, Object?>.from(call.arguments as Map));
      return {'uri': 'content://documents/card.png', 'destination': 'file'};
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('destiny-archive-card-save')));
    for (var attempt = 0;
        attempt < 100 && controller.savingArchiveCard;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.savingArchiveCard, false);
    await tester.pumpAndSettle();
    expect(savedImages, hasLength(3));
    expect(find.text('已保存图片文件（出生日期已隐藏）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  test('命理档案问候语按不同八字日柱生成', () {
    expect(DestinyMatchController.dayPillarGreeting('戊', '午'), '你好，我是戊午');
    expect(DestinyMatchController.dayPillarGreeting('甲', '子'), '你好，我是甲子');
  });
}
