import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';

class HealthSection {
  final String title;
  final String content;
  const HealthSection(this.title, this.content);
}

class HealthFocus {
  final String bodyArea;
  final String summary;
  final String? ageRange;

  const HealthFocus({
    required this.bodyArea,
    required this.summary,
    this.ageRange,
  });

  factory HealthFocus.fromMap(Map<String, dynamic>? map) {
    final area = map?['bodyArea']?.toString().trim() ?? '';
    final summary = map?['summary']?.toString().trim() ?? '';
    final ageRange = map?['ageRange']?.toString().trim();
    return HealthFocus(
      bodyArea: area.isEmpty ? '整体精力与作息节律' : area,
      summary: summary.isEmpty ? '保持规律作息与温和活动，连续劳累后给身体留出恢复时间。' : summary,
      ageRange: ageRange?.isNotEmpty == true ? ageRange : null,
    );
  }
}

class TodayHealthController extends GetxController {
  TodayHealthController();
  final _scope = ApiSessionScope();
  int _request = 0;

  @override
  void onInit() {
    super.onInit();
    apiSessionChanges.addListener(_accountChanged);
  }

  @override
  void onClose() {
    apiSessionChanges.removeListener(_accountChanged);
    _request++;
    super.onClose();
  }

  void _accountChanged() {
    _request++;
    _applyMap({});
    tempHigh = tempLow = weather = '—';
    sections = [const HealthSection('提示', apiSessionChangedMessage)];
    update(['health']);
  }

  String tempHigh = '—';
  String tempLow = '—';
  String weather = '—';
  String tizhi = '体质';
  String jieqi = '节气';
  String date = '';
  bool healthFocusAvailable = true;
  String healthFocusSource = '账号个人信息';
  String healthFocusMessage = '';
  bool weeklyCheckDue = false;
  bool weeklyHasBaseline = false;
  String weeklyCheckMessage = '';
  List<String> archiveSources = const [];
  String recommendationDirection = '均衡稳定';
  List<String> recommendationPrinciples = const ['食材多样', '三餐规律', '少油少糖'];
  HealthFocus natalFocus = const HealthFocus(
    bodyArea: '整体精力与作息节律',
    summary: '保持规律作息与温和活动，连续劳累后给身体留出恢复时间。',
  );
  HealthFocus decadalFocus = const HealthFocus(
    bodyArea: '睡眠、消化与活动节律',
    summary: '当前阶段宜减少连续熬夜与久坐，活动和饮食以循序渐进为主。',
  );

  List<HealthSection> sections = <HealthSection>[
    const HealthSection('养生建议', '加载中…'),
  ];

  static String _todayString() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _formatTemp(dynamic t) {
    if (t == null) return '';
    if (t is num) return t.round().toString();
    final raw = t.toString().replaceAll('℃', '').trim();
    final n = num.tryParse(raw);
    if (n != null) return n.round().toString();
    return raw;
  }

  String? _weatherSummaryFromMap(Map<String, dynamic>? w) {
    if (w == null) return null;
    final parts = <String>[];
    if (w['weather'] != null && w['weather'].toString().isNotEmpty) {
      parts.add(w['weather'].toString());
    }
    if (w['temperature'] != null) {
      final t = _formatTemp(w['temperature']);
      if (t.isNotEmpty) parts.add('$t℃');
    }
    if (w['wind_direction'] != null &&
        w['wind_direction'].toString().isNotEmpty) {
      parts.add((w['wind_direction'] ?? '').toString() +
          (w['wind_power'] ?? '').toString());
    }
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  @override
  Future<void> onReady() async {
    super.onReady();
    await _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    bool current() => !isClosed && _scope.current && request == _request;
    if (!current()) return;
    final prefs = await SharedPreferences.getInstance();
    if (!current()) return;
    final dateKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthDate);
    final dataKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthCache);
    final today = _todayString();
    final cachedDate = prefs.getString(dateKey);
    final cached = prefs.getString(dataKey);
    var hasUsableCache = false;
    if (cachedDate == today && cached != null && cached.isNotEmpty) {
      try {
        final data = jsonDecode(cached) as Map<String, dynamic>?;
        if (data != null) {
          _applyMap(data);
          hasUsableCache = true;
        }
      } catch (_) {}
    }
    // 先用当天缓存快速显示，但每次进入页面仍从服务端刷新结构化的
    // 原局/大限疾厄关注。这样规则或出生资料修正后不会被当天旧缓存挡住。
    try {
      final res = await _scope.get('/api/fortune/daily-health');
      if (!current()) return;
      final data = (res.data as Map?)?['data'];
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        await prefs.setString(dateKey, today);
        if (!current()) return;
        await prefs.setString(dataKey, jsonEncode(map));
        if (!current()) return;
        _applyMap(map);
        return;
      }
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
    if (!current()) return;
    if (hasUsableCache) return;
    sections = <HealthSection>[
      const HealthSection('提示', '暂时无法获取养生数据，请稍后再试。'),
    ];
    update(['health']);
  }

  Future<void> refreshHealth() => _load();

  void _applyMap(Map<String, dynamic> m) {
    final w = m['weather'];
    final weatherMap = w is Map ? Map<String, dynamic>.from(w) : null;
    final summary = (m['weatherSummary'] as String?)?.trim() ??
        _weatherSummaryFromMap(weatherMap) ??
        '—';
    weather = summary;
    final t = weatherMap?['temperature'];
    if (t != null && t.toString().isNotEmpty) {
      final s = _formatTemp(t);
      final parts = s.split(RegExp(r'[~～\-/]'));
      if (parts.length >= 2) {
        tempHigh = _formatTemp(parts[0].trim());
        tempLow = _formatTemp(parts[1].trim());
      } else {
        tempHigh = s;
        tempLow = s;
      }
    }
    final cons = m['constitution'] as String?;
    tizhi = cons != null && cons.isNotEmpty ? '体质：$cons' : '体质';
    final st = m['solarTerm'] as String?;
    jieqi = st != null && st.isNotEmpty ? '节气：$st' : '节气';
    date = m['date']?.toString().trim() ?? '';
    final ziwei = m['ziweiHealth'];
    final archive = m['healthArchive'];
    final weekly = m['weeklyRefresh'];
    if (weekly is Map) {
      weeklyCheckDue = weekly['due'] == true;
      weeklyHasBaseline = weekly['hasBaseline'] == true;
      weeklyCheckMessage = weekly['message']?.toString().trim() ?? '';
    } else {
      weeklyCheckDue = false;
      weeklyHasBaseline = false;
      weeklyCheckMessage = '';
    }
    if (archive is Map) {
      final names = <String>[];
      if ((archive['questionnaire']?.toString().trim() ?? '').isNotEmpty) {
        names.add('体质问卷');
      }
      if ((archive['tongue']?.toString().trim() ?? '').isNotEmpty) {
        names.add('舌象');
      }
      if (archive['pulse'] is Map) names.add('AI把脉');
      archiveSources = names;
    } else {
      archiveSources = const [];
    }
    final direction = m['recommendationDirection'];
    if (direction is Map) {
      final title = direction['title']?.toString().trim() ?? '';
      final principles = direction['principles'];
      recommendationDirection = title.isEmpty ? '均衡稳定' : title;
      recommendationPrinciples = principles is List
          ? principles
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .take(3)
              .toList(growable: false)
          : const [];
      if (recommendationPrinciples.isEmpty) {
        recommendationPrinciples = const ['食材多样', '三餐规律', '少油少糖'];
      }
    } else {
      recommendationDirection = '均衡稳定';
      recommendationPrinciples = const ['食材多样', '三餐规律', '少油少糖'];
    }
    if (ziwei is Map) {
      final map = Map<String, dynamic>.from(ziwei);
      healthFocusAvailable = map['available'] != false;
      healthFocusSource =
          map['sourceLabel']?.toString().trim().isNotEmpty == true
              ? map['sourceLabel'].toString().trim()
              : '账号个人信息';
      healthFocusMessage = map['message']?.toString().trim() ?? '';
      final natal = map['natal'];
      final decadal = map['decadal'];
      if (healthFocusAvailable) {
        natalFocus = HealthFocus.fromMap(
          natal is Map ? Map<String, dynamic>.from(natal) : null,
        );
        decadalFocus = HealthFocus.fromMap(
          decadal is Map ? Map<String, dynamic>.from(decadal) : null,
        );
      }
    } else {
      healthFocusAvailable = false;
      healthFocusSource = '账号个人信息';
      healthFocusMessage = '暂时无法读取账号出生资料，请稍后重试。';
    }
    if (!healthFocusAvailable) {
      natalFocus = HealthFocus.fromMap(null);
      decadalFocus = HealthFocus.fromMap(null);
    }
    final content = m['content'] as String? ?? '';
    sections = <HealthSection>[
      HealthSection('养生建议', content.isEmpty ? '暂无内容。' : content),
    ];
    update(['health']);
  }
}
