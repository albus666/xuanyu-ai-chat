import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/pages/home/home_index/controller.dart';
import 'package:xuanyu/app/pages/home/home_index/view.dart';

void main() {
  testWidgets('首页功能入口在360像素宽度保持五列两行并支持翻页', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final entries = List<GridEntry>.generate(
      13,
      (index) => GridEntry('功能${index + 1}', ''),
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, child) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: HomeFeatureCarousel(
                entries: entries,
                onTap: (_) async {},
                iconBuilder: (_) => const SizedBox.square(
                  dimension: 42,
                  child: Icon(Icons.auto_awesome_rounded),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('功能入口第1页，共2页'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('功能入口第2页，共2页'), findsOneWidget);
  });
}
