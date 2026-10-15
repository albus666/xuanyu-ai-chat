import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/bootstrap/startup_quote_page.dart';
import 'package:xuanyu/app/bootstrap/startup_quote_service.dart';
import 'package:xuanyu/app/bootstrap/startup_gate.dart';

void main() {
  test('开屏时间保持轻快', () {
    expect(startupDisplayDuration, const Duration(milliseconds: 1200));
    expect(startupTransitionDuration, const Duration(milliseconds: 180));
  });

  test('启动寄语本地校验拒绝空文本与超长文本', () {
    expect(StartupQuoteService.normalize('  慢一点\n也没关系  '), '慢一点 也没关系');
    expect(StartupQuoteService.normalize(''), isNull);
    expect(
      StartupQuoteService.normalize('愿' * (StartupQuoteService.maxLength + 1)),
      isNull,
    );
  });

  testWidgets('图标完成渲染后仅通知一次开始开屏计时', (tester) async {
    var ready = 0;
    await tester.pumpWidget(MaterialApp(
        home: StartupQuotePage(
      quote: StartupQuoteService.defaultQuote,
      onContinue: () {},
      onReady: () => ready++,
    )));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('assets/app_icon.png'),
          tester.element(find.byType(StartupQuotePage)));
    });
    await tester.pumpAndSettle();
    expect(ready, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(ready, 1);
  });

  testWidgets('长寄语最多三行且页面不重复展示品牌文字', (tester) async {
    var continued = false;
    const quote = StartupQuoteService.defaultQuote;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupQuotePage(
          quote: quote,
          onContinue: () => continued = true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('startup-quote-icon')),
      findsOneWidget,
    );
    expect(find.text(quote), findsOneWidget);
    expect(find.text('玄遇 APP'), findsNothing);
    expect(find.text('点击任意位置进入'), findsOneWidget);
    final text = tester.widget<Text>(find.text(quote));
    expect(text.maxLines, 3);
    expect(text.textAlign, TextAlign.center);

    await tester.tap(find.byKey(const ValueKey<String>('startup-quote-page')));
    expect(continued, isTrue);
  });

  testWidgets('短寄语使用单行紧凑字号', (tester) async {
    const quote = '慢一点，也没关系。';
    await tester.pumpWidget(
      MaterialApp(
        home: StartupQuotePage(quote: quote, onContinue: () {}),
      ),
    );

    final text = tester.widget<Text>(find.text(quote));
    expect(text.maxLines, 1);
    expect(text.style?.fontSize, lessThanOrEqualTo(24));
  });
}
