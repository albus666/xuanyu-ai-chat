import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/pages/home/today_fortune/controller.dart';
import 'package:xuanyu/app/pages/home/today_fortune/view.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';

class _FooterController extends TodayFortuneController {
  @override
  Future<void> onReady() async {}
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  Future<void> mount(WidgetTester tester, String content) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Get.put<TodayFortuneController>(
        _FooterController()..sections = [FortuneSection('今日分析', content)]);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => const GetMaterialApp(home: TodayFortunePage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('短内容提示贴住页面底部，没有正文后大块空白', (tester) async {
    await mount(tester, '今日测试正文');
    final footer = tester.getRect(find.text(CulturalReferenceNotice.text));
    final viewport = tester.getRect(find.byType(CustomScrollView));
    expect(footer.bottom, closeTo(viewport.bottom, 0.1));
    expect(footer.top, greaterThan(tester.getRect(find.text('今日测试正文')).bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长内容提示随正文滚动，滑到底才出现且不遮挡正文', (tester) async {
    final content = List.filled(350, '长正文测试').join('，');
    await mount(tester, content);
    final notice = find.text(CulturalReferenceNotice.text);
    final viewport = tester.getRect(find.byType(CustomScrollView));
    expect(tester.getRect(notice).top, greaterThanOrEqualTo(viewport.bottom));
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final footer = tester.getRect(notice);
    expect(footer.bottom, closeTo(viewport.bottom, 0.1));
    expect(footer.top, greaterThan(tester.getRect(find.text(content)).bottom));
    expect(tester.takeException(), isNull);
  });
}
