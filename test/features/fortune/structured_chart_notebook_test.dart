import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_archive_store.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_models.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_archive_store.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_models.dart';
import 'package:xuanyu/shared/widgets/chart_case_notebook.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['astrology', 'qizheng']) {
    final birth = DateTime(2000, 1, 1, 12);
    final profile = kind == 'astrology'
        ? AstrologyProfile(
            name: '合成案例',
            birthDateTime: birth,
            birthPlace: '北京',
            longitude: 116.4,
            latitude: 39.9)
        : QizhengProfile(
            name: '合成案例',
            birthDateTime: birth,
            birthPlace: '北京',
            longitude: 116.4,
            latitude: 39.9);
    Future<dynamic> save() => kind == 'astrology'
        ? AstrologyArchiveStore.save(profile as AstrologyProfile, isSelf: false)
        : QizhengArchiveStore.save(profile as QizhengProfile, isSelf: false);
    Future<List<dynamic>> load() async => kind == 'astrology'
        ? await AstrologyArchiveStore.loadAll()
        : await QizhengArchiveStore.loadAll();
    Future<void> update(String id,
            {String title = '验证标题',
            String reasoning = '看盘依据',
            String feedback = '实际反馈'}) =>
        kind == 'astrology'
            ? AstrologyArchiveStore.updateCase(id,
                caseTitle: title,
                reasoningNotes: reasoning,
                commentary: feedback,
                expectedUserId: 77)
            : QizhengArchiveStore.updateCase(id,
                caseTitle: title,
                reasoningNotes: reasoning,
                commentary: feedback,
                expectedUserId: 77);
    final key = '${kind}_archive_records_v1_user_77';

    test('$kind 旧笔记完整迁移、三字段持久化和重排保留，清空判断不复活旧文', () async {
      SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
      final original = await save();
      final json = Map<String, dynamic>.from(original.toJson() as Map)
        ..remove('caseTitle')
        ..remove('reasoningNotes')
        ..remove('commentary')
        ..['note'] = List.filled(800, '旧笔记').join('\n');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode([json]));
      final legacy = (await load()).single;
      expect(legacy.reasoningNotes, json['note']);
      expect(legacy.commentary, '');
      await update(legacy.id as String,
          reasoning: legacy.reasoningNotes as String);
      final updated = (await load()).single;
      expect(updated.caseTitle, '验证标题');
      expect(updated.reasoningNotes, json['note']);
      expect(updated.commentary, '实际反馈');
      final recalculated = await save();
      expect(recalculated.id, original.id);
      expect(recalculated.caseTitle, updated.caseTitle);
      expect(recalculated.reasoningNotes, updated.reasoningNotes);
      expect(recalculated.commentary, updated.commentary);
      await update(original.id as String, reasoning: '');
      final cleared = (await load()).single;
      expect(cleared.reasoningNotes, '');
      expect(cleared.commentary, '实际反馈');
      expect(cleared.hasCaseNotes, isTrue);
    });

    test('$kind 切号、档案损坏或已删除时不能写入并保留原数据', () async {
      SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
      final original = await save();
      final prefs = await SharedPreferences.getInstance();
      const damaged = '[{"broken"';
      await prefs.setString(key, damaged);
      await expectLater(update(original.id as String), throwsFormatException);
      expect(prefs.getString(key), damaged);
      await prefs.setString(key, '[]');
      await expectLater(update(original.id as String), throwsStateError);
      final otherKey = '${kind}_archive_records_v1_user_88';
      final otherData = jsonEncode([original.toJson()]);
      await prefs.setString(otherKey, otherData);
      await prefs.setInt(AppConstants.keyUserId, 88);
      await expectLater(update(original.id as String), throwsStateError);
      expect(prefs.getString(otherKey), otherData);
      expect(prefs.getString(key), '[]');
    });
  }

  for (final width in [360.0, 440.0]) {
    testWidgets('笔记面板 $width 窄屏大字体、键盘下可滚动编辑三个字段且保存不关闭', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final title = TextEditingController(text: '合成案例 · 档案笔记');
      final reasoning = TextEditingController(text: '旧笔记完整保留');
      final feedback = TextEditingController();
      final scroll = ScrollController();
      addTearDown(title.dispose);
      addTearDown(reasoning.dispose);
      addTearDown(feedback.dispose);
      addTearDown(scroll.dispose);
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: const TextScaler.linear(1.5),
                  viewInsets: const EdgeInsets.only(bottom: 200)),
              child: Scaffold(
                  body: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                          width: width - 20,
                          height: 300,
                          child: ChartCaseNotebook(
                              scrollController: scroll,
                              titleController: title,
                              reasoningController: reasoning,
                              commentaryController: feedback,
                              onSave: () async {
                                saves++;
                              },
                              onClose: () {})))))));
      expect(find.text('笔记标题'), findsOneWidget);
      expect(find.text('看盘判断'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      final feedbackField = find
          .byWidgetPredicate((w) => w is TextField && w.controller == feedback);
      await tester.ensureVisible(feedbackField);
      await tester.enterText(feedbackField, '新增现实反馈');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(saves, 1);
      expect(feedback.text, '新增现实反馈');
      expect(find.byType(ChartCaseNotebook), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
