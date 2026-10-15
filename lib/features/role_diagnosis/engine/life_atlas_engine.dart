import '../data/life_atlas_catalog.dart';
import '../models/life_atlas_models.dart';
import '../models/role_diagnosis_models.dart';

class LifeAtlasEngine {
  LifeAtlasEngine._();

  static LifeAtlasResult build({
    required RoleDiagnosisReport report,
    required Map<String, LifeAtlasAnswer> answers,
    Map<String, LifeAtlasRarityStat> rarityStatistics = const {},
  }) {
    final confirmed = answers.entries
        .where((entry) => entry.value == LifeAtlasAnswer.yes)
        .map((entry) => entry.key)
        .toSet();
    final preferred = _preferredDomains(report.dominantGod);
    final achievements = <LifeAtlasAchievement>[];

    for (final question in lifeAtlasQuestions) {
      if (!confirmed.contains(question.id)) continue;
      final seed = _stableHash('${report.pillars}|${question.id}');
      final title = question.titles[seed % question.titles.length];
      final rarity = rarityStatistics[question.id];
      achievements.add(
        LifeAtlasAchievement(
          id: '${question.id}_${seed % question.titles.length}',
          title: title,
          quote: question.quote,
          domain: question.domain,
          rarityLabel:
              rarity?.rarityLabel ?? (question.sensitive ? '珍藏印记' : '人生印记'),
          rarityPercent:
              rarity?.sampleSufficient == true ? rarity?.percent : null,
          sourceQuestionIds: [question.id],
        ),
      );
    }
    achievements.sort((a, b) {
      final aIndex = preferred.indexOf(a.domain);
      final bIndex = preferred.indexOf(b.domain);
      final aScore = aIndex < 0 ? preferred.length : aIndex;
      final bScore = bIndex < 0 ? preferred.length : bIndex;
      return aScore.compareTo(bScore);
    });

    final hidden = <LifeAtlasAchievement>[];
    for (final rule in lifeAtlasHiddenRules) {
      if (!rule.requiredQuestionIds.every(confirmed.contains)) continue;
      hidden.add(
        LifeAtlasAchievement(
          id: rule.id,
          title: rule.title,
          quote: rule.quote,
          domain: rule.domain,
          rarityLabel: '隐藏交汇',
          sourceQuestionIds: rule.requiredQuestionIds,
          hidden: true,
        ),
      );
    }
    hidden.sort((a, b) {
      final aIndex = preferred.indexOf(a.domain);
      final bIndex = preferred.indexOf(b.domain);
      return (aIndex < 0 ? preferred.length : aIndex)
          .compareTo(bIndex < 0 ? preferred.length : bIndex);
    });

    final base = lifeAtlasBaseByGod[report.dominantGod] ??
        const ('自主人生观察者', '你正在用自己的方式，理解并书写正在发生的人生。');
    return LifeAtlasResult(
      report: report,
      baseTitle: base.$1,
      baseQuote: base.$2,
      achievements: achievements,
      hiddenAchievements: hidden,
      confirmedQuestionIds: confirmed.toList(growable: false),
      answeredCount: answers.length,
      totalQuestionCount: lifeAtlasQuestions.length,
    );
  }

  static List<LifeAtlasDomain> _preferredDomains(String dominantGod) {
    return switch (dominantGod) {
      '正官' => [LifeAtlasDomain.career, LifeAtlasDomain.family],
      '七杀' => [LifeAtlasDomain.growth, LifeAtlasDomain.career],
      '正印' => [LifeAtlasDomain.family, LifeAtlasDomain.social],
      '偏印' => [LifeAtlasDomain.growth, LifeAtlasDomain.journey],
      '正财' => [LifeAtlasDomain.wealth, LifeAtlasDomain.family],
      '偏财' => [LifeAtlasDomain.wealth, LifeAtlasDomain.career],
      '食神' => [LifeAtlasDomain.health, LifeAtlasDomain.social],
      '伤官' => [LifeAtlasDomain.career, LifeAtlasDomain.growth],
      '比肩' => [LifeAtlasDomain.social, LifeAtlasDomain.career],
      '劫财' => [LifeAtlasDomain.career, LifeAtlasDomain.journey],
      _ => LifeAtlasDomain.values,
    };
  }

  static int _stableHash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }
}
