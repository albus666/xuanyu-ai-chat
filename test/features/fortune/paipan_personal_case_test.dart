import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/fortune/paipan/paipan_personal_info_tab.dart';
import 'package:xuanyu/features/fortune/paipan/paipan_result_host_page.dart';
import 'package:xuanyu/features/fortune/paipan/share/paipan_extra_content_service.dart';
import 'package:xuanyu/features/fortune/paipan/utils/bazi_result.dart';
import 'package:xuanyu/features/fortune/paipan/utils/date_util.dart';

void main() {
  test('案例笔记字段可兼容旧档案并完整序列化', () {
    final record = PaipanRecord(
      id: 'case-1',
      createdAt: DateTime(2026, 8, 12),
      displayName: '测试命主',
      birthDateTime: DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
      calendarTypeIndex: 0,
      summary: '辛巳 己亥 戊戌 丁巳',
      caseTitle: '戊土申月案例',
      reasoningNotes: '先辨旺衰，再看取用。',
      commentary: '批语正文。',
      caseUpdatedAt: DateTime(2026, 8, 12, 22, 30),
    );

    final decoded = PaipanRecord.fromJson(record.toJson());
    expect(decoded.isCase, isTrue);
    expect(decoded.caseTitle, record.caseTitle);
    expect(decoded.reasoningNotes, record.reasoningNotes);
    expect(decoded.commentary, record.commentary);

    final legacy = PaipanRecord.fromJson({
      'id': 'legacy',
      'createdAt': '2026-08-12T00:00:00',
      'birthDateTime': '2001-12-01T10:09:00',
      'summary': '旧档案',
    });
    expect(legacy.isCase, isFalse);
  });

  test('八字档案区分唯一本人与他人关系', () {
    final self = PaipanRecord(
      id: 'self-1',
      createdAt: DateTime(2026, 8, 27),
      displayName: '玄遇用户',
      isSelf: true,
      relationship: ArchiveRelationship.self,
      birthDateTime: DateTime(1992, 3, 5, 9),
      isFemale: true,
      calendarTypeIndex: 0,
      summary: '壬申 壬寅 庚辰 辛巳',
    );
    final decoded = PaipanRecord.fromJson(self.toJson());
    expect(decoded.isSelf, isTrue);
    expect(decoded.relationshipLabel, '本人');

    final legacy = PaipanRecord.fromJson({
      'id': 'old-self',
      'createdAt': '2026-08-01T00:00:00',
      'displayName': '本人',
      'birthDateTime': '1992-03-05T09:00:00',
      'summary': '旧档案',
    });
    expect(legacy.isLegacySelf, isTrue);
    expect(legacy.relationshipLabel, '待整理');
  });

  test('命灵只使用现有用神条文并按日主生成族系', () {
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    final profile = MinglingProfile.from(
      result,
      const PaipanExtraContent(
        wangShuai: '申月戊土身弱。',
        yongShen: '首用丙火，其次丁火。',
      ),
    );

    expect(profile.identity, contains(result.dayGan));
    expect(profile.assetPath, startsWith('assets/mingling_v2/'));
    expect(profile.framePaths, hasLength(4));
    expect(profile.assetPath, endsWith('_full_v3.png'));
    expect(profile.framePaths.toSet(), hasLength(1));
    expect(profile.yongElement, '火');
    expect(profile.xiElement, '火');

    final conditional = MinglingProfile.from(
      result,
      const PaipanExtraContent(
        wangShuai: '身弱。',
        yongShen: '如局内见甲木，则用戊土；其余用丙丁火。',
      ),
    );
    expect(conditional.hasStructuredSupport, isFalse);
    expect(conditional.supportLabel, '助力待综合判断');
  });

  test('命灵差异由完整四柱稳定生成而非只看日主', () {
    final first = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    final second = List.generate(
      80,
      (index) => computeBaziResult(
        DateTime(2001, 12, 2 + index, 10, 9),
        isFemale: false,
      ),
    ).firstWhere(
      (candidate) =>
          candidate.dayGan == first.dayGan &&
          candidate.fourPillarsStr != first.fourPillarsStr,
    );
    const extra = PaipanExtraContent(
      wangShuai: '身弱。',
      yongShen: '首用丙火，其次丁火。',
    );
    final firstProfile = MinglingProfile.from(first, extra);
    final sameAgain = MinglingProfile.from(first, extra);
    final secondProfile = MinglingProfile.from(second, extra);

    expect(firstProfile.ornamentName, sameAgain.ornamentName);
    expect(firstProfile.patternIndex, sameAgain.patternIndex);
    expect(
      '${firstProfile.ornamentName}-${firstProfile.patternIndex}-'
      '${firstProfile.motifIndex}-${firstProfile.secondaryAccent}',
      isNot(
        '${secondProfile.ornamentName}-${secondProfile.patternIndex}-'
        '${secondProfile.motifIndex}-${secondProfile.secondaryAccent}',
      ),
    );
  });

  test('丁火命灵改为完整灯角羊且不再切换错位主体帧', () {
    var date = DateTime(2000, 1, 1, 12);
    var result = computeBaziResult(date, isFemale: false);
    while (result.dayGan != '丁') {
      date = date.add(const Duration(days: 1));
      result = computeBaziResult(date, isFemale: false);
    }
    final profile = MinglingProfile.from(
      result,
      const PaipanExtraContent(),
    );

    expect(profile.name, '灯角羊');
    expect(profile.assetPath, endsWith('ding_lamb_full_v3.png'));
    expect(profile.framePaths.toSet(), hasLength(1));
  });

  test('四柱反推保留六十年候选并可取最近年份', () {
    final matches = DateUtil.datesFromBaZi('丙辰', '丁酉', '丙子', '甲午');

    expect(matches.map((date) => date.year), containsAll(<int>[1916, 1976]));
    final recent = DateUtil.dateFromBaZi(
      '丙辰',
      '丁酉',
      '丙子',
      '甲午',
      near: DateTime(2000),
    );
    expect(recent?.year, 1976);
  });

  test('今日命灵状态由日期与既有喜用规则联动', () {
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    final fixedDate = DateTime(2026, 8, 12);
    final todayGan = dayGanZhiFromDate(fixedDate)[0];
    const ganElements = {
      '甲': '木',
      '乙': '木',
      '丙': '火',
      '丁': '火',
      '戊': '土',
      '己': '土',
      '庚': '金',
      '辛': '金',
      '壬': '水',
      '癸': '水',
    };
    final element = ganElements[todayGan]!;
    final profile = MinglingProfile.from(
      result,
      PaipanExtraContent(
        wangShuai: '身弱。',
        yongShen: '首用$todayGan$element，其次用$todayGan$element。',
      ),
      now: fixedDate,
    );
    final stage = LifeStageProfile.from(result, profile, now: fixedDate);

    expect(profile.state, '舒展');
    expect(profile.todayGanZhi, dayGanZhiFromDate(fixedDate));
    expect(stage.currentDaYunRange, contains('~'));
    expect(stage.currentYearGanZhi, ganZhiForLiuNian(2026));
    expect(stage.focuses, hasLength(3));
  });

  test('同一命盘连续四日文案稳定且不重复', () {
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    const extra = PaipanExtraContent(
      wangShuai: '申月戊土身弱。',
      yongShen: '首用丙火，其次丁火。',
    );
    final dates = List.generate(
      4,
      (index) => DateTime(2026, 8, 13).add(Duration(days: index)),
    );
    final profiles = dates
        .map((date) => MinglingProfile.from(result, extra, now: date))
        .toList();

    expect(
      profiles.map((profile) => profile.stateDescription).toSet(),
      hasLength(4),
    );
    expect(
      MinglingProfile.from(result, extra, now: dates.first).stateDescription,
      profiles.first.stateDescription,
    );
  });

  test('人生阶段由大运与流年共同变化且十年内不套同一句', () {
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    final profile = MinglingProfile.from(
      result,
      const PaipanExtraContent(
        wangShuai: '申月戊土身弱。',
        yongShen: '首用丙火，其次丁火。',
      ),
    );
    final firstStartAge = int.parse(
      RegExp(r'\d+').firstMatch(result.daYunAgeRanges.first)!.group(0)!,
    );
    final firstYear = result.solarDate.year + firstStartAge - 1;
    final stages = List.generate(
      10,
      (offset) => LifeStageProfile.forSelection(
        result,
        profile,
        daYunIndex: 0,
        year: firstYear + offset,
      ),
    );
    final fingerprints = stages
        .map(
          (stage) => [
            ...stage.focuses,
            stage.relationship,
            stage.career,
            stage.wealth,
            stage.status,
          ].join('|'),
        )
        .toSet();

    expect(fingerprints, hasLength(10));

    final nextDaYun = LifeStageProfile.forSelection(
      result,
      profile,
      daYunIndex: 1,
      year: firstYear + 10,
    );
    expect(nextDaYun.currentDaYun, isNot(stages.last.currentDaYun));
    expect(nextDaYun.focuses.first, isNot(stages.last.focuses.first));
  });

  testWidgets('结果页只保留两个入口并提供档案笔记', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: PaipanResultPage(
          birthDateTime: DateTime(2001, 12, 1, 10, 9),
          isFemale: false,
          displayName: '测试命主',
          skipSaveToArchive: true,
          recordId: 'test-record',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('专业细盘'), findsOneWidget);
    expect(find.text('基本命盘'), findsNothing);
    expect(find.text('基础分析'), findsNothing);
    expect(find.byKey(const ValueKey('paipan-case-notebook-action')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('paipan-case-notebook-action')),
    );
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find
          .byKey(const ValueKey('paipan-case-notebook-overlay'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.byKey(const ValueKey('paipan-case-notebook-overlay')),
      findsOneWidget,
    );
    expect(find.text('边看命盘边写，自动归入当前档案'), findsOneWidget);
    final detailScroll = find.byKey(const ValueKey('paipan-detail-scroll'));
    final scrollableState = tester.state<ScrollableState>(
      find
          .descendant(
            of: detailScroll,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final beforeDrag = scrollableState.position.pixels;
    await tester.dragFrom(
      const Offset(200, 180),
      const Offset(0, -180),
    );
    await tester.pump();
    final afterDrag = scrollableState.position.pixels;
    expect(afterDrag, greaterThan(beforeDrag));
    expect(
      find.byKey(const ValueKey('paipan-case-notebook-overlay')),
      findsOneWidget,
    );
  });

  testWidgets('个人信息展示全身命灵、人生阶段并删除命主资料', (tester) async {
    final result = computeBaziResult(
      DateTime(2001, 12, 1, 10, 9),
      isFemale: false,
    );
    await tester.pumpWidget(
      GetMaterialApp(
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

    expect(
        find.byKey(const ValueKey('mingling-full-body-hero')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mingling-facing-left')),
      findsOneWidget,
    );
    final heroFacing = tester.widget<Transform>(
      find.byKey(const ValueKey('mingling-facing-left')),
    );
    expect(heroFacing.transform.storage.first, 1);
    expect(find.text('命主资料'), findsNothing);
    expect(find.text('命灵详情'), findsNothing);
    expect(find.text('分享'), findsNothing);
    expect(find.text('为什么'), findsNothing);
    expect(find.text('当前人生阶段'), findsOneWidget);
    expect(find.text('查看运势轨迹'), findsOneWidget);
    expect(find.textContaining('数据直接取自专业细盘'), findsNothing);
    expect(find.textContaining('页面只将现有条文'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mingling-facing-right')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('paipan-personal-info-content')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mingling-facing-right')),
      findsOneWidget,
    );
    final compactFacing = tester.widget<Transform>(
      find.byKey(const ValueKey('mingling-facing-right')),
    );
    expect(compactFacing.transform.storage.first, -1);

    for (var index = 0; index < 4; index++) {
      await tester.drag(
        find.byKey(const ValueKey('paipan-personal-info-content')),
        const Offset(0, -500),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('认识自己'), findsOneWidget);
    expect(find.textContaining('先把自己点亮'), findsOneWidget);

    for (var index = 0; index < 4; index++) {
      await tester.drag(
        find.byKey(const ValueKey('paipan-personal-info-content')),
        const Offset(0, 500),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }

    final stage = LifeStageProfile.from(
        result,
        MinglingProfile.from(
          result,
          const PaipanExtraContent(
            wangShuai: '申月戊土身弱。',
            yongShen: '首用丙火，其次丁火。',
          ),
        ));
    await tester.tap(find.byKey(const ValueKey('life-stage-year-next')));
    await tester.pump();
    expect(find.text(ganZhiForLiuNian(stage.currentYear + 1)), findsWidgets);

    await tester.drag(
      find.byKey(const ValueKey('paipan-personal-info-content')),
      const Offset(0, -500),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('mingling-day-3')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fortune-trajectory-action')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('fortune-trajectory-inline')),
        findsOneWidget);
    expect(find.text('大运'), findsWidgets);
    expect(find.text('流年'), findsWidgets);
    expect(find.text('打开专业细盘核对'), findsNothing);
  });
}
