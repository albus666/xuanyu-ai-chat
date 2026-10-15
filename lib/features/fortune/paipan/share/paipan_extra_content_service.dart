import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/bazi_result.dart';

/// 个人信息使用的现有六十甲子旺衰、用神原文。
///
/// 数据按“日干 + 月柱”从本地 600 条规则中读取，不调用 AI，也不参与或修改
/// 专业细盘的任何计算。
class PaipanExtraContent {
  const PaipanExtraContent({
    this.wangShuai = '',
    this.yongShen = '',
  });

  final String wangShuai;
  final String yongShen;

  bool get hasAny => wangShuai.isNotEmpty || yongShen.isNotEmpty;
}

Map<String, dynamic>? _cached60Decline;

Future<Map<String, dynamic>> _load60Decline() async {
  if (_cached60Decline != null) return _cached60Decline!;
  final source = await rootBundle.loadString('assets/bz/data/60decline.json');
  _cached60Decline = jsonDecode(source) as Map<String, dynamic>;
  return _cached60Decline!;
}

Future<PaipanExtraContent> loadPaipanExtraContent(
  BaziResult result,
  bool isFemale,
) async {
  // 性别保留在签名中以兼容现有调用；六十甲子旺衰/用神表不按性别分表。
  try {
    final data = await _load60Decline();
    final byDay = data[result.dayGan];
    final monthPillar = '${result.monthGan}${result.monthZhi}';
    if (byDay is Map && byDay[monthPillar] is Map) {
      final entry = byDay[monthPillar] as Map;
      return PaipanExtraContent(
        wangShuai: '${entry['ws'] ?? ''}'.trim(),
        yongShen: '${entry['ys'] ?? ''}'.trim(),
      );
    }
  } catch (_) {}
  return const PaipanExtraContent();
}
