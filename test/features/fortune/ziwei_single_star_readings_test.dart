import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_single_star_readings.dart';

void main() {
  final chart = _chart();

  test('单星断宫按现有宫位返回合规文案', () {
    final reading = ZiweiSingleStarReadings.forChart(
      chart,
      ZiweiReadingTopic.relationship,
    ).single;

    expect(reading.star, '巨门');
    expect(reading.summary, contains('沟通'));
    expect(reading.detail, contains('事实、感受和需求'));
    expect(reading.detail, isNot(contains('一定')));
    expect(reading.detail, isNot(contains('第三者')));
  });

  test('隐藏来源时只保留自然的自我画像表达', () {
    final detail = ZiweiSingleStarReadings.detailFor(
      chart,
      ZiweiReadingTopic.relationship,
      showStarNames: false,
    );

    expect(detail, isNot(contains('巨门')));
    expect(detail, isNot(contains('夫妻宫')));
    expect(detail, isNot(contains('斗数')));
    expect(detail, contains('关系'));
  });

  test('空宫直接借对宫主星生成本宫解读', () {
    final emptyRelationshipChart = _chart(emptyPalaceIndex: 10);
    final reading = ZiweiSingleStarReadings.forChart(
      emptyRelationshipChart,
      ZiweiReadingTopic.relationship,
    ).single;

    expect(reading.star, '武曲');
    expect(
      ZiweiSingleStarReadings.summaryFor(
        emptyRelationshipChart,
        ZiweiReadingTopic.relationship,
      ),
      isNot(contains('复合')),
    );
  });
}

ZiweiChartData _chart({int? emptyPalaceIndex}) {
  const emptyScope = ZiweiScope(
    index: 0,
    name: '',
    heavenlyStem: '',
    earthlyBranch: '',
    palaceNames: [],
    mutagen: [],
    stars: [],
  );
  const emptyDecadal = ZiweiDecadal(
    startAge: 1,
    endAge: 10,
    heavenlyStem: '甲',
    earthlyBranch: '子',
  );
  ZiweiStar star(String name) => ZiweiStar(
        name: name,
        type: 'major',
        scope: 'origin',
        brightness: '',
        mutagen: '',
      );
  ZiweiPalace palace(int index, String name, String branch, String starName) =>
      ZiweiPalace(
        index: index,
        name: name,
        isBodyPalace: false,
        isOriginalPalace: false,
        heavenlyStem: '甲',
        earthlyBranch: branch,
        majorStars: index == emptyPalaceIndex ? const [] : [star(starName)],
        minorStars: const [],
        adjectiveStars: const [],
        changsheng12: '',
        boshi12: '',
        jiangqian12: '',
        suiqian12: '',
        decadal: emptyDecadal,
        ages: const [],
      );
  final names = [
    '命宫',
    '父母',
    '福德',
    '田宅',
    '官禄',
    '交友',
    '迁移',
    '疾厄',
    '财帛',
    '子女',
    '夫妻',
    '兄弟',
  ];
  final stars = [
    '紫微',
    '天机',
    '太阴',
    '天府',
    '武曲',
    '天相',
    '太阳',
    '廉贞',
    '天梁',
    '天同',
    '巨门',
    '七杀',
  ];
  const branches = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  return ZiweiChartData(
    engineName: 'test',
    engineVersion: '1',
    ruleCode: 'test',
    astrolabe: ZiweiAstrolabe(
      gender: '男',
      solarDate: '',
      lunarDate: '',
      chineseDate: '',
      time: '',
      timeRange: '',
      sign: '',
      zodiac: '',
      bodyPalaceBranch: '午',
      soulPalaceBranch: '子',
      soul: '',
      body: '',
      fiveElementsClass: '',
      palaces: [
        for (var index = 0; index < names.length; index++)
          palace(index, names[index], branches[index], stars[index]),
      ],
    ),
    horoscope: const ZiweiHoroscope(
      solarDate: '',
      lunarDate: '',
      decadal: emptyScope,
      age: emptyScope,
      yearly: emptyScope,
      monthly: emptyScope,
      daily: emptyScope,
      hourly: emptyScope,
    ),
  );
}
