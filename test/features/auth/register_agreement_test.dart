import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/auth/register_page.dart';
import 'package:xuanyu/app/pages/system/register/controller.dart';
import 'package:xuanyu/app/pages/system/register/view.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('备用注册入口必须主动同意，保留输入并可阅读协议', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    var requests = 0;
    final fake = InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'code': 0, 'data': {}}));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester
        .pumpWidget(MaterialApp(home: RegisterPage(onRegisterSuccess: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('开发环境验证码'), findsNothing);
    final checkbox = find.byKey(const ValueKey('legacy-register-agreement'));
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.ensureVisible(find.text('注册'));
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    await tester.ensureVisible(find.text('《隐私政策》'));
    await tester.tap(find.text('《隐私政策》'));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注册页可阅读并主动勾选用户协议与隐私政策', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => const GetMaterialApp(home: ShellRegisterPage()),
      ),
    );
    await tester.pumpAndSettle();

    final userAgreement = find.byKey(
      const ValueKey<String>('register-user-agreement-link'),
    );
    final privacyPolicy = find.byKey(
      const ValueKey<String>('register-privacy-policy-link'),
    );
    expect(userAgreement, findsOneWidget);
    expect(privacyPolicy, findsOneWidget);

    final controller = Get.find<RegisterController>();
    expect(controller.agreed, isFalse);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('register-agreement-checkbox')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('register-agreement-checkbox')),
    );
    await tester.pump();
    expect(controller.agreed, isTrue);

    await tester.ensureVisible(userAgreement);
    await tester.tap(userAgreement);
    await tester.pumpAndSettle();
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('玄遇用户协议'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(privacyPolicy);
    await tester.tap(privacyPolicy);
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('玄遇隐私政策'), findsWidgets);
  });
}
