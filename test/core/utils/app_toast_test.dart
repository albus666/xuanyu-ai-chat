import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/app_toast.dart';

void main() {
  testWidgets('页面返回后会立即清理当前页面的短提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _ToastPage()),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示提示'));
    await tester.pump();
    expect(find.text('仅属于当前页面'), findsOneWidget);

    Navigator.of(tester.element(find.text('显示提示'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('仅属于当前页面'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
  });
}

class _ToastPage extends StatelessWidget {
  const _ToastPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showAppToast(context, '仅属于当前页面'),
          child: const Text('显示提示'),
        ),
      ),
    );
  }
}
