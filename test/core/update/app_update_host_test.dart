import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/update/app_update_host.dart';
import 'package:xuanyu/core/update/app_update_service.dart';

class UpdateAdapter implements HttpClientAdapter {
  bool required = false;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': {
          'updateAvailable': true,
          'required': required,
          'latestVersion': '1.0.38',
          'latestBuild': 39,
          'releaseNotes': ['优化更新提示', '修复消息显示问题'],
          'updateUrl': 'https://www.lingshu.uno/static/app/xuanyu-latest.apk',
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter previous;
  late UpdateAdapter adapter;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: '玄遇',
      packageName: 'com.xuanyu.android',
      version: '1.0.37',
      buildNumber: '38',
      buildSignature: '',
    );
    previous = apiClient.httpClientAdapter;
    apiClient.httpClientAdapter = adapter = UpdateAdapter();
  });
  tearDown(() {
    apiClient.httpClientAdapter = previous;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> mount(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (context, child) =>
            AppUpdateHost(navigatorKey: key, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppUpdateHost.checkNow(context),
              child: const Text('检查更新'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'dialog above navigator shows notes and remembers today checkbox',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('更新内容'), findsOneWidget);
      expect(find.text('• 优化更新提示'), findsOneWidget);
      expect(find.text('今日不再提示'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(
        await AppUpdateService.instance.shouldPrompt(
          AppUpdatePolicy.fromJson({}),
        ),
        isFalse,
      );
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('更新内容'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('required update ignores snooze and cannot be dismissed', (
    tester,
  ) async {
    adapter.required = true;
    await AppUpdateService.instance.snoozeToday();
    await mount(tester);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('今日不再提示'), findsNothing);
    expect(find.text('稍后'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('立即更新'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'expired suppression triggers a check even with recent last check',
    () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'agreement_accepted': true,
        'app_update_last_check_at_v1': now.millisecondsSinceEpoch,
        'app_update_check_interval_hours_v1': 24,
        'app_update_snoozed_local_date_v1': AppUpdateService.localDateKey(
          now.subtract(const Duration(days: 1)),
        ),
      });
      expect(await AppUpdateService.instance.check(), isNotNull);
      expect(adapter.calls, 1);
      expect(await AppUpdateService.instance.check(), isNull);
    },
  );
}
