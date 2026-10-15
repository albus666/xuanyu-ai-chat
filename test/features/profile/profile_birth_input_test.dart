import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/profile/edit_profile_page.dart';

void main() {
  testWidgets('个人资料用一个出生日期时辰入口支持三种历法', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: EditProfilePage(initialNickname: '测试用户'),
      ),
    );

    expect(
      find.text('本人资料全局通用，八字、斗数、每日养生等功能会自动使用'),
      findsOneWidget,
    );
    expect(find.text('出生时辰'), findsNothing);

    await tester.tap(find.text('出生日期时辰'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('公历'), findsOneWidget);
    expect(find.text('农历'), findsOneWidget);
    expect(find.text('四柱'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
  });
}
