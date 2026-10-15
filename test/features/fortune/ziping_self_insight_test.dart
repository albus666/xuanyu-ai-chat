import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/paipan/paipan_personal_info_tab.dart';
import 'package:xuanyu/features/fortune/paipan/share/paipan_extra_content_service.dart';
import 'package:xuanyu/features/fortune/paipan/utils/bazi_result.dart';
import 'package:xuanyu/features/fortune/paipan/utils/ziping_self_insight.dart';

void main() {
  test('认识自己按传统子平组合月令旺衰根气十神与喜用', () {
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    final insights = buildZipingSelfInsights(
      result: result,
      wangShuai: '申月戊土身弱。',
      yongShen: '首用丙火，其次丁火。',
    );

    expect(insights.map((item) => item.title), [
      '命局主线',
      '性情底色',
      '关系模式',
      '事业路径',
      '财富方式',
      '喜忌取舍',
    ]);
    expect(insights.map((item) => item.summary), [
      '先把自己点亮，才接得住外面的机会',
      '表面很稳，心里一直在计算代价',
      '你要的不是热闹，是有人愿意和你一起扛事',
      '适合在复杂里建立秩序，不适合长期靠蛮劲硬撑',
      '不是没有财，而是机会有时来得比承载能力更快',
      '对你来说，先增温，比先增量更重要',
    ]);
    expect(insights.first.detail, contains('${result.dayGan}土日主'));
    expect(insights.first.detail, contains('${result.monthZhi}月'));
    expect(insights.first.detail, contains('月令主气'));
    expect(insights.first.detail, contains('见根'));
    expect(insights[2].detail, contains('夫妻宫'));
    expect(insights[3].detail, contains('为提纲'));
    expect(insights.last.summary, contains('先增温'));
    expect(insights.last.detail, contains('喜用同取火'));
    expect(insights.last.detail, contains('首用丙火，其次丁火'));
    final visibleCopy =
        insights.map((item) => '${item.summary}${item.detail}').join();
    expect(visibleCopy, isNot(contains('现有条文')));
    expect(visibleCopy, isNot(contains('结构化')));
    expect(visibleCopy, isNot(contains('不额外猜测')));
  });

  test('认识自己六项均为分层长解读且不同命局不会套用同组结论', () {
    final first = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    final second = computeBaziResult(
      DateTime(1994, 6, 18, 22, 30),
      isFemale: true,
    );
    final firstInsights = buildZipingSelfInsights(
      result: first,
      wangShuai: '戊土身弱。',
      yongShen: '首用丙火，其次丁火。',
    );
    final secondInsights = buildZipingSelfInsights(
      result: second,
      wangShuai: '日主身强。',
      yongShen: '首用壬水，其次甲木。',
    );

    for (final insight in firstInsights) {
      expect(insight.sections.length, greaterThanOrEqualTo(6));
      expect(insight.detail.length, greaterThan(180));
      expect(insight.sections.last.title, '命局依据');
    }
    expect(
      firstInsights.map((item) => item.summary).toList(),
      isNot(secondInsights.map((item) => item.summary).toList()),
    );
    expect(firstInsights[2].detail, contains('你会怎样表达在意'));
    expect(firstInsights[3].detail, contains('不适合长期待的环境'));
    expect(firstInsights[4].detail, contains('容易漏财或错失的地方'));
    expect(firstInsights[5].detail, contains('落到日常怎么选'));
  });

  testWidgets('手机宽度下命灵完整画面位于英雄区安全边界内', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaipanPersonalInfoTab(
            result: result,
            extraFuture: Future.value(
              const PaipanExtraContent(
                wangShuai: '申月戊土身弱。',
                yongShen: '首用丙火，其次丁火。',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final hero = tester.getRect(
      find.byKey(const ValueKey('mingling-full-body-hero')),
    );
    final visual = tester.getRect(
      find.byKey(const ValueKey('mingling-visual-frame')),
    );
    expect(visual.left, greaterThanOrEqualTo(hero.left));
    expect(visual.right, lessThanOrEqualTo(hero.right));
    expect(visual.top, greaterThanOrEqualTo(hero.top));
    expect(visual.bottom, lessThanOrEqualTo(hero.bottom));
  });

  testWidgets('认识自己详情在手机宽度下可分层滚动且不会溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaipanPersonalInfoTab(
            result: result,
            extraFuture: Future.value(
              const PaipanExtraContent(
                wangShuai: '戊土身弱。',
                yongShen: '首用丙火，其次丁火。',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('命局主线'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('paipan-personal-info-content')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.text('命局主线'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('命局主线'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final detail = find.byKey(
      const ValueKey('self-insight-detail-命局主线'),
    );
    expect(detail, findsOneWidget);
    expect(find.text('核心判断'), findsOneWidget);
    expect(find.textContaining('先把自己点亮'), findsWidgets);
    await tester.drag(detail, const Offset(0, -1000));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('命局依据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('十日主全身命灵素材均使用统一安全画布', (tester) async {
    const paths = <String>[
      'assets/mingling_v2/jia_full_v3.png',
      'assets/mingling_v2/yi_full_v3.png',
      'assets/mingling_v2/bing_full_v3.png',
      'assets/mingling_v2/ding_lamb_full_v3.png',
      'assets/mingling_v2/wu_full_v3.png',
      'assets/mingling_v2/ji_full_v3.png',
      'assets/mingling_v2/geng_full_v3.png',
      'assets/mingling_v2/xin_full_v3.png',
      'assets/mingling_v2/ren_full_v3.png',
      'assets/mingling_v2/gui_full_v3.png',
    ];

    for (final path in paths) {
      final data = await rootBundle.load(path);
      // PNG IHDR 中宽高分别位于字节 16 和 20，为大端无符号整数。
      expect(data.getUint32(16), 720, reason: path);
      expect(data.getUint32(20), 840, reason: path);
    }
  });
}
