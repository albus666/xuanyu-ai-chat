import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/app_toast.dart';

void main() {
  testWidgets('关闭提示后延迟回调不重复移除浮层', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const Scaffold();
    })));
    showAppToast(context, '测试提示');
    await tester.pump();
    expect(find.text('测试提示'), findsOneWidget);
    dismissAllAppToasts();
    dismissAllAppToasts();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(find.text('测试提示'), findsNothing);
  });

  testWidgets('同一帧连续提示只保留最新且正常自动消失', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const Scaffold();
    })));
    showAppToast(context, '第一条');
    await tester.pump();
    showAppToast(context, '第二条');
    showAppToast(context, '第三条');
    await tester.pump();
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsNothing);
    expect(find.text('第三条'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(find.text('第三条'), findsNothing);
  });
}
