import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/cache/page_snapshot_cache.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/virtual_goods/decoration_center_page.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_studio_page.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_catalog.dart';
import 'package:xuanyu/features/profile/profile_background_presets.dart';

void main() {
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PageSnapshotCache.clearMemory();
    setupApiClientToken('catalog-loading-test');
    calls.clear();
    respond = (request, handler) {};
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request.path);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
    PageSnapshotCache.clearMemory();
  });
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(480, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('装扮主页不会抢先加载隐藏的头像馆', (tester) async {
    respond = (request, handler) => handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'code': 0,
            'data': {'homeBackgroundId': '', 'backgrounds': []}
          },
        ));
    await open(tester, const DecorationCenterPage(user: {}));
    expect(calls, ['/api/virtual/backgrounds']);
    expect(find.text('头像馆'), findsOneWidget);
    await tester.tap(find.text('头像馆'));
    // Lazy mounting happens in the next frame; then Dio schedules its reads.
    await tester.pumpAndSettle();
    expect(calls, contains('/api/virtual/catalog'));
    expect(calls, contains('/api/virtual/profile'));
  });
  testWidgets('头像馆慢网首屏直接展示本地成品且禁止未校验购买', (tester) async {
    await open(tester, const VirtualAvatarStudioPage());
    expect(find.text('平台原创成品 · 五官统一校准 · 全站同步'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('余额更新中'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '使用'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('缓存头像展示时禁止翻页，实时首页返回后恢复分页', (tester) async {
    final catalog = <String, dynamic>{
      'avatars': [
        for (final asset in VirtualAvatarCatalog.finishedAssets.keys)
          {'id': 100 + VirtualAvatarCatalog.finishedAssets.keys.toList().indexOf(asset),
           'name': asset, 'productType': 'finished', 'categoryCode': asset.split('_').first,
           'owned': true, 'price': '0', 'config': {'assetCode': asset, 'productType': 'finished'}},
      ],
      'avatarPageInfo': {'page': 1, 'hasMore': true},
      'balance': '0',
    };
    await tester.runAsync(() => PageSnapshotCache('avatar_studio_catalog').write(catalog));
    RequestOptions? firstRequest;
    RequestInterceptorHandler? firstHandler;
    final pages = <int>[];
    respond = (request, handler) {
      if (request.path.endsWith('/catalog')) {
        final page = (request.queryParameters['avatarPage'] as int?) ?? 1;
        pages.add(page);
        if (page == 1) { firstRequest = request; firstHandler = handler; return; }
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200,
        data: {'code': 0, 'data': {'avatars': [], 'avatarPageInfo': {'page': 2, 'hasMore': false}}}));
    };
    await open(tester, const VirtualAvatarStudioPage());
    await tester.drag(find.byType(GridView).first, const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pages, [1]);
    firstHandler!.resolve(Response(requestOptions: firstRequest!, statusCode: 200,
        data: {'code': 0, 'data': catalog}));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.drag(find.byType(GridView).first, const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.drag(find.byType(GridView).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pages, [1, 2]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未手动选装扮时缓存和实时装备均同步预览选择', (tester) async {
    final backgrounds = [
      {'id': 'star_sea_whale', 'price': '0'},
      {'id': 'moon_white', 'price': '0'},
      {'id': 'sunny_hug', 'price': '0'},
    ];
    await tester.runAsync(() => PageSnapshotCache('decoration_center').write({
      'homeBackgroundId': 'moon_white', 'backgrounds': backgrounds,
    }));
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pendingHandler;
    respond = (request, handler) { pendingRequest = request; pendingHandler = handler; };
    await open(tester, const DecorationCenterPage(user: {'homeBackgroundId': 'sunny_hug'}));
    Text selectedButton() => tester.widget<FilledButton>(find.byType(FilledButton)).child! as Text;
    expect(selectedButton().data, contains(profileBackgroundById('moon_white')!.name));
    pendingHandler!.resolve(Response(requestOptions: pendingRequest!, statusCode: 200,
      data: {'code': 0, 'data': {'homeBackgroundId': 'star_sea_whale', 'backgrounds': backgrounds}}));
    await tester.pump(const Duration(milliseconds: 120));
    expect(selectedButton().data, contains(profileBackgroundById('star_sea_whale')!.name));
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
