import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/fortune/paipan_record_archive_page.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  late Directory directory;
  late PathProviderPlatform original;
  late InterceptorsWrapper interceptor;
  File file(int uid) => File('${directory.path}/paipan_records_user_$uid.json');
  final record = PaipanRecord(
    id: 'same-id',
    createdAt: DateTime(2026, 9, 29),
    displayName: '合成案例',
    birthDateTime: DateTime(2000, 1, 1, 12),
    isFemale: false,
    calendarTypeIndex: 0,
    summary: '己卯 丙子 戊午 戊午',
    reasoningNotes: '原始合成笔记',
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    setupApiClientToken('synthetic-a');
    directory = await Directory.systemTemp.createTemp('archive-notebook-test-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
    await file(77).writeAsString(jsonEncode([record.toJson()]));
    await file(88).writeAsString(jsonEncode([record.toJson()]));
    interceptor = InterceptorsWrapper(
        onRequest: (r, h) => h.resolve(
              Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: {'code': 0, 'data': {}}),
            ));
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() async {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
    PathProviderPlatform.instance = original;
    await directory.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PaipanRecordArchivePage()));
    await settle(tester);
  }

  Future<void> switchAccount(WidgetTester tester) async {
    await (await SharedPreferences.getInstance())
        .setInt(AppConstants.keyUserId, 88);
    setupApiClientToken('synthetic-b');
    await tester.pump();
  }

  testWidgets('档案笔记保存失败保留输入和损坏原文件', (tester) async {
    await open(tester);
    await tester.tap(find.text('编辑笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '看盘判断'), '未保存的新笔记');
    const damaged = '[{"broken"';
    await tester.runAsync(() => file(77).writeAsString(damaged));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await settle(tester);
    expect(find.text('未保存的新笔记'), findsOneWidget);
    expect(find.text('保存失败，输入已保留，原有档案未覆盖'), findsOneWidget);
    expect(await tester.runAsync(() => file(77).readAsString()), damaged);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in ['删除', '编辑']) {
    testWidgets('切号后旧$action确认不能改动新账号同ID档案', (tester) async {
      await open(tester);
      final before = await tester.runAsync(() => file(88).readAsString());
      if (action == '删除') {
        await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      } else {
        await tester.tap(find.text('编辑'));
      }
      await tester.pumpAndSettle();
      await switchAccount(tester);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await tester.runAsync(() => file(88).readAsString()), before);
      expect(find.text('账号已切换，请重新进入当前页面'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
