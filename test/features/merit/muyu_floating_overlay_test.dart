import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';
import 'package:xuanyu/features/merit/widgets/muyu_floating_overlay.dart';
import 'package:xuanyu/features/merit/widgets/muyu_knock_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('悬浮木鱼可敲击、跟手拖动并从底部关闭', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = MuyuFloatingController.instance;
    await controller.initialize();
    await controller.enable(data: MeritSaveData());

    await tester.pumpWidget(
      const MaterialApp(
        home: MuyuFloatingOverlayHost(
          child: Scaffold(body: Center(child: Text('播间内容'))),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('播间内容'), findsOneWidget);
    expect(find.byType(MuyuKnockWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('floating-muyu-visual')), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await tester.tap(find.byType(MuyuKnockWidget));
    await tester.pump(const Duration(milliseconds: 320));

    final saved = await MeritStorageService.load();
    expect(saved.totalTaps, 1);
    expect(saved.todayTaps, 1);
    expect(find.text('平安顺遂'), findsOneWidget);

    final handle = find.byKey(const ValueKey('floating-muyu-drag-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    // 第一小段移动用于越过系统拖拽识别阈值；之后的每一帧应按增量跟手。
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    final dragStart = tester.getTopLeft(handle);
    await gesture.moveBy(const Offset(-40, 20));
    await tester.pump();

    final moved = tester.getTopLeft(handle);
    expect(moved.dx, closeTo(dragStart.dx - 40, .1));
    expect(moved.dy, closeTo(dragStart.dy + 20, .1));
    expect(find.byKey(const ValueKey('muyu-close-target')), findsOneWidget);
    expect(find.text('拖到这里关闭悬浮木鱼'), findsOneWidget);

    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(find.text('松手关闭悬浮木鱼'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(controller.enabled, isFalse);
    expect(find.byType(MuyuKnockWidget), findsNothing);
    await controller.disable();
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
