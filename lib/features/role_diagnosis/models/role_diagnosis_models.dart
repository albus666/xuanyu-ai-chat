import 'package:flutter/material.dart';
import 'package:xuanyu/core/theme/app_colors.dart';

/// 诊断六维
enum DiagnosisDimension {
  career('事业', '💼'),
  love('感情', '❤️'),
  wealth('财富', '💰'),
  emotion('情绪', '🧠'),
  health('健康', '🏥'),
  social('人际', '👥');

  const DiagnosisDimension(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// 单维度诊断内容
class DimDiagnosis {
  const DimDiagnosis({
    required this.diagnosis,
    required this.prescription,
    required this.action,
  });

  final String diagnosis;
  final String prescription;
  final String action;
}

/// 六维雷达
class RadarScores {
  const RadarScores({
    required this.money,
    required this.pressure,
    required this.peach,
    required this.roast,
    required this.blame,
    required this.slack,
  });

  final int money; // 搞钱力
  final int pressure; // 抗压值
  final int peach; // 桃花缘
  final int roast; // 清醒洞察力
  final int blame; // 背锅率
  final int slack; // 摸鱼天赋

  List<double> get values01 => [
        money / 100,
        pressure / 100,
        peach / 100,
        roast / 100,
        blame / 100,
        slack / 100,
      ];

  List<(String, int)> get items => [
        ('搞钱力', money),
        ('抗压值', pressure),
        ('桃花缘', peach),
        ('清醒洞察力', roast),
        ('背锅率', blame),
        ('摸鱼天赋', slack),
      ];

  Map<String, dynamic> toJson() => {
        'money': money,
        'pressure': pressure,
        'peach': peach,
        'roast': roast,
        'blame': blame,
        'slack': slack,
      };

  factory RadarScores.fromJson(Map<String, dynamic> j) => RadarScores(
        money: (j['money'] as num).toInt(),
        pressure: (j['pressure'] as num).toInt(),
        peach: (j['peach'] as num).toInt(),
        roast: (j['roast'] as num).toInt(),
        blame: (j['blame'] as num).toInt(),
        slack: (j['slack'] as num).toInt(),
      );
}

/// 从命盘直接归纳的摘要，供结果页展示和本地持久化。
class RoleDiagnosisInsights {
  const RoleDiagnosisInsights({
    required this.tuning,
    required this.circulation,
    required this.favorableElements,
    required this.unfavorableElements,
    required this.interactions,
    required this.shenSha,
  });

  final String tuning;
  final String circulation;
  final List<String> favorableElements;
  final List<String> unfavorableElements;
  final List<String> interactions;
  final List<String> shenSha;

  Map<String, dynamic> toJson() => {
        'tuning': tuning,
        'circulation': circulation,
        'favorableElements': favorableElements,
        'unfavorableElements': unfavorableElements,
        'interactions': interactions,
        'shenSha': shenSha,
      };

  factory RoleDiagnosisInsights.fromJson(Map<String, dynamic> json) =>
      RoleDiagnosisInsights(
        tuning: json['tuning'] as String? ?? '五行节奏仍在校准中',
        circulation: json['circulation'] as String? ?? '平衡',
        favorableElements:
            List<String>.from(json['favorableElements'] as List? ?? const []),
        unfavorableElements:
            List<String>.from(json['unfavorableElements'] as List? ?? const []),
        interactions:
            List<String>.from(json['interactions'] as List? ?? const []),
        shenSha: List<String>.from(json['shenSha'] as List? ?? const []),
      );
}

/// 完整诊断报告
class RoleDiagnosisReport {
  const RoleDiagnosisReport({
    required this.tag,
    required this.verdict,
    required this.matchScore,
    required this.radar,
    required this.story,
    required this.dimensions,
    required this.dayMaster,
    required this.pillars,
    required this.dominantGod,
    required this.genderMale,
    required this.birthDate,
    required this.birthHour,
    required this.insights,
  });

  final String tag;
  final String verdict;
  final int matchScore;
  final RadarScores radar;
  final String story;
  final Map<DiagnosisDimension, DimDiagnosis> dimensions;
  final String dayMaster;
  final String pillars;
  final String dominantGod;
  final bool genderMale;
  final DateTime birthDate;
  final int birthHour;
  final RoleDiagnosisInsights insights;

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'verdict': verdict,
        'matchScore': matchScore,
        'radar': radar.toJson(),
        'story': story,
        'dimensions': {
          for (final e in dimensions.entries)
            e.key.name: {
              'diagnosis': e.value.diagnosis,
              'prescription': e.value.prescription,
              'action': e.value.action,
            },
        },
        'dayMaster': dayMaster,
        'pillars': pillars,
        'dominantGod': dominantGod,
        'genderMale': genderMale,
        'birthDate': birthDate.toIso8601String(),
        'birthHour': birthHour,
        'insights': insights.toJson(),
      };

  factory RoleDiagnosisReport.fromJson(Map<String, dynamic> j) =>
      RoleDiagnosisReport(
        tag: j['tag'] as String,
        verdict: j['verdict'] as String,
        matchScore: (j['matchScore'] as num).toInt(),
        radar: RadarScores.fromJson(j['radar'] as Map<String, dynamic>),
        story: j['story'] as String,
        dimensions: {
          for (final e in (j['dimensions'] as Map<String, dynamic>).entries)
            DiagnosisDimension.values.byName(e.key): DimDiagnosis(
              diagnosis: (e.value as Map)['diagnosis'] as String,
              prescription: (e.value as Map)['prescription'] as String,
              action: (e.value as Map)['action'] as String,
            ),
        },
        dayMaster: j['dayMaster'] as String,
        pillars: j['pillars'] as String,
        dominantGod: j['dominantGod'] as String,
        genderMale: j['genderMale'] as bool,
        birthDate: DateTime.parse(j['birthDate'] as String),
        birthHour: (j['birthHour'] as num).toInt(),
        insights: RoleDiagnosisInsights.fromJson(
          Map<String, dynamic>.from(j['insights'] as Map? ?? const {}),
        ),
      );

  /// 服务端 V7 规则引擎返回的报告。接口四柱是对象，本地缓存是字符串。
  factory RoleDiagnosisReport.fromApiJson(Map<String, dynamic> j) {
    final pillars = Map<String, dynamic>.from(j['pillars'] as Map);
    return RoleDiagnosisReport(
      tag: j['tag'] as String,
      verdict: j['verdict'] as String,
      matchScore: (j['matchScore'] as num).toInt(),
      radar: RadarScores.fromJson(Map<String, dynamic>.from(j['radar'] as Map)),
      story: j['story'] as String,
      dimensions: {
        for (final entry
            in Map<String, dynamic>.from(j['dimensions'] as Map).entries)
          DiagnosisDimension.values.byName(entry.key): DimDiagnosis(
            diagnosis: (entry.value as Map)['diagnosis'] as String,
            prescription: (entry.value as Map)['prescription'] as String,
            action: (entry.value as Map)['action'] as String,
          ),
      },
      dayMaster: j['dayMaster'] as String,
      pillars:
          ['year', 'month', 'day', 'hour'].map((key) => pillars[key]).join(' '),
      dominantGod: j['dominantGod'] as String,
      genderMale:
          !{'female', 'f', '女', '0'}.contains((j['gender'] ?? '').toString()),
      birthDate: DateTime.parse(j['birthDate'] as String),
      birthHour: int.parse((j['birthTime'] as String).split(':').first),
      insights: RoleDiagnosisInsights.fromJson(
        Map<String, dynamic>.from(j['insights'] as Map? ?? const {}),
      ),
    );
  }
}

/// 角色诊断书视觉色板（与首页 AppColors 统一）
class RoleDiagColors {
  RoleDiagColors._();

  static const Color bg = AppColors.background;
  static const Color gold = AppColors.primary;
  static const Color goldLight = AppColors.primaryLight;
  static const Color trustBlue = AppColors.primaryDark;
  static const Color card = AppColors.surface;
  static const Color cardBorder = AppColors.divider;
  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textMuted = AppColors.textHint;
}
