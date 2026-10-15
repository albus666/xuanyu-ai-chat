import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_page.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_page.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/fortune/shared_chart_archive.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  late Directory directory;
  late PathProviderPlatform paths;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUserId: 77,
      'unrelated-account-birth-profile': 'keep'
    });
    directory = await Directory.systemTemp.createTemp('unified-chart-test-');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
    await PaipanRecordStore.save(PaipanRecord(
        id: 'self',
        createdAt: DateTime(2026),
        displayName: '我的命盘',
        isSelf: true,
        birthDateTime: DateTime(2000, 1, 1, 12),
        isFemale: true,
        calendarTypeIndex: 0,
        summary: '己卯 丙子 戊午 戊午'));
  });
  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 15 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  for (final entry in <String, Widget>{
    '星盘': const AstrologyArchivePage(),
    '七政四余': const QizhengArchivePage()
  }.entries) {
    testWidgets('${entry.key}采用统一分类并允许删除本人及待补全档案', (tester) async {
      await tester.pumpWidget(MaterialApp(home: entry.value));
      await settle(tester);
      for (final label in ['全部', '本人', '亲友', '有笔记', '写笔记', '编辑']) {
        expect(find.text(label), findsWidgets);
      }
      final delete = find.byTooltip('删除档案');
      expect(delete, findsOneWidget);
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.textContaining('账号出生资料保留'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
          jsonDecode(await tester.runAsync(() =>
                  File('${directory.path}/paipan_records_user_77.json')
                      .readAsString()) ??
              '[]'),
          hasLength(1));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await settle(tester);
      for (var i = 0;
          i < 150 && find.byTooltip('删除档案').evaluate().isNotEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
          jsonDecode(await tester.runAsync(() =>
                  File('${directory.path}/paipan_records_user_77.json')
                      .readAsString()) ??
              '[]'),
          isEmpty);
      expect(find.byTooltip('删除档案'), findsNothing);
      expect(
          (await SharedPreferences.getInstance())
              .getString('unrelated-account-birth-profile'),
          'keep');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  test('统一档案笔记保存到原始记录且账号切换后拒绝旧编辑', () async {
    final record = (await loadRoomChartCases()).single;
    await updateRoomChartCaseNotes(record,
        caseTitle: '重点',
        reasoningNotes: '记录',
        commentary: '反馈',
        expectedUserId: 77);
    expect((await PaipanRecordStore.loadAll()).single.reasoningNotes, '记录');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 78);
    await expectLater(
        updateRoomChartCaseNotes(record,
            caseTitle: '覆盖',
            reasoningNotes: '',
            commentary: '',
            expectedUserId: 77),
        throwsStateError);
    expect(await PaipanRecordStore.loadAll(), isEmpty);
  });
}
