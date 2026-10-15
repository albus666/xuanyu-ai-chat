import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_artwork.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_catalog.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_studio_page.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  testWidgets('苍鳞和其它成品不依赖预览界面就能导出1024像素头像', (tester) async {
    for (final code in ['shanhai_canglin', 'night_yuehen', 'micro_jinglan']) {
      final bytes = await tester.runAsync(() =>
          VirtualAvatarArtwork.exportLocalPng(
              {...VirtualAvatarCatalog.initialConfig(), 'assetCode': code}));
      expect(bytes, isNotNull);
      final image = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes!);
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });
      expect(image!.width, 1024);
      expect(image.height, 1024);
      image.dispose();
    }
  });

  testWidgets('已购买苍鳞保存成功，不再购买且上传原图导出的PNG', (tester) async {
    final temp = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('avatar-save-test-')))!;
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    SharedPreferences.setMockInitialValues({});
    setupApiClientToken('avatar-test-only');
    final config = {
      ...VirtualAvatarCatalog.initialConfig(),
      'assetCode': 'shanhai_canglin'
    };
    final calls = <RequestOptions>[];
    String? savedUrl;
    const url = 'https://example.test/approved-avatar.png';
    final fake = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      Object data = {};
      if (r.path == '/api/virtual/catalog') {
        data = {
          'balance': 8758,
          'avatars': [
            {
              'id': 89,
              'name': '苍鳞',
              'productType': 'finished',
              'owned': true,
              'price': 48,
              'config': config
            }
          ]
        };
      } else if (r.path == '/api/config/upload') {
        expect((r.data as FormData).files.single.value.filename,
            'xuanyu_avatar_1024.png');
        data = {'url': url, 'reviewStatus': 'approved'};
      } else if (r.method == 'PATCH') {
        expect(r.data['productId'], 89);
        expect(r.data['avatarUrl'], url);
        data = {'saved': true, 'avatarUrl': url};
      } else {
        data = {'config': config};
      }
      h.resolve(Response(
          requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() async {
      dismissAllAppToasts();
      apiClient.interceptors.remove(fake);
      setupApiClientToken(null);
      PathProviderPlatform.instance = previous;
      await temp.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VirtualAvatarStudioPage(
                embedded: true, onAvatarSaved: (url) => savedUrl = url))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('使用'));
      for (var i = 0; i < 100 && savedUrl == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
    expect(savedUrl, url,
        reason:
            'requests: ${calls.map((r) => '${r.method} ${r.path}').join(', ')}; '
            'texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(', ')}');
    expect(calls.where((r) => r.path.endsWith('/purchase')), isEmpty);
    expect(calls.where((r) => r.method == 'PATCH'), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}
