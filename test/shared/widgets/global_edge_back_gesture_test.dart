import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/shared/widgets/global_edge_back_gesture.dart';

void main() {
  testWidgets('只响应从左缘开始且方向明确的右滑返回', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => GlobalEdgeBackGesture(
          onBack: () async {
            final navigator = navigatorKey.currentState;
            if (navigator != null && navigator.canPop()) {
              await navigator.maybePop();
            }
          },
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('第二页')),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    final vertical = await tester.startGesture(const Offset(8, 200));
    await vertical.moveTo(const Offset(28, 330));
    await vertical.up();
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    final back = await tester.startGesture(const Offset(8, 220));
    await back.moveTo(const Offset(130, 226));
    await back.up();
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
  });
}
