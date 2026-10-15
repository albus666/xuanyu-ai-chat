// Run explicitly: passing assertions reproduce defects, not acceptance criteria.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/room_chart_sheet.dart';
import 'package:xuanyu/features/fortune/paipan/paipan_detail_chart_tab.dart';

/// Uses the shape returned by the existing server birth-data scrubber.
/// This probe records the current broken professional-chart presentation.
void main() {
  testWidgets('缺陷复现：默认隐藏出生资料后共享八字退化为四柱摘要', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () => showRoomChartSnapshot(
              context,
              kind: RoomChartKind.bazi,
              title: '审计案例',
              snapshot: const {
                'id': 'audit-case',
                'name': '审计案例',
                'isFemale': false,
                'summary': '甲子 丙寅 戊辰 庚午',
              },
            ),
            child: const Text('打开共享盘'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('打开共享盘'));
    await tester.pumpAndSettle();
    expect(find.byType(PaipanDetailChartTab), findsNothing);
    expect(find.text('甲子'), findsOneWidget);
    expect(find.text('发布者已隐藏出生资料，仅展示获授权的专业盘面快照。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
