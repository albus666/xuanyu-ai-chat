import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('个人择日的对方档案入口可选择已有档案或新建后自动带回', () {
    final source = File(
      'lib/app/pages/home/home_index/widgets/month_calendar_sheet.dart',
    ).readAsStringSync();

    expect(source, contains("onTap: () => _showArchivePicker(partner: true)"));
    expect(
      source,
      contains("ValueKey('calendar-create-partner-archive')"),
    );
    expect(source, contains("label: const Text('新建对方档案')"));
    expect(source, contains("partner ? '暂无可选的其他档案'"));
    expect(source, contains('forOther: true'));
    expect(source, contains('replaceInputWithResult: true'));
    expect(source, contains('await _activatePartnerArchive(created)'));
  });
}
