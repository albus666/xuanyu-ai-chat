import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_pattern.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_pattern_catalog.dart';

void main() {
  group('斗数格局识别', () {
    test('太阴独坐亥宫时优先识别月朗天门', () {
      final pattern = ZiweiPatternRecognizer.recognize(_moonlitGateChart());

      expect(pattern.name, '月朗天门格');
      expect(pattern.classic, isTrue);
      expect(pattern.badgeLabel, '成格较有力');
      expect(pattern.evidence, contains('太阴独坐亥宫入庙'));
      expect(pattern.evidence, contains('夜生加力'));
    });

    test('同时会到日月时不会把月朗天门误判为日月并明', () {
      final pattern = ZiweiPatternRecognizer.recognize(_moonlitGateChart());

      expect(pattern.name, isNot('日月并明格'));
      expect(pattern.name, '月朗天门格');
    });

    test('太阴不是独坐或不得地时不强套月朗天门', () {
      final notAlone = ZiweiPatternRecognizer.recognize(
        _moonlitGateChart(
          extraSoulMajor: const [
            ZiweiStar(
              name: '天同',
              type: 'major',
              scope: 'origin',
              brightness: '庙',
              mutagen: '',
            ),
          ],
        ),
      );
      final notBright = ZiweiPatternRecognizer.recognize(
        _moonlitGateChart(moonBrightness: '得'),
      );

      expect(notAlone.name, isNot('月朗天门格'));
      expect(notBright.name, isNot('月朗天门格'));
    });

    test('吉曜与煞忌只调整成格状态，不改变格局名称', () {
      final supported = ZiweiPatternRecognizer.recognize(
        _moonlitGateChart(
          minorStars: {
            7: const [
              ZiweiStar(
                name: '文昌',
                type: 'minor',
                scope: 'origin',
                brightness: '庙',
                mutagen: '',
              ),
            ],
          },
        ),
      );
      final challenged = ZiweiPatternRecognizer.recognize(
        _moonlitGateChart(
          adjectiveStars: {
            5: const [
              ZiweiStar(
                name: '擎羊',
                type: 'adjective',
                scope: 'origin',
                brightness: '陷',
                mutagen: '',
              ),
            ],
          },
        ),
      );

      expect(supported.name, '月朗天门格');
      expect(supported.badgeLabel, '成格较有力');
      expect(challenged.name, '月朗天门格');
      expect(challenged.badgeLabel, '成格受煞忌影响');
    });

    test('明珠出海、机月同梁、三奇嘉会和日照雷门均可精确识别', () {
      final pearl = ZiweiPatternRecognizer.recognize(
        _chart(
          soulIndex: 7,
          majorStars: {
            3: [_star('太阳')],
            11: [_star('太阴')],
          },
        ),
      );
      final machineMoon = ZiweiPatternRecognizer.recognize(
        _chart(
          soulIndex: 0,
          majorStars: {
            0: [_star('天机')],
            4: [_star('太阴')],
            6: [_star('天同')],
            8: [_star('天梁')],
          },
        ),
      );
      final threeWonders = ZiweiPatternRecognizer.recognize(
        _chart(
          soulIndex: 0,
          majorStars: {
            0: [_star('天机', mutagen: '禄')],
            4: [_star('武曲', mutagen: '权')],
            8: [_star('天梁', mutagen: '科')],
          },
        ),
      );
      final sunrise = ZiweiPatternRecognizer.recognize(
        _chart(
          soulIndex: 3,
          majorStars: {
            3: [_star('太阳')],
          },
          time: '午时',
        ),
      );

      expect(pearl.name, '明珠出海格');
      expect(machineMoon.name, '机月同梁格');
      expect(threeWonders.name, '三奇嘉会格');
      expect(sunrise.name, '日照雷门格');
      expect(sunrise.badgeLabel, '成格较有力');
    });

    test('87项格局目录完整、编号唯一且条件不为空', () {
      expect(ziweiPatternCatalog, hasLength(87));
      expect(
        ziweiPatternCatalog.map((item) => item.code).toSet(),
        {for (var code = 1; code <= 87; code++) code},
      );
      expect(
        ziweiPatternCatalog.every(
          (item) => item.name.isNotEmpty && item.condition.isNotEmpty,
        ),
        isTrue,
      );
      expect(
        ziweiPatternCatalog
            .where((item) => !item.automatic)
            .map((item) => item.code),
        containsAll(const [52, 76, 78, 79, 81, 82, 83, 84, 85, 86, 87]),
      );
    });
  });
}

ZiweiChartData _moonlitGateChart({
  String moonBrightness = '庙',
  List<ZiweiStar> extraSoulMajor = const [],
  Map<int, List<ZiweiStar>> minorStars = const {},
  Map<int, List<ZiweiStar>> adjectiveStars = const {},
}) =>
    _chart(
      soulIndex: 11,
      palaceNames: const {3: '官禄'},
      majorStars: {
        11: [
          _star('太阴', brightness: moonBrightness),
          ...extraSoulMajor,
        ],
        5: [_star('天机')],
        3: [_star('太阳'), _star('天梁')],
      },
      minorStars: minorStars,
      adjectiveStars: adjectiveStars,
    );

ZiweiChartData _chart({
  required int soulIndex,
  required Map<int, List<ZiweiStar>> majorStars,
  Map<int, List<ZiweiStar>> minorStars = const {},
  Map<int, List<ZiweiStar>> adjectiveStars = const {},
  Map<int, String> palaceNames = const {},
  String time = '子时',
}) {
  const branches = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  final palaces = [
    for (var index = 0; index < 12; index++)
      ZiweiPalace(
        index: index,
        name: palaceNames[index] ?? (index == soulIndex ? '命宫' : '宫$index'),
        isBodyPalace: false,
        isOriginalPalace: index == soulIndex,
        heavenlyStem: '甲',
        earthlyBranch: branches[index],
        majorStars: majorStars[index] ?? const [],
        minorStars: minorStars[index] ?? const [],
        adjectiveStars: adjectiveStars[index] ?? const [],
        changsheng12: '长生',
        boshi12: '博士',
        jiangqian12: '将星',
        suiqian12: '岁驿',
        decadal: ZiweiDecadal(
          startAge: index * 10 + 1,
          endAge: index * 10 + 10,
          heavenlyStem: '甲',
          earthlyBranch: branches[index],
        ),
        ages: const [],
      ),
  ];
  final scope = _scope();
  return ZiweiChartData(
    engineName: 'iztro',
    engineVersion: 'test',
    ruleCode: 'test',
    astrolabe: ZiweiAstrolabe(
      gender: '男',
      solarDate: '1990-01-01',
      lunarDate: '测试',
      chineseDate: '测试',
      time: time,
      timeRange: '23:00~01:00',
      sign: '',
      zodiac: '',
      bodyPalaceBranch: branches[soulIndex],
      soulPalaceBranch: branches[soulIndex],
      soul: '',
      body: '',
      fiveElementsClass: '',
      palaces: palaces,
    ),
    horoscope: ZiweiHoroscope(
      solarDate: '2026-01-01',
      lunarDate: '测试',
      decadal: scope,
      age: scope,
      yearly: scope,
      monthly: scope,
      daily: scope,
      hourly: scope,
    ),
  );
}

ZiweiStar _star(
  String name, {
  String brightness = '庙',
  String mutagen = '',
}) =>
    ZiweiStar(
      name: name,
      type: 'major',
      scope: 'origin',
      brightness: brightness,
      mutagen: mutagen,
    );

ZiweiScope _scope() => const ZiweiScope(
      index: 0,
      name: '本命',
      heavenlyStem: '甲',
      earthlyBranch: '子',
      palaceNames: [],
      mutagen: [],
      stars: [],
    );
