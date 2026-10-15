import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/create_post_page.dart';

void main() {
  for (final useGet in [false, true]) {
    for (final save in [false, true]) {
      testWidgets('系统返回保留主页面：Get=$useGet，保存=$save', (tester) async {
        SharedPreferences.setMockInitialValues({});
        var appExitCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') appExitCalls++;
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        final interceptor = InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: {
                'data': {'list': <dynamic>[]},
              },
              statusCode: 200,
            ),
          ),
        );
        apiClient.interceptors.insert(0, interceptor);
        addTearDown(() => apiClient.interceptors.remove(interceptor));
        final home = Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                if (useGet) {
                  Get.to<dynamic>(() => const CreatePostPage());
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<dynamic>(
                      builder: (_) => const CreatePostPage(),
                    ),
                  );
                }
              },
              child: const Text('主页面'),
            ),
          ),
        );
        await tester.pumpWidget(
          useGet ? GetMaterialApp(home: home) : MaterialApp(home: home),
        );
        await tester.tap(find.text('主页面'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '返回测试草稿');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('保存草稿'), findsOneWidget);
        expect(find.text('不保存草稿'), findsOneWidget);
        expect(appExitCalls, 0);
        // 取消选择后仍留在编辑页，连续返回不能退出应用。
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(CreatePostPage), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text(save ? '保存草稿' : '不保存草稿'));
        await tester.pumpAndSettle();
        expect(find.byType(CreatePostPage), findsNothing);
        expect(find.text('主页面'), findsOneWidget);
        expect(appExitCalls, 0);
        await tester.tap(find.text('主页面'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, save ? '返回测试草稿' : '');
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        if (save) {
          expect(find.text('不保存草稿'), findsOneWidget);
          await tester.tap(find.text('不保存草稿'));
          await tester.pumpAndSettle();
        }
        expect(find.text('主页面'), findsOneWidget);
        expect(find.byType(CreatePostPage), findsNothing);
        expect(appExitCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (useGet) Get.reset();
      });
    }
  }
}
