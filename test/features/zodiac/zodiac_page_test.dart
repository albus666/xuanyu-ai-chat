import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/zodiac/zodiac_page.dart';
import 'package:xuanyu/features/zodiac/zodiac_profile.dart';

void main() {
  testWidgets('生肖长解读在360像素手机宽度完整滚动且不再显示流年入口', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: ZodiacReadingContent(
              reading: ZodiacReading.fromBirthDate(DateTime(2001, 12, 1)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('查看生肖流年'), findsNothing);
    expect(find.text('你的完整解读'), findsOneWidget);
    expect(find.text('性格底色'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('适合你的成长方式'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('关系模式'), findsOneWidget);
    expect(find.text('压力与盲点'), findsOneWidget);
    expect(find.text('适合你的成长方式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
