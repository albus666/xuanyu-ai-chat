import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/features/role_diagnosis/data/life_atlas_catalog.dart';
import 'package:xuanyu/features/role_diagnosis/engine/life_atlas_engine.dart';
import 'package:xuanyu/features/role_diagnosis/engine/life_atlas_narrative_fallback.dart';
import 'package:xuanyu/features/role_diagnosis/models/life_atlas_models.dart';
import 'package:xuanyu/features/role_diagnosis/models/role_diagnosis_models.dart';
import 'package:xuanyu/features/role_diagnosis/role_diagnosis_result_page.dart';
import 'package:xuanyu/features/role_diagnosis/widgets/life_atlas_scene.dart';

void main() {
  test('人生图鉴提供超过五百个原创基础与交汇称号', () {
    final uniqueTitles =
        lifeAtlasQuestions.expand((item) => item.titles).toSet();
    expect(lifeAtlasQuestions.length, 48);
    expect(
        lifeAtlasQuestions.every((item) => item.titles.length == 11), isTrue);
    expect(lifeAtlasCuratedTitleCount, greaterThan(500));
    expect(uniqueTitles.length, greaterThan(500));
  });

  test('没有主动确认经历时不会由八字推断真实人生称号', () {
    final result = LifeAtlasEngine.build(report: _report(), answers: const {});

    expect(result.achievements, isEmpty);
    expect(result.hiddenAchievements, isEmpty);
    expect(result.recommendedAchievement.rarityLabel, '命盘底色');
  });

  test('只有经历过会点亮称号，还没有与跳过都不会点亮', () {
    final result = LifeAtlasEngine.build(
      report: _report(),
      answers: const {
        'career_start': LifeAtlasAnswer.yes,
        'wealth_debt': LifeAtlasAnswer.no,
        'love_leave': LifeAtlasAnswer.skip,
      },
    );

    expect(result.achievements, hasLength(1));
    expect(result.achievements.single.sourceQuestionIds, ['career_start']);
    expect(result.confirmedQuestionIds, ['career_start']);
  });

  test('两段真实经历同时成立才点亮隐藏交汇称号', () {
    final one = LifeAtlasEngine.build(
      report: _report(),
      answers: const {'career_start': LifeAtlasAnswer.yes},
    );
    final both = LifeAtlasEngine.build(
      report: _report(),
      answers: const {
        'career_start': LifeAtlasAnswer.yes,
        'journey_city': LifeAtlasAnswer.yes,
      },
    );

    expect(one.hiddenAchievements, isEmpty);
    expect(
      both.hiddenAchievements.any((item) => item.id == 'cross_city_founder'),
      isTrue,
    );
  });

  test('同一四柱和经历始终生成同一称号', () {
    const answers = {'career_start': LifeAtlasAnswer.yes};
    final first = LifeAtlasEngine.build(report: _report(), answers: answers);
    final second = LifeAtlasEngine.build(report: _report(), answers: answers);

    expect(first.achievements.single.id, second.achievements.single.id);
    expect(first.achievements.single.title, second.achievements.single.title);
  });

  test('真实样本充分后才把匿名点亮比例带入称号', () {
    final insufficient = LifeAtlasEngine.build(
      report: _report(),
      answers: const {'career_start': LifeAtlasAnswer.yes},
      rarityStatistics: const {
        'career_start': LifeAtlasRarityStat(
          sampleSize: 29,
          sampleSufficient: false,
          rarityLabel: '数据积累中',
        ),
      },
    );
    final sufficient = LifeAtlasEngine.build(
      report: _report(),
      answers: const {'career_start': LifeAtlasAnswer.yes},
      rarityStatistics: const {
        'career_start': LifeAtlasRarityStat(
          sampleSize: 120,
          sampleSufficient: true,
          rarityLabel: '稀有',
          percent: 6.7,
        ),
      },
    );

    expect(insufficient.achievements.single.rarityPercent, isNull);
    expect(insufficient.achievements.single.rarityLabel, '数据积累中');
    expect(sufficient.achievements.single.rarityPercent, 6.7);
    expect(sufficient.achievements.single.rarityLabel, '稀有');
  });

  test('自由输入考上编制后只追问一次并生成三个不偏题称号', () {
    final analysis = LifeAtlasNarrativeFallback.analyze('今天考上编制了');
    final meaning = analysis.options.firstWhere(
      (item) => item.id == 'long_wait',
    );
    final candidates = LifeAtlasNarrativeFallback.generate(
      input: '今天考上编制了',
      analysis: analysis,
      meaning: meaning,
      report: _report(),
    );

    expect(analysis.eventKey, 'exam_staff_passed');
    expect(analysis.question, '这次考上，对你最像哪一种？');
    expect(candidates, hasLength(3));
    expect(candidates.map((item) => item.title).toSet(), hasLength(3));
    expect(
        candidates.every((item) => item.eventKey == analysis.eventKey), isTrue);
    expect(candidates.any((item) => item.title.contains('创业')), isFalse);
  });

  test('第一次去国外使用远行人物场景且不会冒充用户经历', () {
    final analysis = LifeAtlasNarrativeFallback.analyze('第一次去国外');
    final candidates = LifeAtlasNarrativeFallback.generate(
      input: '第一次去国外',
      analysis: analysis,
      meaning: analysis.options.first,
      report: _report(),
    );

    expect(analysis.eventKey, 'overseas_first');
    expect(analysis.domain, LifeAtlasDomain.journey);
    expect(
        candidates.every((item) => item.sceneKey == 'overseas_first'), isTrue);
    expect(candidates.any((item) => item.title.contains('考上')), isFalse);
  });

  test('人生事件和八个领域均映射到正式电影场景资产', () {
    expect(
      LifeAtlasScene.assetFor(
        LifeAtlasDomain.career,
        'exam_staff_passed',
      ),
      'assets/life_atlas_v2/scene_exam.webp',
    );
    expect(
      LifeAtlasScene.assetFor(
        LifeAtlasDomain.journey,
        'overseas_first',
      ),
      'assets/life_atlas_v2/scene_overseas.webp',
    );
    for (final domain in LifeAtlasDomain.values) {
      expect(
        LifeAtlasScene.assetFor(domain, null),
        startsWith('assets/life_atlas_v2/scene_'),
      );
    }
  });

  testWidgets('人生图鉴结果在360像素手机宽度无布局异常', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = LifeAtlasEngine.build(
      report: _report(),
      answers: const {
        'career_start': LifeAtlasAnswer.yes,
        'career_rebuild': LifeAtlasAnswer.yes,
        'journey_city': LifeAtlasAnswer.yes,
      },
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, child) => MaterialApp(
          home: RoleDiagnosisResultPage(result: result),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('我的人生图鉴'), findsOneWidget);
    expect(find.text('二次点火'), findsWidgets);
    expect(find.text('生成分享图'), findsOneWidget);
  });
}

RoleDiagnosisReport _report() {
  const dimensions = <DiagnosisDimension, DimDiagnosis>{
    DiagnosisDimension.career: DimDiagnosis(
      diagnosis: '',
      prescription: '',
      action: '',
    ),
  };
  return RoleDiagnosisReport(
    tag: '测试底色',
    verdict: '测试',
    matchScore: 95,
    radar: const RadarScores(
      money: 60,
      pressure: 70,
      peach: 50,
      roast: 80,
      blame: 40,
      slack: 30,
    ),
    story: '',
    dimensions: dimensions,
    dayMaster: '甲',
    pillars: '甲子 丙寅 甲辰 辛未',
    dominantGod: '偏财',
    genderMale: true,
    birthDate: DateTime(1990, 1, 1),
    birthHour: 13,
    insights: const RoleDiagnosisInsights(
      tuning: '',
      circulation: '',
      favorableElements: [],
      unfavorableElements: [],
      interactions: [],
      shenSha: [],
    ),
  );
}
