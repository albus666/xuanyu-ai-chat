import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/pages/home/destiny_match/archive_card_background.dart';

void main() {
  test('星轨圆环完整位于档案卡内且适当下移', () {
    const size = Size(343, 204);
    final bounds = ArchiveCardBackground.orbitOuterBounds(size);
    final center = ArchiveCardBackground.orbitCenter(size);

    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(size.width));
    expect(bounds.bottom, lessThanOrEqualTo(size.height));
    expect(center.dy, greaterThan(size.height / 2));
  });

  testWidgets('背景从青绿经天蓝过渡到淡紫，不再止于浅蓝', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 343,
              height: 204,
              child: ArchiveCardBackground(),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      return bytes.buffer.asUint8List();
    }))!;
    List<int> sample(int x, int y) =>
        pixels.sublist((y * 343 + x) * 4, (y * 343 + x) * 4 + 4);
    final left = sample(5, 102);
    final middle = sample(200, 102);
    final right = sample(337, 102);
    expect(left[1], greaterThan(left[0] + 80));
    expect(middle[2], greaterThan(middle[1] + 30));
    expect(right[0], greaterThan(middle[0] + 40));
    expect(right[2], greaterThan(right[1] + 40));
    expect(right[3], 255);
    expect(tester.takeException(), isNull);
  });

  testWidgets('星空装饰适应尺寸、没有持续动画且不拦截操作', (tester) async {
    var taps = 0;
    for (final size in [
      const Size(290, 190),
      const Size(343, 204),
      const Size(600, 230),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => taps++,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const Positioned.fill(child: ArchiveCardBackground()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(tester.getCenter(find.byType(ArchiveCardBackground)));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
    expect(taps, 3);
  });
}
