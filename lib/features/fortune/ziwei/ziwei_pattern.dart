import 'ziwei_models.dart';
import 'ziwei_pattern_catalog.dart';
import 'ziwei_pattern_rules.dart';

enum ZiweiPatternVisual {
  lunarOrbit,
  triad,
  twinCore,
  sunMoon,
  court,
  axis,
}

class ZiweiPatternProfile {
  const ZiweiPatternProfile({
    required this.name,
    required this.headline,
    required this.summary,
    required this.tags,
    required this.keyStars,
    required this.visual,
    required this.paletteIndex,
    this.classic = true,
    this.statusLabel,
    this.evidence = const [],
    this.relatedPatterns = const [],
    this.attentionPatterns = const [],
  });

  final String name;
  final String headline;
  final String summary;
  final List<String> tags;
  final List<String> keyStars;
  final ZiweiPatternVisual visual;
  final int paletteIndex;
  final bool classic;
  final String? statusLabel;
  final List<String> evidence;
  final List<String> relatedPatterns;
  final List<String> attentionPatterns;

  String get badgeLabel => statusLabel ?? (classic ? '基本成格' : '结构识别');
}

/// 只读取专业命盘既有结果，不参与安星、四化或运限计算。
///
/// 格局目录与自动识别分离：目录完整收录用户确认的87项；只有条件足以
/// 转换成确定规则的条目才会自动显示，避免用宽松星系冒充古典格局。
class ZiweiPatternRecognizer {
  ZiweiPatternRecognizer._();

  static List<ZiweiPatternRuleMatch> recognizeAll(ZiweiChartData data) =>
      ZiweiPatternRules.evaluate(data);

  static ZiweiPatternProfile recognize(ZiweiChartData data) {
    final matches = recognizeAll(data);
    final positive = matches
        .where((match) =>
            match.definition.category != ZiweiPatternCategory.challenging &&
            match.definition.category != ZiweiPatternCategory.timing)
        .toList(growable: false)
      ..sort((a, b) {
        final priority = _priority(b.definition.code)
            .compareTo(_priority(a.definition.code));
        return priority != 0
            ? priority
            : a.definition.code.compareTo(b.definition.code);
      });
    final attention = matches
        .where((match) =>
            match.definition.category == ZiweiPatternCategory.challenging)
        .map((match) => match.definition.name)
        .toList(growable: false);

    if (positive.isNotEmpty) {
      final primary = positive.first;
      return _profileFromMatch(
        data,
        primary,
        related:
            positive.skip(1).map((match) => match.definition.name).toList(),
        attention: attention,
      );
    }
    return _fallbackProfile(data, attention: attention);
  }

  static ZiweiPatternProfile _profileFromMatch(
    ZiweiChartData data,
    ZiweiPatternRuleMatch match, {
    required List<String> related,
    required List<String> attention,
  }) {
    final definition = match.definition;
    return ZiweiPatternProfile(
      name: definition.name,
      headline: _headline(definition),
      summary: '${definition.condition}。${_statusSummary(match)}',
      tags: match.evidence.take(3).toList(growable: false),
      keyStars: _keyStars(definition, data),
      visual: _visual(definition),
      paletteIndex: _palette(definition.category),
      statusLabel: match.statusLabel,
      evidence: match.evidence,
      relatedPatterns: related,
      attentionPatterns: attention,
    );
  }

  static ZiweiPatternProfile _fallbackProfile(
    ZiweiChartData data, {
    required List<String> attention,
  }) {
    final soul = data.astrolabe.palaces.firstWhere(
      (palace) => palace.earthlyBranch == data.astrolabe.soulPalaceBranch,
    );
    final borrowed = data.borrowsOppositeMajorStars(soul);
    final majorNames =
        data.effectiveMajorStarsFor(soul).map((star) => star.name).toList();
    final keyStars = majorNames;
    final shownStars = keyStars.isEmpty ? const ['命宫', '三方', '四正'] : keyStars;
    final title = majorNames.isEmpty
        ? '命宫主轴'
        : '${majorNames.join('·')}坐命${borrowed ? '（借对宫）' : ''}';
    final archetypes = shownStars.take(2).map(_archetype).toSet().join('与');
    return ZiweiPatternProfile(
      name: title,
      headline:
          archetypes.isEmpty ? '看见自己的节奏，也看见选择的空间' : '$archetypes，是你稳定向前的内在节奏',
      summary: majorNames.isEmpty
          ? '暂无可用的十四主星线索，以命宫三方四正作为结构主轴。'
          : borrowed
              ? '对宫${majorNames.join('、')}借入命宫，以这组主星结合三方四正呈现个人主轴。'
              : '${majorNames.join('、')}守命，结合命宫三方四正呈现个人主轴。',
      tags: shownStars.take(3).map(_archetype).toSet().toList(),
      keyStars: shownStars.take(4).toList(),
      visual: majorNames.length > 1
          ? ZiweiPatternVisual.twinCore
          : ZiweiPatternVisual.axis,
      paletteIndex: soul.index % 5,
      classic: false,
      attentionPatterns: attention,
    );
  }

  static String _headline(ZiweiPatternDefinition definition) {
    if (definition.code == 10) return '月在天门，细腻之中自有清醒与分寸';
    if (definition.code == 13) return '日月相照，在开阔中找到自己的方向';
    if (definition.code == 20) return '思辨、感受与守序，共同构成你的主轴';
    if (definition.code == 41) return '禄权科会，才能、行动与机会彼此呼应';
    return switch (definition.category) {
      ZiweiPatternCategory.imperial => '在统筹与承担中，慢慢建立自己的位置',
      ZiweiPatternCategory.luminary => '既照见外界，也保留对内心的觉察',
      ZiweiPatternCategory.academic => '将理解力与表达力，变成可以积累的优势',
      ZiweiPatternCategory.wealth => '资源与行动相遇，重点在如何长期承接',
      ZiweiPatternCategory.noble => '关键时刻的选择，比单一标签更能定义你',
      ZiweiPatternCategory.challenging => '这是需要留意的结构，不是对结果的绝对断定',
      ZiweiPatternCategory.timing => '运限的变化，需放回原局中一起理解',
    };
  }

  static int _priority(int code) => switch (code) {
        1 ||
        3 ||
        6 ||
        8 ||
        9 ||
        10 ||
        11 ||
        12 ||
        13 ||
        14 ||
        21 ||
        23 ||
        31 ||
        32 ||
        33 ||
        38 ||
        45 ||
        46 ||
        47 ||
        48 ||
        49 ||
        50 =>
          100,
        4 ||
        19 ||
        20 ||
        27 ||
        29 ||
        30 ||
        35 ||
        37 ||
        39 ||
        41 ||
        43 ||
        51 =>
          90,
        16 => 50,
        _ => 70,
      };

  static String _statusSummary(ZiweiPatternRuleMatch match) {
    if (match.challenged) return '同时见煞忌，格局表现需结合全盘，不作单一吉凶定论';
    if (match.supported) return '同时得吉曜、吉化或生时条件加力';
    return '当前符合基本结构，实际表现仍需结合全盘';
  }

  static List<String> _keyStars(
    ZiweiPatternDefinition definition,
    ZiweiChartData data,
  ) {
    const candidates = {
      '紫微',
      '天机',
      '太阳',
      '武曲',
      '天同',
      '廉贞',
      '天府',
      '太阴',
      '贪狼',
      '巨门',
      '天相',
      '天梁',
      '七杀',
      '破军',
      '文昌',
      '文曲',
      '左辅',
      '右弼',
      '天魁',
      '天钺',
      '禄存',
      '天马',
      '火星',
      '铃星',
    };
    final present = data.astrolabe.palaces
        .expand((palace) => [
              ...palace.majorStars,
              ...palace.minorStars,
              ...palace.adjectiveStars,
            ])
        .map((star) => star.name)
        .where((name) =>
            candidates.contains(name) && definition.condition.contains(name))
        .toSet()
        .take(4)
        .toList();
    return present.isEmpty ? const ['命宫', '三方', '四正'] : present;
  }

  static ZiweiPatternVisual _visual(ZiweiPatternDefinition definition) {
    if (definition.category == ZiweiPatternCategory.luminary) {
      return definition.name.contains('月')
          ? ZiweiPatternVisual.lunarOrbit
          : ZiweiPatternVisual.sunMoon;
    }
    if (definition.name.contains('同宫')) return ZiweiPatternVisual.twinCore;
    if (definition.name.contains('朝垣') || definition.name.contains('庆会')) {
      return ZiweiPatternVisual.court;
    }
    if (definition.name.contains('三奇') || definition.name.contains('三合')) {
      return ZiweiPatternVisual.triad;
    }
    return ZiweiPatternVisual.axis;
  }

  static int _palette(ZiweiPatternCategory category) => switch (category) {
        ZiweiPatternCategory.luminary => 0,
        ZiweiPatternCategory.imperial => 1,
        ZiweiPatternCategory.academic => 2,
        ZiweiPatternCategory.wealth => 3,
        ZiweiPatternCategory.noble => 4,
        ZiweiPatternCategory.challenging => 3,
        ZiweiPatternCategory.timing => 2,
      };

  static String _archetype(String star) => switch (star) {
        '紫微' => '统筹',
        '天机' => '思辨',
        '太阳' => '担当',
        '武曲' => '执行',
        '天同' => '包容',
        '廉贞' => '原则',
        '天府' => '沉稳',
        '太阴' => '细腻',
        '贪狼' => '体验',
        '巨门' => '洞察',
        '天相' => '协调',
        '天梁' => '守护',
        '七杀' => '决断',
        '破军' => '重建',
        '禄存' => '积累',
        '天马' => '行动',
        _ => star,
      };
}
