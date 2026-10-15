import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/room_chart_sheet.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';

void main() {
  test('房间命盘入口紧邻缩小按钮且不再悬浮在左侧', () {
    final source = File(
      'lib/features/consultation/voice_plaza_room_page.dart',
    ).readAsStringSync();

    final chartButton = source.indexOf('TextButton.icon(\n'
        '                      onPressed: _openRoomCharts');
    final minimizeButton = source.indexOf("tooltip: '缩小房间'", chartButton);
    expect(chartButton, greaterThan(0));
    expect(minimizeButton, greaterThan(chartButton));
    expect(source.substring(chartButton, minimizeButton), contains("'命盘'"));
    expect(
      source.contains('top: MediaQuery.paddingOf(context).top + 58'),
      isFalse,
    );
  });

  test('房间案例直达四类专业盘且新增结果替换输入页', () {
    final roomSource = File(
      'lib/features/consultation/room_chart_sheet.dart',
    ).readAsStringSync();
    final baziSource = File(
      'lib/app/pages/home/bazi/view.dart',
    ).readAsStringSync();
    final ziweiSource = File(
      'lib/features/fortune/ziwei/ziwei_input_page.dart',
    ).readAsStringSync();

    expect(RegExp(r'professionalOnly: true').allMatches(roomSource).length, 3);
    expect(roomSource, contains('replaceInputWithResult: true'));
    expect(
      RegExp(r'professionalOnlyResult: true').allMatches(roomSource).length,
      3,
    );
    expect(roomSource, contains('点击直接查看专业盘面'));
    expect(roomSource, contains('onTap: () => onSelect(rows[index])'));
    expect(roomSource, contains('ListView.separated('));
    expect(roomSource, contains('rows.length > 3'));
    expect(roomSource, contains('loadRoomChartCases()'));
    expect(roomSource, contains('_cases.map((item) => item.archiveFor(_kind))'));
    expect(roomSource, contains('_refreshCases(selectNewest: true)'));
    expect(
      RegExp(r'_showProfessionalChartSheet\(').allMatches(roomSource).length,
      4,
    );
    expect(baziSource, contains('replaceCurrent: replaceInputWithResult'));
    expect(
      ziweiSource,
      contains('replaceCurrent || widget.professionalOnlyResult'),
    );
  });

  test('一个完整案例可在四种专业盘之间互通', () {
    final roomCase = RoomChartCase(
      id: 'shared-case',
      createdAt: DateTime(2026, 9, 23),
      name: '共享案例',
      isSelf: false,
      relationship: ArchiveRelationship.caseRecord,
      birthDateTime: DateTime(2000, 1, 1, 12),
      isFemale: false,
      calendarTypeIndex: 0,
      birthPlace: '北京市',
      longitude: 116.4074,
      latitude: 39.9042,
      snapshots: const {},
    );

    for (final kind in RoomChartKind.values) {
      final archive = roomCase.archiveFor(kind);
      expect(archive.id, 'shared-case');
      expect(archive.kind, kind);
      expect(archive.snapshot, isNotEmpty);
      expect(archive.unavailableReason, isNull);
    }
  });

  test('新建案例返回键使用当前页面 Navigator', () {
    final baziSource = File(
      'lib/app/pages/home/bazi/view.dart',
    ).readAsStringSync();
    final ziweiSource = File(
      'lib/features/fortune/ziwei/ziwei_input_page.dart',
    ).readAsStringSync();

    expect(baziSource, contains('Navigator.of(context).maybePop()'));
    expect(ziweiSource, contains('Navigator.of(context).maybePop()'));
  });

  test('Android 最近任务不再排除玄遇', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, isNot(contains('android:excludeFromRecents="true"')));
    expect(manifest, contains('android:name=".PrivacyConsentActivity"'));
    expect(manifest, contains('android:name=".MainActivity"'));
  });
}
