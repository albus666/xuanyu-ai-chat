import 'package:flutter/material.dart';

import 'role_diagnosis_models.dart';

enum LifeAtlasDomain {
  career('事业与创业', '事业', Icons.rocket_launch_outlined),
  wealth('财富与生活', '财富', Icons.savings_outlined),
  love('感情与关系', '感情', Icons.favorite_border_rounded),
  family('家庭与责任', '家庭', Icons.home_outlined),
  growth('成长与低谷', '成长', Icons.auto_awesome_outlined),
  health('身体与生活', '生活', Icons.self_improvement_outlined),
  social('朋友与人际', '人际', Icons.people_alt_outlined),
  journey('远行与世界', '远行', Icons.explore_outlined);

  const LifeAtlasDomain(this.label, this.shortLabel, this.icon);

  final String label;
  final String shortLabel;
  final IconData icon;
}

enum LifeAtlasAnswer {
  yes,
  no,
  skip;

  String get storageValue => name;

  static LifeAtlasAnswer? tryParse(String? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

class LifeAtlasQuestion {
  const LifeAtlasQuestion({
    required this.id,
    required this.domain,
    required this.question,
    required this.quote,
    required this.titles,
    this.sensitive = false,
  });

  final String id;
  final LifeAtlasDomain domain;
  final String question;
  final String quote;
  final List<String> titles;
  final bool sensitive;
}

class LifeAtlasAchievement {
  const LifeAtlasAchievement({
    required this.id,
    required this.title,
    required this.quote,
    required this.domain,
    required this.rarityLabel,
    this.sourceQuestionIds = const [],
    this.hidden = false,
    this.rarityPercent,
    this.eventKey,
    this.sceneKey,
    this.eventSummary,
    this.meaningLabel,
    this.imageUrl,
    this.sceneToken,
    this.aiGenerated = false,
    this.unlockedAt,
  });

  final String id;
  final String title;
  final String quote;
  final LifeAtlasDomain domain;
  final String rarityLabel;
  final List<String> sourceQuestionIds;
  final bool hidden;
  final double? rarityPercent;
  final String? eventKey;
  final String? sceneKey;
  final String? eventSummary;
  final String? meaningLabel;
  final String? imageUrl;
  final String? sceneToken;
  final bool aiGenerated;
  final DateTime? unlockedAt;

  LifeAtlasAchievement copyWith({
    String? rarityLabel,
    double? rarityPercent,
    String? imageUrl,
    String? sceneToken,
    bool? aiGenerated,
    DateTime? unlockedAt,
  }) {
    return LifeAtlasAchievement(
      id: id,
      title: title,
      quote: quote,
      domain: domain,
      rarityLabel: rarityLabel ?? this.rarityLabel,
      sourceQuestionIds: sourceQuestionIds,
      hidden: hidden,
      rarityPercent: rarityPercent ?? this.rarityPercent,
      eventKey: eventKey,
      sceneKey: sceneKey,
      eventSummary: eventSummary,
      meaningLabel: meaningLabel,
      imageUrl: imageUrl ?? this.imageUrl,
      sceneToken: sceneToken ?? this.sceneToken,
      aiGenerated: aiGenerated ?? this.aiGenerated,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'quote': quote,
        'domain': domain.name,
        'rarityLabel': rarityLabel,
        'sourceQuestionIds': sourceQuestionIds,
        'hidden': hidden,
        'rarityPercent': rarityPercent,
        'eventKey': eventKey,
        'sceneKey': sceneKey,
        'eventSummary': eventSummary,
        'meaningLabel': meaningLabel,
        'imageUrl': imageUrl,
        'sceneToken': sceneToken,
        'aiGenerated': aiGenerated,
        'unlockedAt': unlockedAt?.toIso8601String(),
      };

  factory LifeAtlasAchievement.fromJson(Map<String, dynamic> json) {
    final domainName = json['domain']?.toString();
    return LifeAtlasAchievement(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      quote: json['quote']?.toString() ?? '',
      domain: LifeAtlasDomain.values.firstWhere(
        (item) => item.name == domainName,
        orElse: () => LifeAtlasDomain.growth,
      ),
      rarityLabel: json['rarityLabel']?.toString() ?? '人生印记',
      sourceQuestionIds: (json['sourceQuestionIds'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      hidden: json['hidden'] == true,
      rarityPercent: (json['rarityPercent'] as num?)?.toDouble(),
      eventKey: json['eventKey']?.toString(),
      sceneKey: json['sceneKey']?.toString(),
      eventSummary: json['eventSummary']?.toString(),
      meaningLabel: json['meaningLabel']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      sceneToken: json['sceneToken']?.toString(),
      aiGenerated: json['aiGenerated'] == true,
      unlockedAt: DateTime.tryParse(json['unlockedAt']?.toString() ?? ''),
    );
  }
}

class LifeAtlasMeaningOption {
  const LifeAtlasMeaningOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;

  factory LifeAtlasMeaningOption.fromJson(Map<String, dynamic> json) =>
      LifeAtlasMeaningOption(
        id: json['id']?.toString() ?? 'personal_meaning',
        label: json['label']?.toString() ?? '这件事对我有特别意义',
      );
}

class LifeAtlasEventAnalysis {
  const LifeAtlasEventAnalysis({
    required this.eventKey,
    required this.summary,
    required this.domain,
    required this.stage,
    required this.level,
    required this.question,
    required this.options,
  });

  final String eventKey;
  final String summary;
  final LifeAtlasDomain domain;
  final String stage;
  final String level;
  final String question;
  final List<LifeAtlasMeaningOption> options;

  factory LifeAtlasEventAnalysis.fromJson(Map<String, dynamic> json) {
    final domainName = json['domain']?.toString();
    return LifeAtlasEventAnalysis(
      eventKey: json['eventKey']?.toString() ?? 'other_growth',
      summary: json['summary']?.toString() ?? '一件值得记住的事',
      domain: LifeAtlasDomain.values.firstWhere(
        (item) => item.name == domainName,
        orElse: () => LifeAtlasDomain.growth,
      ),
      stage: json['stage']?.toString() ?? 'completed',
      level: json['level']?.toString() ?? 'life_mark',
      question: json['question']?.toString() ?? '这件事对你更像哪一种？',
      options: (json['options'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => LifeAtlasMeaningOption.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'eventKey': eventKey,
        'summary': summary,
        'domain': domain.name,
        'stage': stage,
        'level': level,
        'question': question,
        'options': [
          for (final item in options) {'id': item.id, 'label': item.label},
        ],
      };
}

class LifeAtlasGeneratedTitles {
  const LifeAtlasGeneratedTitles({
    required this.analysis,
    required this.candidates,
  });

  final LifeAtlasEventAnalysis analysis;
  final List<LifeAtlasAchievement> candidates;
}

class LifeAtlasRarityStat {
  const LifeAtlasRarityStat({
    required this.sampleSize,
    required this.sampleSufficient,
    required this.rarityLabel,
    this.percent,
  });

  final int sampleSize;
  final bool sampleSufficient;
  final String rarityLabel;
  final double? percent;

  factory LifeAtlasRarityStat.fromJson(Map<String, dynamic> json) {
    return LifeAtlasRarityStat(
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 0,
      sampleSufficient: json['sampleSufficient'] == true,
      rarityLabel: json['rarityLabel']?.toString() ?? '数据积累中',
      percent: (json['percent'] as num?)?.toDouble(),
    );
  }
}

class LifeAtlasHiddenRule {
  const LifeAtlasHiddenRule({
    required this.id,
    required this.requiredQuestionIds,
    required this.title,
    required this.quote,
    required this.domain,
  });

  final String id;
  final List<String> requiredQuestionIds;
  final String title;
  final String quote;
  final LifeAtlasDomain domain;
}

class LifeAtlasResult {
  const LifeAtlasResult({
    required this.report,
    required this.baseTitle,
    required this.baseQuote,
    required this.achievements,
    required this.hiddenAchievements,
    required this.confirmedQuestionIds,
    required this.answeredCount,
    required this.totalQuestionCount,
  });

  final RoleDiagnosisReport report;
  final String baseTitle;
  final String baseQuote;
  final List<LifeAtlasAchievement> achievements;
  final List<LifeAtlasAchievement> hiddenAchievements;
  final List<String> confirmedQuestionIds;
  final int answeredCount;
  final int totalQuestionCount;

  List<LifeAtlasAchievement> get allAchievements => [
        ...hiddenAchievements,
        ...achievements,
      ];

  LifeAtlasAchievement get recommendedAchievement {
    if (hiddenAchievements.isNotEmpty) return hiddenAchievements.first;
    if (achievements.isNotEmpty) return achievements.first;
    return LifeAtlasAchievement(
      id: 'base_${report.dominantGod}',
      title: baseTitle,
      quote: baseQuote,
      domain: LifeAtlasDomain.growth,
      rarityLabel: '命盘底色',
      sourceQuestionIds: const [],
    );
  }

  int get completionPercent {
    if (totalQuestionCount == 0) return 0;
    return ((answeredCount / totalQuestionCount) * 100).round().clamp(0, 100);
  }
}
