import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/create_post_page.dart';
import 'package:xuanyu/features/community/map_location_picker_page.dart';

void main() {
  testWidgets('作品发布页保留发布设置入口并由加号直达三种媒体来源', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'data': {'list': <dynamic>[]},
        },
      )),
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(const MaterialApp(home: CreatePostPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('post-tool-话题')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-tool-Ta')), findsOneWidget);
    expect(find.text('AI灵感'), findsNothing);
    expect(find.text('音频'), findsNothing);
    expect(find.text('投票'), findsNothing);
    expect(find.text('发文字'), findsNothing);
    expect(find.text('相册'), findsNothing);
    expect(find.text('选择位置'), findsOneWidget);
    expect(find.text('广场可见'), findsOneWidget);
    expect(find.text('添加组件'), findsOneWidget);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.style?.fontSize, 15);
    expect(textField.decoration?.hintStyle?.fontSize, 14);
    expect(tester.widget<Text>(find.text('话题')).style?.fontSize, 13);
    expect(tester.widget<Text>(find.text('Ta')).style?.fontSize, 13);
    expect(tester.widget<Text>(find.text('选择位置')).style?.fontSize, 15);
    expect(tester.widget<Text>(find.text('广场可见')).style?.fontSize, 15);
    expect(tester.widget<Text>(find.text('添加组件')).style?.fontSize, 15);

    await tester.enterText(find.byType(TextField), '字号检查');
    await tester.pump();
    expect(tester.widget<Text>(find.text('预览')).style?.fontSize, 13);
    expect(tester.widget<Text>(find.text('发布')).style?.fontSize, 13);

    await tester
        .ensureVisible(find.byKey(const ValueKey('post-setting-visibility')));
    await tester.tap(find.byKey(const ValueKey('post-setting-visibility')));
    await tester.pumpAndSettle();

    expect(find.text('发布设置'), findsOneWidget);
    expect(find.text('可见范围'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.byKey(const ValueKey('post-setting-component')));
    await tester.tap(find.byKey(const ValueKey('post-setting-component')));
    await tester.pumpAndSettle();

    expect(find.text('添加组件'), findsWidgets);
    expect(find.text('群聊派对'), findsOneWidget);
    expect(find.text('更多功能'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.byKey(const ValueKey('post-setting-location')));
    tester
        .widget<InkWell>(find.byKey(const ValueKey('post-setting-location')))
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MapLocationPickerPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('post-media-add')));
    await tester.tap(find.byKey(const ValueKey('post-media-add')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('post-media-source-camera')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('post-media-source-image')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('post-media-source-video')), findsOneWidget);
    expect(find.text('玄遇相机'), findsNothing);
    expect(find.text('打开相册'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
