import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/notification/app_notifications.dart';
import 'package:xuanyu/features/profile/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设置中心按账号、安全、服务与通用能力分组', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          isMinorMode: false,
          onMinorModeChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('账号与安全'), findsOneWidget);
    expect(find.text('隐私与在线状态'), findsOneWidget);
    expect(find.text('未成年人保护'), findsOneWidget);
    expect(find.text('安全中心'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('退出登录'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('切换账号'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('关于玄遇'), findsOneWidget);
  });

  testWidgets('未成年人状态在独立入口展示且支付保护仍可查看', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          isMinorMode: true,
          onMinorModeChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('未成年人保护'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('玄遇币与支付安全'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('玄遇币与支付安全'), findsOneWidget);
  });

  test('发布结果提醒偏好能够持久化关闭和开启', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await isPostPublishNotificationEnabled(), isTrue);

    await setPostPublishNotificationEnabled(false);
    expect(await isPostPublishNotificationEnabled(), isFalse);

    await setPostPublishNotificationEnabled(true);
    expect(await isPostPublishNotificationEnabled(), isTrue);
  });
}
