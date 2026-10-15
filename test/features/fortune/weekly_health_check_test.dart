import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/weekly_health_check_page.dart';

void main() {
  test('weekly report parses the structured premium summary', () {
    final report = WeeklyHealthReport.fromMap({
      'headline': '本周恢复速度落后于消耗',
      'level': '需要减负',
      'score': 68,
      'trend': '较上次波动增加',
      'keywords': ['睡眠恢复', '情绪压力', '恢复优先'],
      'overview': '本周需要主动减少一部分负荷。',
      'focuses': [
        {
          'title': '睡眠恢复',
          'status': '需要关注',
          'insight': '留意夜醒和醒后的恢复感。',
        },
      ],
      'plan': ['固定上床和起床时间', '每天记录压力触发点'],
      'boundary': '不用于疾病筛查或诊断。',
    });

    expect(report.score, 68);
    expect(report.headline, '本周恢复速度落后于消耗');
    expect(report.focuses.single['status'], '需要关注');
    expect(report.plan, hasLength(2));
  });

  test('three archive entries navigate directly without secondary copy', () {
    final source = File('lib/features/fortune/constitution_test_page.dart')
        .readAsStringSync();

    expect(source, isNot(contains('健康信息单独授权')));
    expect(source, isNot(contains('同意并继续')));
    expect(source, isNot(contains('指尖光电脉搏波转为脉率属性')));
    expect(source, isNot(contains('生成中医舌苔分类，记录苔色')));
    expect(source, contains('Future<void> _open(Widget page)'));
  });

  testWidgets('weekly summary remains scrollable on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final report = WeeklyHealthReport.fromMap({
      'headline': '本周恢复速度落后于消耗',
      'level': '需要减负',
      'score': 68,
      'trend': '较上次波动增加',
      'keywords': ['睡眠恢复', '情绪压力', '恢复优先'],
      'overview': '本周有几项状态持续占用精力，建议先降低负荷并观察恢复速度。',
      'focuses': [
        {
          'title': '睡眠恢复',
          'status': '需要关注',
          'insight': '观察重点是入睡、夜醒和醒后恢复感。',
        },
        {
          'title': '情绪压力',
          'status': '需要关注',
          'insight': '观察重点是紧绷、低落、易怒和放松难度。',
        },
      ],
      'plan': ['固定上床和起床时间', '每天记录压力触发点', '连续工作之间安排短暂停顿'],
      'boundary': '本总结用于个人状态记录和日常养护参考，不用于疾病筛查或诊断。',
    });

    await tester.pumpWidget(MaterialApp(
      home: WeeklyHealthReportView(report: report, onDone: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('本周状态总结'), findsOneWidget);
    expect(find.text('未来 7 天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
