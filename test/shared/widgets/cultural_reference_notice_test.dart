import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';

void main() {
  const screenSize = Size(280, 640);

  Future<void> mountFooter(
    WidgetTester tester, {
    double textScale = 1,
    double bottomInset = 0,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          textScaler: TextScaler.linear(textScale),
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 640),
                CulturalReferenceNotice(),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
  }

  void useNarrowScreen(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screenSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('窄屏使用大字体时正文真实换行且完整留在页面内', (tester) async {
    useNarrowScreen(tester);
    await mountFooter(tester, textScale: 2.4);

    final textFinder = find.descendant(
      of: find.byType(CulturalReferenceNotice),
      matching: find.byType(Text),
    );
    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    final text = tester.widget<Text>(textFinder).data!;
    final lineBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );

    // 检查真实排版行，而不是通过组件的 softWrap 配置推断换行。
    expect(lineBoxes.map((box) => box.top).toSet().length, greaterThan(1));
    expect(paragraph.didExceedMaxLines, isFalse);
    final bounds = tester.getRect(textFinder);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(screenSize.width));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(screenSize.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部系统安全区增大时正文整体上移并保留全部间距', (tester) async {
    useNarrowScreen(tester);
    final textFinder = find.descendant(
      of: find.byType(CulturalReferenceNotice),
      matching: find.byType(Text),
    );
    await mountFooter(tester);
    final withoutInset = tester.getRect(textFinder);

    const systemInset = 34.0;
    await mountFooter(tester, bottomInset: systemInset);
    final withInset = tester.getRect(textFinder);

    expect(withInset.height, closeTo(withoutInset.height, 0.01));
    expect(withoutInset.bottom - withInset.bottom, closeTo(systemInset, 0.01));
    expect(
      screenSize.height - withInset.bottom,
      greaterThanOrEqualTo(systemInset),
    );
    expect(tester.takeException(), isNull);
  });
}
