import 'ziwei_models.dart';
import 'ziwei_pattern_catalog.dart';
import 'ziwei_timeline.dart';

class ZiweiPatternRuleMatch {
  const ZiweiPatternRuleMatch({
    required this.definition,
    required this.evidence,
    required this.supported,
    required this.challenged,
  });

  final ZiweiPatternDefinition definition;
  final List<String> evidence;
  final bool supported;
  final bool challenged;

  bool get isChallenging =>
      definition.category == ZiweiPatternCategory.challenging;

  String get statusLabel {
    if (isChallenging) return '需留意的结构';
    if (challenged) return '成格受煞忌影响';
    if (supported) return '成格较有力';
    return '基本成格';
  }
}

class ZiweiPatternRules {
  ZiweiPatternRules._();

  static List<ZiweiPatternRuleMatch> evaluate(ZiweiChartData data) {
    final context = _PatternContext(data);
    final result = <ZiweiPatternRuleMatch>[];
    for (final definition in ziweiPatternCatalog) {
      if (!definition.automatic) continue;
      final evidence = _evidence(definition.code, context);
      if (evidence == null) continue;
      final axis = context.axis;
      final birthTimeSupports = switch (definition.code) {
        9 => context.isDayBirth,
        10 => context.isNightBirth,
        _ => false,
      };
      result.add(
        ZiweiPatternRuleMatch(
          definition: definition,
          evidence: evidence,
          supported: context.hasSupport(axis) || birthTimeSupports,
          challenged: context.hasChallenge(axis),
        ),
      );
    }
    return result;
  }

  static List<String>? _evidence(int code, _PatternContext c) {
    final soul = c.soul;
    final branch = soul.earthlyBranch;
    final axis = c.axis;
    final soulNames = c.names(soul);
    final axisNames = c.namesOf(axis);
    switch (code) {
      case 1:
        return c.soulHasAll(const {'紫微', '天府'}) &&
                const {'寅', '申'}.contains(branch)
            ? ['紫府同守命宫', '命宫在$branch']
            : null;
      case 2:
        return c.axisHasAll(const {'紫微', '天府'}) &&
                c.bright('紫微', axis) &&
                c.bright('天府', axis)
            ? const ['紫微天府会命', '两星庙旺']
            : null;
      case 3:
        return branch == '戌' && soulNames.contains('天府') && c.hasSupport(axis)
            ? const ['天府坐命戌宫', '三方见吉曜']
            : null;
      case 4:
        return soulNames.contains('紫微') &&
                c.axisHasAll(const {'天府', '天相', '左辅', '右弼', '文昌', '文曲'})
            ? const ['紫微坐命', '府相会照', '辅弼昌曲齐会']
            : null;
      case 5:
        return c.axisHasAll(const {'天府', '天相'}) ? const ['天府天相会命'] : null;
      case 6:
        return branch == '午' &&
                soulNames.contains('紫微') &&
                c.hasSupport(axis) &&
                !c.hasChallenge(axis)
            ? const ['紫微坐命午宫', '吉曜会照', '无煞忌冲破']
            : null;
      case 7:
        final axisAssist = c.axisHasAll(const {'左辅', '右弼'});
        final flanked = c.flankedByNames('左辅', '右弼');
        return soulNames.contains('紫微') && (axisAssist || flanked)
            ? ['紫微坐命', flanked ? '辅弼夹命' : '辅弼拱照']
            : null;
      case 8:
        return branch == '午' && soulNames.contains('太阳')
            ? const ['太阳坐命午宫']
            : null;
      case 9:
        return branch == '卯' &&
                soulNames.contains('太阳') &&
                c.bright('太阳', [soul])
            ? ['太阳坐命卯宫', if (c.isDayBirth) '日生加力']
            : null;
      case 10:
        return branch == '亥' &&
                soul.majorStars.length == 1 &&
                soul.majorStars.first.name == '太阴' &&
                c.bright('太阴', [soul])
            ? ['太阴独坐亥宫入庙', if (c.isNightBirth) '夜生加力']
            : null;
      case 11:
        return branch == '辰' && soulNames.contains('太阴')
            ? const ['太阴坐命辰宫']
            : null;
      case 12:
        final first = branch == '丑' &&
            c.starAtBranch('太阳', '巳') &&
            c.starAtBranch('太阴', '酉');
        final second = c.starAtBranch('太阳', '辰') &&
            c.starAtBranch('太阴', '戌') &&
            axisNames.containsAll(const {'太阳', '太阴'});
        return first || second ? [first ? '命丑日巳月酉' : '太阳辰太阴戌', '日月拱照命宫'] : null;
      case 13:
        return branch == '未' &&
                soul.majorStars.isEmpty &&
                c.starAtBranch('太阳', '卯') &&
                c.starAtBranch('太阴', '亥')
            ? const ['命宫在未无正曜', '太阳卯太阴亥会照']
            : null;
      case 14:
        return const {'丑', '未'}.contains(branch) &&
                c.soulHasAll(const {'太阳', '太阴'})
            ? ['日月同坐$branch宫']
            : null;
      case 15:
        return c.flankedByNames('太阳', '太阴') ? const ['太阳太阴夹命'] : null;
      case 16:
        final estate = c.palaceNamed(const {'田宅'});
        if (estate == null) return null;
        final estateAxis = c.axisFor(estate);
        return c.namesOf(estateAxis).containsAll(const {'太阳', '太阴'})
            ? const ['日月会照田宅宫']
            : null;
      case 17:
        return c.axisHasAll(const {'太阳', '太阴'}) &&
                c.bright('太阳', axis) &&
                c.bright('太阴', axis)
            ? const ['日月会命', '两星庙旺']
            : null;
      case 18:
        return c.axisHasAll(const {'太阳', '太阴'}) &&
                c.fallen('太阳', axis) &&
                c.fallen('太阴', axis) &&
                !c.hasSupport(axis)
            ? const ['日月均落陷', '三方无吉救']
            : null;
      case 19:
        return c.axisHasAll(const {'太阳', '天梁', '文昌'}) &&
                (axisNames.contains('禄存') || c.mutagens(axis).contains('禄'))
            ? const ['阳梁昌会', '禄存或化禄同会']
            : null;
      case 20:
        return c.axisHasAll(const {'天机', '太阴', '天同', '天梁'})
            ? const ['机月同梁齐会命宫三方']
            : null;
      case 21:
        return const {'辰', '戌'}.contains(branch) &&
                c.soulHasAll(const {'天机', '天梁'})
            ? ['机梁同守$branch宫']
            : null;
      case 22:
        return axisNames.contains('天梁') &&
                axisNames.intersection(const {'文昌', '文曲'}).isNotEmpty
            ? const ['天梁会昌曲']
            : null;
      case 23:
        return c.soulHasAll(const {'文昌', '文曲'}) && c.isMaoOrYouBirth
            ? const ['昌曲同守命宫', '卯酉时生']
            : null;
      case 24:
        return soulNames.contains('文昌') && c.axisHasAll(const {'左辅', '右弼'})
            ? const ['文昌坐命', '辅弼拱照']
            : null;
      case 25:
        return c.axisHasAll(const {'禄存', '文昌', '文曲'}) ? const ['禄存昌曲拱命'] : null;
      case 26:
        return c.mutagens(axis).contains('科') && axisNames.contains('禄存')
            ? const ['化科会禄存']
            : null;
      case 27:
        return soulNames.contains('廉贞') &&
                c.axisHasAll(const {'文昌', '文曲', '左辅', '右弼'})
            ? const ['廉贞坐命', '昌曲辅弼齐会']
            : null;
      case 28:
        return c.axisHasAll(const {'文昌', '文曲'}) ? const ['文昌文曲拱命'] : null;
      case 29:
        return c.axisHasAll(const {'贪狼', '火星'}) ? const ['贪狼会火星'] : null;
      case 30:
        return c.axisHasAll(const {'贪狼', '铃星'}) ? const ['贪狼会铃星'] : null;
      case 31:
        return const {'寅', '申'}.contains(branch) &&
                soulNames.contains('廉贞') &&
                c.hasSupport(axis)
            ? ['廉贞坐命$branch宫', '吉曜会照']
            : null;
      case 32:
        return const {'辰', '戌'}.contains(branch) && soulNames.contains('武曲')
            ? ['武曲坐命$branch宫']
            : null;
      case 33:
        return const {'丑', '未'}.contains(branch) &&
                c.soulHasAll(const {'武曲', '贪狼'})
            ? ['武贪同坐$branch宫']
            : null;
      case 34:
        return c.axisHasAll(const {'禄存', '天马'}) ? const ['禄存天马会命'] : null;
      case 35:
        final same = c.samePalaceHasNameAndMutagen('禄存', '禄');
        final combined =
            axisNames.contains('禄存') && c.mutagens(axis).contains('禄');
        final sixHarmony = c.sixHarmonyHasSecondFortune;
        return same || combined || sixHarmony
            ? [
                same
                    ? '禄存化禄同宫'
                    : sixHarmony
                        ? '明禄暗禄六合'
                        : '命财官迁双禄会照'
              ]
            : null;
      case 36:
        return c.soulHasFortune && c.darkHarmonyHasFortuneOrScience
            ? const ['命宫见明禄', '暗合宫见禄或科']
            : null;
      case 37:
        return soulNames.contains('天马') && c.flankedByNameAndMutagen('禄存', '禄')
            ? const ['天马坐命', '禄存化禄夹命']
            : null;
      case 38:
        return const {'丑', '辰', '未', '戌'}.contains(branch) &&
                soulNames.contains('擎羊')
            ? ['擎羊坐命$branch墓库']
            : null;
      case 39:
        final soulNoble = soulNames.intersection(const {'天魁', '天钺'});
        final oppositeNoble =
            c.names(c.opposite).intersection(const {'天魁', '天钺'});
        return soulNoble.length == 1 &&
                oppositeNoble.length == 1 &&
                soulNoble.first != oppositeNoble.first
            ? const ['命迁分坐魁钺']
            : null;
      case 40:
        return c.flankedByNames('天魁', '天钺') || c.flankedByNames('左辅', '右弼')
            ? const ['贵曜或辅弼夹命']
            : null;
      case 41:
        return c.mutagens(axis).containsAll(const {'禄', '权', '科'})
            ? const ['命财官迁会齐禄权科']
            : null;
      case 42:
        return c.mutagens(axis).containsAll(const {'禄', '权'})
            ? const ['化禄化权会命']
            : null;
      case 43:
        return c.flankedByTwoGoodMutagens ? const ['禄权科中两种夹命'] : null;
      case 44:
        return c.samePalaceHasAll(const {'左辅', '右弼'}, axis)
            ? const ['左辅右弼同宫会命']
            : null;
      case 45:
        return branch == '午' && soulNames.contains('天梁')
            ? const ['天梁坐命午宫']
            : null;
      case 46:
        return const {'子', '午'}.contains(branch) && soulNames.contains('破军')
            ? ['破军坐命$branch宫']
            : null;
      case 47:
        return const {'寅', '申', '子', '午'}.contains(branch) &&
                soulNames.contains('七杀')
            ? ['七杀坐命$branch宫']
            : null;
      case 48:
        return const {'子', '午'}.contains(branch) &&
                soulNames.contains('巨门') &&
                (c
                        .mutagens(axis)
                        .intersection(const {'禄', '权', '科'}).isNotEmpty ||
                    axisNames.contains('禄存'))
            ? ['巨门坐命$branch宫', '禄权科或禄存会照']
            : null;
      case 49:
        return const {'寅', '申'}.contains(branch) &&
                c.soulHasAll(const {'巨门', '太阳'})
            ? ['巨日同坐$branch宫']
            : null;
      case 50:
        return const {'卯', '酉'}.contains(branch) &&
                c.soulHasAll(const {'巨门', '天机'})
            ? ['巨机同坐$branch宫']
            : null;
      case 51:
        return c.samePalaceHasMutagenAndMalefic('权', axis) &&
                c.mutagens(axis).contains('禄')
            ? const ['化权与煞曜同宫', '化禄会照']
            : null;
      case 53:
        return soul.majorStars.isEmpty ? const ['命宫无十四主星'] : null;
      case 54:
        return const {'卯', '酉'}.contains(branch) &&
                c.soulHasAll(const {'紫微', '贪狼'})
            ? ['紫贪同坐$branch宫']
            : null;
      case 55:
        return c.axisHasAll(const {'七杀', '廉贞'}) ? const ['七杀拱照廉贞'] : null;
      case 56:
        return axisNames.contains('巨门') && c.hasFourMalefic(axis)
            ? const ['巨门会四煞']
            : null;
      case 57:
        return branch == '午' &&
                soulNames.contains('擎羊') &&
                axisNames.contains('天马')
            ? const ['午宫擎羊坐命', '天马会照']
            : null;
      case 58:
        return soulNames.intersection(const {'地空', '地劫'}).isNotEmpty
            ? const ['命宫见地空或地劫']
            : null;
      case 59:
        return c.flankedByNames('地空', '地劫') ? const ['地空地劫夹命'] : null;
      case 60:
        return c.mutagens([soul]).contains('忌') && c.flankedByNames('擎羊', '陀罗')
            ? const ['命宫化忌', '羊陀夹命']
            : null;
      case 61:
        return c.flankedByNames('火星', '铃星') ? const ['火星铃星夹命'] : null;
      case 62:
        return soulNames.contains('天相') && c.flankedByNames('擎羊', '廉贞')
            ? const ['天相坐命', '擎羊廉贞夹命']
            : null;
      case 63:
        return soulNames.contains('天相') && c.flankedByMutagenAndName('忌', '天刑')
            ? const ['天相坐命', '化忌天刑夹命']
            : null;
      case 64:
        return c.hasDistressedLiteraryStar ? const ['昌曲落陷或受煞夹'] : null;
      case 65:
        return c.mutagens(axis).contains('科') && c.hasChallenge(axis)
            ? const ['化科会煞忌']
            : null;
      case 66:
        return axisNames.intersection(const {'天魁', '天钺'}).isNotEmpty &&
                c.hasChallenge(axis)
            ? const ['魁钺会空劫煞曜']
            : null;
      case 67:
        return c.samePalaceHasAllWithMalefic(const {'太阴', '天同'}, axis)
            ? const ['太阴天同同宫遇煞']
            : null;
      case 68:
        return c.axisHasAll(const {'太阳', '太阴'}) &&
                ((c.fallen('太阳', axis) && c.fallen('太阴', axis)) ||
                    c.hasChallenge(axis))
            ? const ['日月落陷或受煞']
            : null;
      case 69:
        return c.samePalaceHasOneFromEach(
                const {'天马'}, const {'地空', '地劫', '旬空', '截空'}, axis)
            ? const ['天马与空亡同宫']
            : null;
      case 70:
        return c.axisHasAll(const {'天梁', '天马'}) ? const ['天梁天马会命'] : null;
      case 71:
        return branch == '酉' && c.soulHasAll(const {'巨门', '天机'})
            ? const ['巨机同坐酉宫']
            : null;
      case 72:
        return soulNames.contains('禄存') && c.flankedByNames('擎羊', '陀罗')
            ? const ['禄存坐命', '羊陀夹命']
            : null;
      case 73:
        return const {'辰', '戌'}.contains(branch) &&
                c.soulHasAll(const {'天机', '天梁'}) &&
                axisNames.contains('擎羊')
            ? ['机梁同坐$branch宫', '擎羊会照']
            : null;
      case 74:
        return axisNames.contains('贪狼') &&
                axisNames.intersection(const {'文昌', '文曲'}).isNotEmpty
            ? const ['贪狼会文昌或文曲']
            : null;
      case 75:
        return c.axisHasAll(const {'武曲', '廉贞'}) && c.hasChallenge(axis)
            ? const ['武曲廉贞会照', '同见煞忌']
            : null;
      case 77:
        return c.countNames(axis, const {'华盖', '地空', '地劫', '旬空', '截空'}) >= 2
            ? const ['命宫三方重见华盖空亡类星曜']
            : null;
      case 80:
        return soulNames.contains('巨门') && c.axisHasAll(const {'火星', '擎羊'})
            ? const ['巨门坐命', '火星擎羊会照']
            : null;
    }
    return null;
  }
}

class _PatternContext {
  _PatternContext(this.data)
      : soul = data.astrolabe.palaces.firstWhere(
          (palace) => palace.earthlyBranch == data.astrolabe.soulPalaceBranch,
        ) {
    axis = axisFor(soul);
    opposite = data.palaceAt((soul.index + 6) % 12);
    left = data.palaceAt((soul.index + 11) % 12);
    right = data.palaceAt((soul.index + 1) % 12);
  }

  static const _supportStars = {
    '左辅',
    '右弼',
    '文昌',
    '文曲',
    '天魁',
    '天钺',
    '禄存',
    '天马',
  };
  static const _malefics = {'擎羊', '陀罗', '火星', '铃星', '地空', '地劫'};

  final ZiweiChartData data;
  final ZiweiPalace soul;
  late final List<ZiweiPalace> axis;
  late final ZiweiPalace opposite;
  late final ZiweiPalace left;
  late final ZiweiPalace right;

  Iterable<ZiweiStar> stars(ZiweiPalace palace) sync* {
    yield* palace.majorStars;
    yield* palace.minorStars;
    yield* palace.adjectiveStars;
  }

  Set<String> names(ZiweiPalace palace) =>
      stars(palace).map((star) => star.name).toSet();

  Set<String> namesOf(Iterable<ZiweiPalace> palaces) =>
      palaces.expand(stars).map((star) => star.name).toSet();

  Set<String> mutagens(Iterable<ZiweiPalace> palaces) => palaces
      .expand(stars)
      .map((star) => star.mutagen)
      .where((value) => value.isNotEmpty)
      .toSet();

  List<ZiweiPalace> axisFor(ZiweiPalace palace) =>
      ZiweiTimelineBuilder.surroundedIndices(palace.index)
          .map(data.palaceAt)
          .toList();

  bool soulHasAll(Set<String> expected) => names(soul).containsAll(expected);
  bool axisHasAll(Set<String> expected) => namesOf(axis).containsAll(expected);

  bool starAtBranch(String star, String branch) => data.astrolabe.palaces.any(
        (palace) =>
            palace.earthlyBranch == branch && names(palace).contains(star),
      );

  ZiweiPalace? palaceNamed(Set<String> expected) {
    for (final palace in data.astrolabe.palaces) {
      if (expected.contains(palace.name)) return palace;
    }
    return null;
  }

  bool bright(String name, Iterable<ZiweiPalace> palaces) =>
      palaces.expand(stars).any((star) =>
          star.name == name && const {'庙', '旺'}.contains(star.brightness));

  bool fallen(String name, Iterable<ZiweiPalace> palaces) => palaces
      .expand(stars)
      .any((star) => star.name == name && star.brightness == '陷');

  bool hasSupport(Iterable<ZiweiPalace> palaces) =>
      namesOf(palaces).intersection(_supportStars).isNotEmpty ||
      mutagens(palaces).intersection(const {'禄', '权', '科'}).isNotEmpty;

  bool hasChallenge(Iterable<ZiweiPalace> palaces) =>
      namesOf(palaces).intersection(_malefics).isNotEmpty ||
      mutagens(palaces).contains('忌');

  bool hasFourMalefic(Iterable<ZiweiPalace> palaces) =>
      namesOf(palaces).intersection(const {'擎羊', '陀罗', '火星', '铃星'}).isNotEmpty;

  bool flankedByNames(String first, String second) =>
      (names(left).contains(first) && names(right).contains(second)) ||
      (names(left).contains(second) && names(right).contains(first));

  bool flankedByNameAndMutagen(String name, String mutagen) =>
      (names(left).contains(name) && mutagens([right]).contains(mutagen)) ||
      (names(right).contains(name) && mutagens([left]).contains(mutagen));

  bool flankedByMutagenAndName(String mutagen, String name) =>
      flankedByNameAndMutagen(name, mutagen);

  bool samePalaceHasAll(Set<String> expected, Iterable<ZiweiPalace> palaces) =>
      palaces.any((palace) => names(palace).containsAll(expected));

  bool samePalaceHasOneFromEach(
    Set<String> first,
    Set<String> second,
    Iterable<ZiweiPalace> palaces,
  ) =>
      palaces.any((palace) {
        final values = names(palace);
        return values.intersection(first).isNotEmpty &&
            values.intersection(second).isNotEmpty;
      });

  bool samePalaceHasNameAndMutagen(String name, String mutagen) =>
      data.astrolabe.palaces.any(
        (palace) =>
            names(palace).contains(name) &&
            mutagens([palace]).contains(mutagen),
      );

  bool samePalaceHasMutagenAndMalefic(
          String mutagen, Iterable<ZiweiPalace> palaces) =>
      palaces.any((palace) =>
          mutagens([palace]).contains(mutagen) &&
          names(palace).intersection(_malefics).isNotEmpty);

  bool samePalaceHasAllWithMalefic(
          Set<String> expected, Iterable<ZiweiPalace> palaces) =>
      palaces.any((palace) =>
          names(palace).containsAll(expected) &&
          names(palace).intersection(_malefics).isNotEmpty);

  int countNames(Iterable<ZiweiPalace> palaces, Set<String> expected) => palaces
      .expand(stars)
      .where((star) => expected.contains(star.name))
      .length;

  bool get soulHasFortune =>
      names(soul).contains('禄存') || mutagens([soul]).contains('禄');

  ZiweiPalace? get darkHarmonyPalace {
    const harmony = {
      '子': '丑',
      '丑': '子',
      '寅': '亥',
      '亥': '寅',
      '卯': '戌',
      '戌': '卯',
      '辰': '酉',
      '酉': '辰',
      '巳': '申',
      '申': '巳',
      '午': '未',
      '未': '午',
    };
    final branch = harmony[soul.earthlyBranch];
    if (branch == null) return null;
    for (final palace in data.astrolabe.palaces) {
      if (palace.earthlyBranch == branch) return palace;
    }
    return null;
  }

  bool get darkHarmonyHasFortuneOrScience {
    final palace = darkHarmonyPalace;
    if (palace == null) return false;
    return names(palace).contains('禄存') ||
        mutagens([palace]).intersection(const {'禄', '科'}).isNotEmpty;
  }

  bool get sixHarmonyHasSecondFortune =>
      soulHasFortune && darkHarmonyHasFortuneOrScience;

  bool get flankedByTwoGoodMutagens {
    final leftValues = mutagens([left]).intersection(const {'禄', '权', '科'});
    final rightValues = mutagens([right]).intersection(const {'禄', '权', '科'});
    return leftValues.isNotEmpty &&
        rightValues.isNotEmpty &&
        leftValues.union(rightValues).length >= 2;
  }

  bool get hasDistressedLiteraryStar {
    for (final palace in axis) {
      final palaceStars = stars(palace).toList();
      final hasLiterary = palaceStars.any((star) =>
          const {'文昌', '文曲'}.contains(star.name) && star.brightness == '陷');
      if (hasLiterary ||
          (names(palace).intersection(const {'文昌', '文曲'}).isNotEmpty &&
              names(palace).intersection(_malefics).isNotEmpty)) {
        return true;
      }
    }
    return flankedByNames('文昌', '擎羊') || flankedByNames('文曲', '陀罗');
  }

  bool get isDayBirth =>
      const {'卯', '辰', '巳', '午', '未', '申'}.any(data.astrolabe.time.contains);
  bool get isNightBirth => !isDayBirth;
  bool get isMaoOrYouBirth =>
      const {'卯', '酉'}.any(data.astrolabe.time.contains);
}
