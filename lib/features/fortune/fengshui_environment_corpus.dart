import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 本地「金锁玉关」环境分析文案（运行时只读 [structuredAsset]）。
///
/// 若需从原始 Markdown 重新生成 JSON，见 `tools/assets/parse_fengshui_environment.py`（需自备两份源 txt）。
class FengshuiEnvironmentCorpus {
  FengshuiEnvironmentCorpus._();

  static const String structuredAsset =
      'assets/fengshui/environment_palaces.json';

  /// 八卦常见展示顺序（坎离等用于 UI 排序时可参考）。
  static const List<String> guaOrder = ['乾', '兑', '离', '震', '巽', '坎', '艮', '坤'];

  /// 解析后的 JSON 根：卦名（乾坤震巽坎离艮兑）→ 宫数据。
  static Future<Map<String, dynamic>> loadStructuredDocument() async {
    final raw = await rootBundle.loadString(structuredAsset);
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return <String, dynamic>{};
  }

  /// 单宫结构化数据：`title`、`preamble`、`outdoor`、`indoor`、`malformation`。
  static Future<Map<String, dynamic>?> loadPalaceStructured(String gua) async {
    final doc = await loadStructuredDocument();
    final entry = doc[gua];
    if (entry is! Map) return null;
    return Map<String, dynamic>.from(
      entry.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  static List<String> _uniqueKeysFromEntries(List<dynamic>? entries) {
    if (entries == null) return [];
    final seen = <String>{};
    final out = <String>[];
    for (final e in entries) {
      if (e is! Map) continue;
      final k = '${e['key'] ?? ''}'.trim();
      if (k.isEmpty || !seen.add(k)) continue;
      out.add(k);
    }
    out.sort((a, b) => a.compareTo(b));
    return out;
  }

  /// 该宫 [indoor] 中不重复的 `key`（仅室内）。
  static List<String> uniqueIndoorKeys(Map<String, dynamic> palace) {
    return _uniqueKeysFromEntries(palace['indoor'] as List?);
  }

  /// **外环境 + 室内 + 形煞** 全部条目的 `key` 去重排序，供输入联想（如「河」可匹配「河道」「河流」）。
  static List<String> uniqueSuggestKeys(Map<String, dynamic> palace) {
    final seen = <String>{};
    final out = <String>[];
    for (final field in ['outdoor', 'indoor', 'malformation']) {
      final list = palace[field] as List?;
      if (list == null) continue;
      for (final e in list) {
        if (e is! Map) continue;
        final k = '${e['key'] ?? ''}'.trim();
        if (k.isEmpty || !seen.add(k)) continue;
        out.add(k);
      }
    }
    out.sort((a, b) => a.compareTo(b));
    return out;
  }

  static String? _lookupInList(List<dynamic>? entries, String itemKey) {
    if (entries == null) return null;
    final key = itemKey.trim();
    if (key.isEmpty) return null;
    final parts = <String>[];
    for (final e in entries) {
      if (e is! Map) continue;
      if ('${e['key'] ?? ''}'.trim() == key) {
        final t = '${e['text'] ?? ''}'.trim();
        if (t.isNotEmpty) parts.add(t);
      }
    }
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  /// 按物品名精确匹配 [indoor]（同 key 多条则拼接）。
  static String? lookupIndoorDescription(
      Map<String, dynamic> palace, String itemKey) {
    return _lookupInList(palace['indoor'] as List?, itemKey);
  }

  /// 按物品名在 **室内 → 外环境 → 形煞** 顺序查找第一条目文案。
  static String? lookupPalaceDescription(
      Map<String, dynamic> palace, String itemKey) {
    return lookupIndoorDescription(palace, itemKey) ??
        _lookupInList(palace['outdoor'] as List?, itemKey) ??
        _lookupInList(palace['malformation'] as List?, itemKey);
  }

  /// Unicode 码点级 Levenshtein（适合中文短词）。
  static int levenshteinRunes(String a, String b) {
    final la = a.runes.toList();
    final lb = b.runes.toList();
    final m = la.length;
    final n = lb.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var row = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      var prev = row[0];
      row[0] = i;
      for (var j = 1; j <= n; j++) {
        final tmp = row[j];
        final cost = la[i - 1] == lb[j - 1] ? 0 : 1;
        final ins = row[j] + 1;
        final del = row[j - 1] + 1;
        final sub = prev + cost;
        row[j] = ins < del ? (ins < sub ? ins : sub) : (del < sub ? del : sub);
        prev = tmp;
      }
    }
    return row[n];
  }

  /// 在 [allKeys] 中为 [query] 找最相近的收录名：先精确，再前缀/包含，再编辑距离（有阈值）。
  /// 无合适结果时返回 null（不臆造、不调用 AI）。
  static String? findBestMatchingKey(List<String> allKeys, String query) {
    final q = query.trim();
    if (q.isEmpty || allKeys.isEmpty) return null;
    if (allKeys.contains(q)) return q;

    if (q.isNotEmpty) {
      final byPrefix = allKeys.where((k) => k.startsWith(q)).toList()
        ..sort((a, b) {
          final c = a.length.compareTo(b.length);
          return c != 0 ? c : a.compareTo(b);
        });
      if (byPrefix.isNotEmpty) return byPrefix.first;

      final byContains = allKeys.where((k) => k.contains(q)).toList()
        ..sort((a, b) {
          final c = b.length.compareTo(a.length);
          return c != 0 ? c : a.compareTo(b);
        });
      if (byContains.isNotEmpty) return byContains.first;
    }

    if (q.length >= 2) {
      final byQueryWrapsKey =
          allKeys.where((k) => k.length >= 2 && q.contains(k)).toList()
            ..sort((a, b) {
              final c = b.length.compareTo(a.length);
              return c != 0 ? c : a.compareTo(b);
            });
      if (byQueryWrapsKey.isNotEmpty) return byQueryWrapsKey.first;
    }

    final qLen = q.runes.length;
    String? best;
    var bestD = 1 << 30;
    for (final k in allKeys) {
      if (k.isEmpty) continue;
      final d = levenshteinRunes(q, k);
      final kLen = k.runes.length;
      final maxLen = qLen > kLen ? qLen : kLen;
      if (maxLen == 0) continue;
      final norm = d / maxLen;
      final maxAllowed = maxLen <= 3 ? 3 : 4;
      final typoOk = d == 1 && maxLen <= 6;
      if (!typoOk && (d > maxAllowed || norm > 0.45)) continue;
      if (d < bestD ||
          (d == bestD && (best == null || k.compareTo(best) < 0))) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  /// 联想列表用：在无前缀/子串命中时按编辑距离推荐若干 key（比提交匹配的阈值略宽）。
  static List<String> rankKeysBySimilarity(List<String> allKeys, String query,
      {int limit = 24}) {
    final q = query.trim();
    if (q.isEmpty || allKeys.isEmpty) return [];
    final qLen = q.runes.length;
    final scored = <({String k, int d})>[];
    for (final k in allKeys) {
      if (k.isEmpty) continue;
      final d = levenshteinRunes(q, k);
      final maxLen = qLen > k.runes.length ? qLen : k.runes.length;
      if (maxLen == 0) continue;
      final norm = d / maxLen;
      final maxAllowed = maxLen <= 3 ? 4 : 5;
      final typoOk = d <= 2 && maxLen <= 8 && norm <= 0.55;
      if (d > maxAllowed && !typoOk) continue;
      if (norm > 0.55 && !typoOk) continue;
      scored.add((k: k, d: d));
    }
    scored.sort((a, b) {
      final c = a.d.compareTo(b.d);
      return c != 0 ? c : a.k.compareTo(b.k);
    });
    return scored.take(limit).map((e) => e.k).toList();
  }

  /// 精确 → 相近匹配；返回 `(文案, 实际命中的 key)`，均未命中返回 null。
  static ({String description, String matchedKey})?
      lookupPalaceDescriptionWithSimilarity(
    Map<String, dynamic> palace,
    String itemQuery,
  ) {
    final keys = uniqueSuggestKeys(palace);
    final q = itemQuery.trim();
    if (q.isEmpty) return null;

    final exact = lookupPalaceDescription(palace, q);
    if (exact != null && exact.isNotEmpty) {
      return (description: exact, matchedKey: q);
    }

    final key = findBestMatchingKey(keys, q);
    if (key == null || key == q) return null;

    final desc = lookupPalaceDescription(palace, key);
    if (desc == null || desc.isEmpty) return null;
    return (description: desc, matchedKey: key);
  }

  static const String suitableStatus = '适宜状态';
  static const String attentionStatus = '需留意';

  /// 用户端仅使用的二态空间结果。
  ///
  /// 原始资料只承担宫位、砂水和象法规则的内部判断依据，不向用户
  /// 展示其中的健康、婚姻、财富或具体事件断语。缺损、潮湿等现实
  /// 状态优先判为需留意；其余先看主判断，再处理条件不完整的条目。
  static String deriveEnvironmentStatus({
    required String itemKey,
    required String sourceText,
  }) {
    final key = itemKey.trim();
    final text = sourceText.trim();
    if (key.isEmpty || text.isEmpty) return attentionStatus;

    if (_attentionStateKeys.any(key.contains)) return attentionStatus;

    final normalized = text
        .replaceAll('无明显吉凶之象', '平稳状态')
        .replaceAll('无明显凶象', '平稳状态')
        .replaceAll('无明显不利', '平稳状态')
        .replaceAll('无太多不利', '平稳状态')
        .replaceAll('无原则性的大问题', '平稳状态')
        .replaceAll('不以凶论', '平稳状态');

    // “若、但、唯、否则”等之后通常是附加条件。用户没有输入该
    // 条件时，先按条目的主判断归类，避免把“树木健康，但枯败时…”
    // 一律误判为需留意。
    final primary = normalized.split(RegExp(r'[；。](?:若|如若|但|唯|否则|然而)')).first;

    if (_containsAttentionSignal(primary)) return attentionStatus;
    if (_containsSuitableSignal(primary)) return suitableStatus;

    // 主句没有明确结论而全文包含条件风险时，采用审慎结果。
    if (_containsAttentionSignal(normalized)) return attentionStatus;
    return suitableStatus;
  }

  static const List<String> _attentionStateKeys = [
    '发霉',
    '潮湿',
    '渗水',
    '堵塞',
    '污秽',
    '垃圾',
    '恶臭',
    '破裂',
    '脱落',
    '龟裂',
    '裂纹',
    '缺口',
    '缺角',
    '倒伏',
    '鼓包',
    '歪斜',
    '折断',
    '剥离',
    '尖刺',
    '刺手',
    '堆积',
    '土坑',
    '大坑',
    '凹陷',
    '挖空',
  ];

  static bool _containsSuitableSignal(String text) {
    return const [
      '适宜',
      '合宜',
      '得位',
      '平稳',
      '平和',
      '顺遂',
      '吉利',
      '吉庆',
      '祥和',
      '有利',
      '无需特意',
      '无需刻意',
      '无需过度',
      '可以保留',
      '可保留',
      '小吉',
      '中吉',
      '上吉',
      '大吉',
    ].any(text.contains);
  }

  static bool _containsAttentionSignal(String text) {
    return const [
      '不适宜',
      '不合宜',
      '不利',
      '不宜',
      '最忌',
      '禁忌',
      '不可',
      '大凶',
      '凶局',
      '凶煞',
      '路冲',
      '破损',
      '破裂',
      '脱落',
      '发霉',
      '潮湿',
      '渗水',
      '堵塞',
      '污浊',
      '脏乱',
      '异味',
      '恶臭',
      '枯败',
      '倒伏',
      '遮挡',
      '过近',
      '紧邻',
      '直射',
      '尖角',
      '冲射',
      '损耗',
      '受损',
      '阻滞',
      '欠佳',
      '纠纷',
      '灾',
      '病',
      '疾',
      '伤',
    ].any(text.contains);
  }
}
