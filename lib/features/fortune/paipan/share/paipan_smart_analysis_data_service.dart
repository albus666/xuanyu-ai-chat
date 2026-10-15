import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/bazi_result.dart';
import 'paipan_shared.dart';

/// 智能分析结果（与原 AI 返回结构一致，便于 UI 复用）
class SmartAnalysisResult {
  final Map<String, String> dayGanSection;
  final Map<String, String> monthDayHourSection;
  /// 近十年流年十神解说；每项含 `title`、`body`（`body` 为 tip + 吉象/凶象，块间空行）
  final List<Map<String, String>> tenYearLuck;

  const SmartAnalysisResult({
    required this.dayGanSection,
    required this.monthDayHourSection,
    required this.tenYearLuck,
  });
}

/// 公历年对应的流年干支（与排盘 `liuNian` 所用 `(year-4)%60` 一致）
String solarYearLiuNianGanZhi(int solarYear) {
  const gan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
  const zhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  final idx = ((solarYear - 4) % 60 + 60) % 60;
  return '${gan[idx % 10]}${zhi[idx % 12]}';
}

/// 从本地 assets 组装智能分析（日干论命 + 月日时命理 + 近十年流年十神），无 AI、无网络。
///
/// 支持 60_jia_zi.json 中日柱为扁平八字段，或 `common` + `man`/`woman`（按性别合并）。
Future<SmartAnalysisResult> loadSmartAnalysisFromData(
  BaziResult result, {
  required bool isFemale,
}) async {
  final dayGanSection = <String, String>{};
  final monthDayHourSection = <String, String>{};

  final dayPillar = '${result.dayGan}${result.dayZhi}';
  final monthPillar = '${result.monthGan}${result.monthZhi}';
  final timeZhi = result.timeZhi;

  // 日干论命：60_jia_zi.json，key=日柱（common+man/woman 嵌套 Map 须用 _mapFromJsonDynamic，否则 is Map<String,dynamic> 易失败）
  try {
    final str = await rootBundle.loadString('assets/bz/data/60_jia_zi.json');
    final data = _mapFromJsonDynamic(_decodeJson(str));
    final dayData = data != null ? _mapFromJsonDynamic(data[dayPillar]) : null;
    if (dayData != null) {
      final map = _flattenJiaZiDaySection(dayData, isFemale: isFemale);
      for (final k in map.entries) {
        if (k.value.isNotEmpty) dayGanSection[k.key] = k.value;
      }
    }
  } catch (_) {}

  // 日柱断语：day.json，key=日柱
  try {
    final str = await rootBundle.loadString('assets/bz/data/day.json');
    final data = _decodeJson(str) as Map<String, dynamic>?;
    final dayDesc = _str(data?[dayPillar]);
    if (dayDesc.isNotEmpty) monthDayHourSection['日'] = dayDesc;
  } catch (_) {}

  // 月柱命理：month.json，key=月柱
  try {
    final str = await rootBundle.loadString('assets/bz/data/month.json');
    final data = _decodeJson(str) as Map<String, dynamic>?;
    final monthDesc = _str(data?[monthPillar]);
    if (monthDesc.isNotEmpty) monthDayHourSection['月'] = monthDesc;
  } catch (_) {}

  // 时辰命理：hour.json，key=时支
  try {
    final str = await rootBundle.loadString('assets/bz/data/hour.json');
    final data = _decodeJson(str) as Map<String, dynamic>?;
    final hourDesc = _str(data?[timeZhi]);
    if (hourDesc.isNotEmpty) monthDayHourSection['时'] = hourDesc;
  } catch (_) {}

  final tenYearLuck = await _loadTenYearLuckByShiShen(result);

  return SmartAnalysisResult(
    dayGanSection: dayGanSection,
    monthDayHourSection: monthDayHourSection,
    tenYearLuck: tenYearLuck,
  );
}

/// [shi_shen.json] 近十年用：仅 `tip` + 吉象、凶象；块之间单换行以缩小段间距（非行高）。
String _shiShenBodyTenYearLuck(Map<String, dynamic> node) {
  final parts = <String>[];
  final tip = _str(node['tip']);
  if (tip.isNotEmpty) parts.add(tip);

  final infos = node['infos'];
  if (infos is List) {
    for (final item in infos) {
      final m = _mapFromJsonDynamic(item);
      if (m == null) continue;
      final label = _str(m['label']);
      if (label != '吉象' && label != '凶象') continue;
      final value = _str(m['value']);
      if (value.isEmpty) continue;
      parts.add('$label：$value');
    }
  }
  return parts.join('\n');
}

/// 自当前公历年起连续 10 年：流年天干相对日主之十神 + [shi_shen.json] 心性解说。
Future<List<Map<String, String>>> _loadTenYearLuckByShiShen(BaziResult result) async {
  final dayGan = result.dayGan;
  final shenByTargetGan = paipanKShenFullMap[dayGan];
  if (shenByTargetGan == null) return [];

  Map<String, dynamic>? shiShenRoot;
  try {
    final raw = await rootBundle.loadString('assets/bz/data/shi_shen.json');
    shiShenRoot = _mapFromJsonDynamic(_decodeJson(raw));
  } catch (_) {}

  final startYear = DateTime.now().year;
  final out = <Map<String, String>>[];
  for (var i = 0; i < 10; i++) {
    final y = startYear + i;
    final gz = solarYearLiuNianGanZhi(y);
    final liuGan = gz.isNotEmpty ? gz[0] : '';
    final shen = shenByTargetGan[liuGan];
    if (shen == null || shen.isEmpty) continue;

    var body = '';
    final nodeMap = shiShenRoot != null ? _mapFromJsonDynamic(shiShenRoot[shen]) : null;
    if (nodeMap != null) {
      body = _shiShenBodyTenYearLuck(nodeMap);
    }
    if (body.isEmpty) {
      body = '该年流年天干为$liuGan，相对日主为「$shen」。可结合原局喜忌、大运流年刑冲合害综合参断，以下资料为十神通论心性，非单独吉凶判定。';
    }

    out.add({
      'title': '$y年 · 流年$gz · 十神：$shen',
      'body': body,
    });
  }
  return out;
}

Map<String, String> _flattenJiaZiDaySection(
  Map<String, dynamic> dayData, {
  required bool isFemale,
}) {
  final common = _mapFromJsonDynamic(dayData['common']);
  if (common != null) {
    final branchKey = isFemale ? 'woman' : 'man';
    final b = _mapFromJsonDynamic(dayData[branchKey]);
    String fromBranch(String k) {
      if (b == null) return '';
      return _str(b[k]);
    }

    String character() {
      final v = fromBranch('character');
      if (v.isNotEmpty) return v;
      return _str(common['character']);
    }

    String love() {
      final v = fromBranch('love');
      if (v.isNotEmpty) return v;
      return _str(common['love']);
    }

    return {
      '日干心性': _str(common['temperament']),
      '日干层次': _str(common['level']),
      '日干支分析': _str(common['analysis']),
      '性格分析': character(),
      '爱情分析': love(),
      '事业分析': _str(common['cause']),
      '财运分析': _str(common['luck']),
      '健康分析': _str(common['health']),
    };
  }

  return {
    '日干心性': _str(dayData['temperament']),
    '日干层次': _str(dayData['level']),
    '日干支分析': _str(dayData['analysis']),
    '性格分析': _str(dayData['character']),
    '爱情分析': _str(dayData['love']),
    '事业分析': _str(dayData['cause']),
    '财运分析': _str(dayData['luck']),
    '健康分析': _str(dayData['health']),
  };
}

String _str(dynamic v) {
  if (v == null) return '';
  final s = '$v'.trim();
  return s.replaceAll(r'\r\n', '\n').replaceAll(r'\n', '\n');
}

/// `jsonDecode` 得到的嵌套 Map 在运行时未必是 `Map<String, dynamic>`，直接 `is Map<String, dynamic>` 会失败，导致读不到 shi_shen / 60_jia_zi 等嵌套字段。
Map<String, dynamic>? _mapFromJsonDynamic(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return Map<String, dynamic>.from(
      value.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
  return null;
}

dynamic _decodeJson(String raw) =>
    raw.isNotEmpty ? jsonDecode(raw) : null;
