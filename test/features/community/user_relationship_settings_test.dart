import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/community/user_relationship_settings.dart';

void main() {
  testWidgets('备注页包含15字备注、200字描述及图片入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UserRemarkPage(userId: 8, initialData: {}),
      ),
    );

    expect(find.text('备注和描述'), findsOneWidget);
    expect(find.text('添加图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('remark-add-image')), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].maxLength, 15);
    expect(fields[1].maxLength, 200);
  });

  testWidgets('特别关心页包含开关、说明和提示音选择', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpecialCareSettingsPage(userId: 8, initialData: {}),
      ),
    );

    expect(find.text('特别关心设置'), findsOneWidget);
    expect(find.byKey(const ValueKey('special-care-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('special-care-sound')), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
  });

  testWidgets('对TA隐身设置包含三个独立开关', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showUserStealthSettingsSheet(
                context,
                userId: 8,
                initialData: const {},
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('对TA隐身访问设置'), findsOneWidget);
    expect(find.text('隐身查看TA的主页'), findsOneWidget);
    expect(find.text('隐身查看TA的瞬间'), findsOneWidget);
    expect(find.text('隐身查看与TA的私聊对话'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
  });
}
