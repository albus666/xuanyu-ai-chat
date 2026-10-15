import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';
import 'package:xuanyu/features/profile/privacy_settings_page.dart';
import 'package:xuanyu/features/profile/settings_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('开关失败立即恢复显示，读取失败后可重试', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettingsStore.instance
        .initialize(await SharedPreferences.getInstance());
    var privacyReads = 0;
    var writes = 0;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final reject = request.method == 'PATCH' ||
          (request.path.endsWith('/privacy') && privacyReads++ == 0);
      if (request.method == 'PATCH') writes++;
      if (reject) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/settings')
            ? AppSettingsStore.defaults
            : {'showIntro': 0}
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: PrivacySettingsPage()));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNull);
    await tester.tap(find.text('部分设置读取失败，点击重试'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('显示在线状态'));
    await tester.pumpAndSettle();
    final row = tester
        .widgetList<SettingsSwitchRow>(find.byType(SettingsSwitchRow))
        .firstWhere((row) => row.title == '显示在线状态');
    expect(row.value, isTrue);
    expect(writes, 1);
    expect(find.text('设置保存失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
  for (final failPrivacy in [false, true]) {
    testWidgets(failPrivacy ? '隐私读取失败时禁止将默认值保存覆盖' : '社交设置加载失败不丢弃已读到的隐私设置',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppSettingsStore.instance
          .initialize(await SharedPreferences.getInstance());
      final fake = InterceptorsWrapper(onRequest: (request, handler) {
        final fail = failPrivacy || request.path.endsWith('/settings');
        if (fail) {
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
        } else {
          handler.resolve(
              Response(requestOptions: request, statusCode: 200, data: {
            'code': 0,
            'data': {
              'showIntro': 0,
              'showLocation': 0,
              'showAge': 0,
              'showBirthDate': 0
            }
          }));
        }
      });
      apiClient.interceptors.insert(0, fake);
      addTearDown(() => apiClient.interceptors.remove(fake));
      await tester.pumpWidget(const MaterialApp(home: PrivacySettingsPage()));
      await tester.pumpAndSettle();
      final save =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '保存'));
      if (failPrivacy) {
        expect(save.onPressed, isNull);
      } else {
        await tester.scrollUntilVisible(find.text('个人简介'), 300);
        final row = tester
            .widgetList<SettingsSwitchRow>(find.byType(SettingsSwitchRow))
            .firstWhere((row) => row.title == '个人简介');
        expect(row.value, isFalse);
      }
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
