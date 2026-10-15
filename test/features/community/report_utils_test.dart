import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/community_feedback.dart';
import 'package:xuanyu/core/utils/report_utils.dart';

void main() {
  test('举报内容至少需要10个非空白字符', () {
    expect(isValidReportReason('一二三四五六七八九'), isFalse);
    expect(isValidReportReason('一 二 三 四 五 六 七 八 九'), isFalse);
    expect(isValidReportReason('一二三四五六七八九十'), isTrue);
  });

  test('举报字数按Unicode字符计算', () {
    expect(reportReasonCharacterCount('  举报内容\n需要说清楚  '), 9);
    expect(reportReasonCharacterCount('一二三四五六七八九十'), 10);
  });

  test('举报分类和子原因编码保持唯一', () {
    final categoryCodes = reportCategories.map((item) => item.code).toList();
    final subReasonCodes = reportCategories
        .expand((item) => item.reasons)
        .map((item) => item.code)
        .toList();
    expect(categoryCodes.toSet().length, categoryCodes.length);
    expect(subReasonCodes.toSet().length, subReasonCodes.length);
    expect(reportCategories.every((item) => item.reasons.length >= 4), isTrue);
    expect(
      reportCategories.map((item) => item.label).toList(),
      const [
        '我不喜欢',
        '涉嫌欺诈',
        '涉政不当言论',
        '违法信息',
        '低俗色情',
        '违规广告',
        '危害人身安全',
        '谣言不实',
        '涉未成年人',
        '攻击辱骂',
        '违反公共道德',
        '搬运盗图',
        '侵权行为',
        '其他违规',
      ],
    );
  });

  test('减少推荐原因编码保持唯一并覆盖三类反馈', () {
    final codes = notInterestedReasons.map((item) => item.code).toList();
    final groups = notInterestedReasons.map((item) => item.group).toSet();
    expect(codes.toSet().length, codes.length);
    expect(groups, containsAll(<String>['💔  不感兴趣', '🙃  内容反馈']));
    expect(notInterestedReasons.map((item) => item.label), contains('假人设'));
  });

  testWidgets('举报流程先选大类再进入具体原因和证据页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReportSheet(
              context,
              targetType: 'post',
              targetId: 7,
            ),
            child: const Text('打开举报'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开举报'));
    await tester.pumpAndSettle();
    expect(find.text('我不喜欢'), findsOneWidget);

    await tester.tap(find.text('我不喜欢'));
    await tester.pump();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('举报帖子'), findsOneWidget);
    expect(find.text('不喜欢该内容、该作者或其他不喜欢原因'), findsOneWidget);
    expect(find.text('选择具体原因'), findsOneWidget);
    expect(find.text('图片证据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不喜欢面板完整展示两组参考原因', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showNotInterestedReasonSheet(context),
            child: const Text('打开不喜欢'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开不喜欢'));
    await tester.pumpAndSettle();
    expect(find.text('选择不喜欢的原因，减少相似推荐'), findsOneWidget);
    for (final label in const [
      '不喜欢该作者',
      '不喜欢该内容',
      '标题党博眼球',
      '虚假欺诈',
      '疑似广告',
      '相似过多',
      '色情低俗',
      '引起不适',
      '负向情绪',
      '对立引战',
      '假人设',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
