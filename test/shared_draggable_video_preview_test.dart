import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/shared/widgets/draggable_video_preview.dart';

void main() {
  testWidgets('视频小窗避开顶部按键，连续拖动累积位移并保留预览', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DraggableVideoPreview(
                child: ColoredBox(
                    key: ValueKey('camera'), color: Colors.black)))));
    final preview = find.byKey(const ValueKey('camera'));
    final original = tester.getTopLeft(preview);
    expect(original.dy, greaterThanOrEqualTo(80));
    final gesture = await tester.startGesture(tester.getCenter(preview));
    await gesture.moveBy(const Offset(-30, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 30));
    await gesture.moveBy(const Offset(-30, 30));
    await tester.pump();
    expect(tester.getTopLeft(preview).dx, lessThan(original.dx - 60));
    expect(tester.getTopLeft(preview).dy, greaterThan(original.dy + 60));
    await gesture.up();
    await tester.pump();
    expect(preview, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('点击小窗切换，拖动不误触且切换保留位置', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DraggableVideoPreview(
                onTap: () => taps++,
                child: const ColoredBox(
                    key: ValueKey('preview-tap'), color: Colors.black)))));
    final preview = find.byKey(const ValueKey('preview-tap'));
    await tester.tap(preview);
    expect(taps, 1);
    await tester.drag(preview, const Offset(-80, 80));
    await tester.pump();
    expect(taps, 1);
    final position = tester.getTopLeft(preview);
    await tester.tap(preview);
    await tester.pump();
    expect(taps, 2);
    expect(tester.getTopLeft(preview), position);
  });
}
