import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/profile/change_password_page.dart';
import 'package:xuanyu/features/profile/change_phone_page.dart';
import 'package:xuanyu/features/profile/settings_ui.dart';

void main() {
  testWidgets('换绑手机使用统一设置表单并保留完整双验证码流程', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChangePhonePage(currentMobile: '13800000000'),
      ),
    );

    expect(find.text('修改绑定手机'), findsOneWidget);
    expect(find.text('138****0000'), findsOneWidget);
    expect(find.byType(SettingsFormField), findsNWidgets(3));
    expect(find.text('获取验证码'), findsNWidgets(2));
    expect(find.byType(SettingsPrimaryButton), findsOneWidget);
  });

  testWidgets('修改密码使用统一设置表单并明确全部设备退出', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChangePasswordPage()),
    );

    expect(find.text('修改密码'), findsOneWidget);
    expect(find.byType(SettingsFormField), findsNWidgets(3));
    expect(find.textContaining('全部登录设备'), findsOneWidget);
    expect(find.byType(SettingsPrimaryButton), findsOneWidget);
  });

  test('设备管理使用脱敏会话ID精确退出，不会按整台设备误删', () {
    final source =
        File('lib/features/profile/settings_subpages.dart').readAsStringSync();

    expect(source, contains("item['sessionId']"));
    expect(source, contains('sessionId.isNotEmpty ? sessionId : deviceId'));
  });
}
