import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/profile/profile_background_artwork.dart';
import 'package:xuanyu/features/profile/profile_background_presets.dart';

const _formerlyAnimatedIds = {
  'star_sea_whale',
  'star_sea_jellyfish',
  'star_sea_deer',
  'star_sea_fox',
  'dolphin_companions',
  'whale_companions',
  'jellyfish_lullaby',
  'koi_ripple',
  'butterfly_breeze',
  'cloud_rabbits',
  'penguin_warmth',
  'red_panda_autumn',
  'moon_cat',
  'crane_mist',
  'aurora_fox',
  'otter_holding_paws',
};

void main() {
  testWidgets('装扮背景始终使用静态素材且不注册动画', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 360,
        height: 600,
        child: ProfileBackgroundArtwork(backgroundId: 'dolphin_companions'),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    final image = tester.widget<Image>(find.byType(Image));
    final assetName = (image.image as AssetImage).assetName;
    expect(assetName, endsWith('dolphin_companions.webp'));
    expect(assetName, isNot(endsWith('_motion.webp')));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  test('原动态款保留静态封面且配置不再引用动态素材', () {
    final backgrounds = platformProfileBackgrounds
        .where((item) => _formerlyAnimatedIds.contains(item.id))
        .toList();
    expect(backgrounds, hasLength(_formerlyAnimatedIds.length));
    expect(backgrounds.map((item) => item.id).toSet(), _formerlyAnimatedIds);
    expect(backgrounds.every((item) => item.assetPath != null), isTrue);
    expect(
      backgrounds.every((item) => !item.assetPath!.endsWith('_motion.webp')),
      isTrue,
    );
  });

  test('所有插画背景的本地文件均为可解码单帧图片', () async {
    final backgrounds =
        platformProfileBackgrounds.where((item) => item.assetPath != null);
    for (final item in backgrounds) {
      final data = await rootBundle.load(item.assetPath!);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      expect(codec.frameCount, 1, reason: item.id);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0), reason: item.id);
      expect(frame.image.height, greaterThan(0), reason: item.id);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('小动物静态图层保留真实透明通道', () async {
    final animals = platformProfileBackgrounds
        .where((item) => item.foregroundAsset)
        .toList();
    expect(animals, hasLength(12));
    for (final item in animals) {
      final data = await rootBundle.load(item.assetPath!);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final rgba =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba, isNotNull, reason: item.id);
      final pixels = rgba!.buffer.asUint8List();
      var minimumAlpha = 255;
      var maximumAlpha = 0;
      for (var index = 3; index < pixels.length; index += 4) {
        minimumAlpha =
            minimumAlpha < pixels[index] ? minimumAlpha : pixels[index];
        maximumAlpha =
            maximumAlpha > pixels[index] ? maximumAlpha : pixels[index];
      }
      expect(minimumAlpha, 0, reason: item.id);
      expect(maximumAlpha, 255, reason: item.id);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('单帧插画背景铺满且保持静止', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 360,
        height: 300,
        child: ProfileBackgroundArtwork(backgroundId: 'sunny_hug'),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect((image.image as AssetImage).assetName, endsWith('sunny_hug.png'));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
