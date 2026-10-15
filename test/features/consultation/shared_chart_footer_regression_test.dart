import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/room_chart_sheet.dart';
import 'package:xuanyu/features/consultation/room_shared_chart.dart';
import 'package:xuanyu/shared/widgets/bottom_footer_scroll_view.dart';
import 'package:xuanyu/features/fortune/paipan/paipan_detail_chart_tab.dart';
import 'package:xuanyu/features/fortune/paipan/utils/bazi_result.dart';

void main() {
  testWidgets('短内容提示贴住底部，长内容提示随末尾滚动且不覆盖内容', (tester) async {
    for (final height in [100.0, 1200.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: BottomFooterScrollView(
                  child: SizedBox(height: height),
                  footer: const Text('末尾提示', key: ValueKey('footer'))))));
      if (height == 100) {
        expect(tester.getBottomLeft(find.byKey(const ValueKey('footer'))).dy,
            closeTo(600, 1));
      } else {
        expect(tester.getTopLeft(find.byKey(const ValueKey('footer'))).dy,
            greaterThanOrEqualTo(1200));
        await tester.drag(
            find.byType(CustomScrollView), const Offset(0, -1000));
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(find.byKey(const ValueKey('footer'))).dy,
            closeTo(600, 1));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('隐藏出生资料仍展示完整八字专业快照', (tester) async {
    final snapshot = await buildRoomProfessionalSnapshot(RoomChartKind.bazi,
        {'birthDateTime': '2000-01-01T09:00:00', 'isFemale': true});
    snapshot.remove('birthDateTime');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoomSharedChart(
                kind: RoomChartKind.bazi, snapshot: snapshot))));
    await tester.pumpAndSettle();
    expect(find.byType(PaipanDetailChartTab), findsOneWidget);
    expect(find.text('藏干'), findsOneWidget);
    expect(find.text('纳音'), findsOneWidget);

    expect(find.text('流月'), findsWidgets);
    expect((snapshot['professionalChart'] as Map)['daYun'], isNotEmpty);
    final result = BaziResult.fromSharedJson(
        Map<String, dynamic>.from(snapshot['professionalChart'] as Map));
    expect(result.detailGans, hasLength(7));
    expect(result.toSharedJson(), snapshot['professionalChart']);
    expect((snapshot['professionalChart'] as Map).containsKey('solarDate'),
        isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('共享八字与原专业盘在手机宽度绘制完全一致', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final native =
        computeBaziResult(DateTime(2001, 11, 30, 23), isFemale: false);
    Future<List<int>> pixels(Widget chart) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RepaintBoundary(
                  key: const ValueKey('comparison'), child: chart))));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('comparison')));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return bytes!.buffer.asUint8List();
      });
      expect(tester.takeException(), isNull);
      return bytes!;
    }

    final expected =
        await pixels(PaipanDetailChartTab(result: native, isFemale: false));
    await tester.pumpWidget(const SizedBox());
    final actual = await pixels(RoomSharedChart(
        kind: RoomChartKind.bazi,
        snapshot: {
          'professionalChart': native.toSharedJson(),
          'isFemale': false
        }));
    expect(actual.length, expected.length);
    expect(
        List.generate(actual.length, (i) => i)
            .every((i) => actual[i] == expected[i]),
        isTrue,
        reason: '共享盘应与原专业盘逐像素一致');
  });
}
