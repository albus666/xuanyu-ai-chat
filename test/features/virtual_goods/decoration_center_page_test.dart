import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/virtual_goods/decoration_center_page.dart';

class _CatalogAdapter implements HttpClientAdapter {
  final writes = <Map>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    if (options.method == 'PATCH') writes.add(Map.from(options.data as Map));
    final data = options.method == 'PATCH'
        ? {
            'homeBackgroundId': options.data['backgroundId'],
            'homeBackgroundUrl': ''
          }
        : {
            'homeBackgroundId': '',
            'backgrounds': [
              {'id': 'star_sea_whale', 'price': '0'},
              {'id': 'moon_white', 'price': '0'},
              {'id': 'sunny_hug', 'price': '0'},
            ]
          };
    return ResponseBody.fromString(jsonEncode({'code': 0, 'data': data}), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('小屏预览不保存，确认后只提交背景编号且无上传入口', (tester) async {
    final original = apiClient.httpClientAdapter;
    final adapter = _CatalogAdapter();
    apiClient.httpClientAdapter = adapter;
    addTearDown(() => apiClient.httpClientAdapter = original);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const DecorationCenterPage(
                                user: {'nickname': '玄遇测试'}),
                          )),
                      child: const Text('打开')),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('上传自己的背景'), findsNothing);
    expect(find.text('装扮中心'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('头像馆')),
      findsNothing,
    );
    expect(find.text('主页装扮'), findsOneWidget);
    expect(find.text('头像馆'), findsOneWidget);
    await tester.tap(find.text('头像馆'));
    await tester.pumpAndSettle();
    expect(find.text('装扮中心'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('头像馆')),
      findsNothing,
    );
    expect(find.text('圆形安全区预览'), findsOneWidget);
    expect(find.textContaining('真实圆形预览'), findsOneWidget);
    expect(find.textContaining('免费使用'), findsNothing);
    await tester.tap(find.text('主页装扮'));
    await tester.pumpAndSettle();
    expect(find.text('动态'), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
    expect(find.textContaining('免费 · 动态'), findsNothing);
    await tester.tap(find.text('星鲸云海'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, '已拥有 · 星鲸云海'));
    await tester.pumpAndSettle();
    expect(adapter.writes, [
      {'backgroundId': 'star_sea_whale'}
    ]);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}
