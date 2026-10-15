import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/daily_energy_score.dart';

class DailyEmotionInsight {
  const DailyEmotionInsight({
    required this.tone,
    required this.pressureLevel,
    required this.pressureSource,
    required this.expression,
    required this.regulation,
  });

  final String tone;
  final String pressureLevel;
  final String pressureSource;
  final String expression;
  final String regulation;

  static DailyEmotionInsight? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    String value(String key) => map[key]?.toString().trim() ?? '';
    final insight = DailyEmotionInsight(
      tone: value('tone'),
      pressureLevel: value('pressureLevel'),
      pressureSource: value('pressureSource'),
      expression: value('expression'),
      regulation: value('regulation'),
    );
    if (insight.tone.isEmpty ||
        insight.pressureLevel.isEmpty ||
        insight.pressureSource.isEmpty ||
        insight.expression.isEmpty ||
        insight.regulation.isEmpty) {
      return null;
    }
    return insight;
  }

  String get displayText => <String>[
        '情绪底色\n$tone',
        '压力感受 · $pressureLevel\n$pressureSource',
        '可能表现\n$expression',
        '调节方式\n$regulation',
      ].join('\n\n');
}

class DailyEnergyDay {
  const DailyEnergyDay({
    required this.score,
    required this.content,
    required this.date,
    this.scoreBasis = const <String>[],
    this.emotion,
  });

  final DailyEnergyScore score;
  final String content;
  final String date;
  final List<String> scoreBasis;
  final DailyEmotionInsight? emotion;
}

/// 七日能量加载结果（一次推断 + 本地按日缓存）。
class DailyEnergyResult {
  const DailyEnergyResult({
    required this.score,
    required this.content,
    required this.date,
    this.days = const <DailyEnergyDay>[],
    this.fromCache = false,
    this.errorMessage,
  });

  final DailyEnergyScore score;
  final String content;
  final String date;
  final List<DailyEnergyDay> days;
  final bool fromCache;
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

class DailyEnergyLoader {
  DailyEnergyLoader._();

  static const String _currentEnergyVersion = 'v15-light-professional-copy';

  static DailyEnergyResult? _sessionCache;
  static String? _sessionDate;
  static int? _sessionIdentity;
  static int _requestVersion = 0;
  static Future<DailyEnergyResult>? _inFlight;
  static int? _inFlightSession;
  static String? _inFlightDate;

  /// 无归属旧缓存不自动认领；个人数据按账号保存。
  static String cacheKey(SharedPreferences prefs, String base) =>
      '${base}_user_${prefs.getInt(AppConstants.keyUserId) ?? 'guest'}';

  static String todayString() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String? _messageFromBody(dynamic body) {
    if (body is! Map) return null;
    final m = body['message'];
    return m is String && m.trim().isNotEmpty ? m.trim() : null;
  }

  /// 当前 App 会话内已加载的今日能量（同一天内再次进入详情页无需读盘/请求）。
  static DailyEnergyResult? sessionCacheForToday() {
    if (_sessionIdentity == apiSessionChanges.value &&
        _sessionCache != null &&
        _sessionDate == todayString()) {
      return _sessionCache;
    }
    return null;
  }

  static void remember(DailyEnergyResult result) {
    _sessionIdentity = apiSessionChanges.value;
    _sessionCache = result;
    _sessionDate = result.date;
  }

  static void clearSession() {
    _requestVersion++;
    _inFlight = null;
    _inFlightSession = null;
    _inFlightDate = null;
    _sessionIdentity = null;
    _sessionCache = null;
    _sessionDate = null;
  }

  /// 当天首次打开 App 请求一次；已有当日本地缓存则直接返回。
  static Future<DailyEnergyResult> load({
    bool forceRefresh = false,
    String? birthDate,
    String? birthTime,
  }) {
    if (forceRefresh) clearSession();
    final pending = _inFlight;
    if (pending != null &&
        _inFlightSession == apiSessionChanges.value &&
        _inFlightDate == todayString()) {
      return pending;
    }
    _inFlightSession = apiSessionChanges.value;
    _inFlightDate = todayString();
    late final Future<DailyEnergyResult> task;
    task = _load(
      forceRefresh: forceRefresh,
      birthDate: birthDate,
      birthTime: birthTime,
    ).whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    });
    _inFlight = task;
    return task;
  }

  static Future<DailyEnergyResult> _load({
    required bool forceRefresh,
    String? birthDate,
    String? birthTime,
  }) async {
    final scope = ApiSessionScope();
    final requestVersion = _requestVersion;
    bool current() => scope.current && requestVersion == _requestVersion;
    DailyEnergyResult expired() => _fallbackResult(
          today: todayString(),
          errorMessage: apiSessionChangedMessage,
        );
    final today = todayString();

    if (!forceRefresh) {
      final session = sessionCacheForToday();
      if (session != null) return session;

      final prefs = await SharedPreferences.getInstance();
      if (!current()) return expired();
      final cached = await _readLocalCache(prefs, today);
      if (!current()) return expired();
      if (cached != null) {
        remember(cached);
        return cached;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (!current()) return expired();
    final dateKey = cacheKey(prefs, AppConstants.keyDailyFortuneDate);
    final dataKey = cacheKey(prefs, AppConstants.keyDailyFortuneCache);
    try {
      final res = await scope.get('/api/fortune/today-fortune');
      if (!current()) return expired();
      final body = res.data;
      if (body is Map) {
        final code = body['code'];
        if (code != null && code != 0) {
          return _fallbackResult(
            today: today,
            birthDate: birthDate,
            birthTime: birthTime,
            errorMessage: _messageFromBody(body) ?? '获取今日能量失败',
          );
        }
      }
      final data = (res.data as Map?)?['data'];
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        await prefs.setString(dateKey, today);
        if (!current()) return expired();
        await prefs.setString(dataKey, jsonEncode(map));
        if (!current()) return expired();
        final result = _resultFromMap(map, today, fromCache: false);
        remember(result);
        return result;
      }
      return _fallbackResult(
        today: today,
        birthDate: birthDate,
        birthTime: birthTime,
        errorMessage: '暂时没有获取到能量数据',
      );
    } on ApiSessionChangedException {
      return expired();
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[daily-energy] ${e.response?.statusCode} ${e.message} body=${e.response?.data}',
        );
      }
      final status = e.response?.statusCode;
      final msg = _messageFromBody(e.response?.data);
      String error;
      if (status == 400) {
        error = msg ?? '请先在「我的 → 编辑资料」中填写出生日期与时辰';
      } else if (status == 401) {
        error = msg ?? '登录已失效，请重新登录';
      } else if (status == 500) {
        error = msg ?? '能量生成服务暂时不可用，请稍后再试';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        error = '请求超时，请检查网络';
      } else if (e.type == DioExceptionType.connectionError) {
        error = '无法连接服务器，请检查网络';
      } else {
        error = msg ?? '暂时无法获取今日能量';
      }
      return _fallbackResult(
        today: today,
        birthDate: birthDate,
        birthTime: birthTime,
        errorMessage: error,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[daily-energy] $e');
      return _fallbackResult(
        today: today,
        birthDate: birthDate,
        birthTime: birthTime,
        errorMessage: '加载今日能量时出错',
      );
    }
  }

  static Future<DailyEnergyResult?> refreshFromLocalCache() async {
    final scope = ApiSessionScope();
    final session = sessionCacheForToday();
    if (session != null) return session;
    final prefs = await SharedPreferences.getInstance();
    if (!scope.current) return null;
    final cached = await _readLocalCache(prefs, todayString());
    if (!scope.current) return null;
    if (cached != null) remember(cached);
    return cached;
  }

  static Future<DailyEnergyResult?> _readLocalCache(
    SharedPreferences prefs,
    String today,
  ) async {
    final cachedDate = prefs.getString(
      cacheKey(prefs, AppConstants.keyDailyFortuneDate),
    );
    final cached = prefs.getString(
      cacheKey(prefs, AppConstants.keyDailyFortuneCache),
    );
    if (cachedDate != today || cached == null || cached.isEmpty) return null;
    try {
      final data = jsonDecode(cached) as Map<String, dynamic>?;
      if (data == null) return null;
      // 旧版仅文本缓存无五维分，需重新请求 AI
      if (DailyEnergyScore.fromMap(data) == null) return null;
      // 服务端能量规则升级后丢弃旧版当日缓存，避免继续展示旧的重复文案。
      if (data['energyVersion']?.toString() != _currentEnergyVersion) {
        return null;
      }
      return _resultFromMap(data, today, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  static DailyEnergyResult _resultFromMap(
    Map<String, dynamic> map,
    String today, {
    required bool fromCache,
  }) {
    final parsedDays = <DailyEnergyDay>[];
    final rawDays = map['days'];
    if (rawDays is List) {
      for (final raw in rawDays.whereType<Map>().take(7)) {
        final dayMap = Map<String, dynamic>.from(raw);
        final dayDate = dayMap['date']?.toString().trim() ?? '';
        final dayScore = DailyEnergyScore.fromMap(dayMap);
        if (dayDate.isEmpty || dayScore == null) continue;
        parsedDays.add(
          DailyEnergyDay(
            score: dayScore,
            content: _formatContent(dayMap['content']),
            date: dayDate,
            scoreBasis: _stringList(dayMap['scoreBasis']),
            emotion: DailyEmotionInsight.fromMap(dayMap['emotion']),
          ),
        );
      }
    }
    final score = parsedDays.isNotEmpty
        ? parsedDays.first.score
        : DailyEnergyScore.fromMap(map) ?? DailyEnergyScore.compute();
    final content = parsedDays.isNotEmpty
        ? parsedDays.first.content
        : _formatContent(map['content']);
    final date = parsedDays.isNotEmpty
        ? parsedDays.first.date
        : (map['date'] as String?)?.trim().isNotEmpty == true
            ? map['date'] as String
            : today;
    final rootEmotion = DailyEmotionInsight.fromMap(map['emotion']);
    return DailyEnergyResult(
      score: score,
      content: content,
      date: date,
      days: parsedDays.isEmpty
          ? <DailyEnergyDay>[
              DailyEnergyDay(
                score: score,
                content: content,
                date: date,
                scoreBasis: _stringList(map['scoreBasis']),
                emotion: rootEmotion,
              ),
            ]
          : parsedDays,
      fromCache: fromCache,
    );
  }

  static String _formatContent(Object? raw) {
    if (raw is Map) return _formatContentMap(Map<String, dynamic>.from(raw));
    if (raw is! String) return '';
    final text = raw.trim();
    if (text.isEmpty) return '';
    final candidate = text
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        return _formatContentMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Older API responses are already plain text.
    }
    return text;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(10)
        .toList(growable: false);
  }

  static String _formatContentMap(Map<String, dynamic> content) {
    String value(String key) => (content[key] as String?)?.trim() ?? '';
    final sections = <String>[];
    void add(String title, String text) {
      if (text.isNotEmpty) sections.add('$title\n$text');
    }

    add('今日概览', value('overall'));
    add('爱情', value('love'));
    add('财富', value('wealth'));
    add('事业', value('career'));
    add('学习', value('study'));
    add('人际', value('social'));
    add('今日建议', value('summary'));
    return sections.join('\n\n');
  }

  static DailyEnergyResult _fallbackResult({
    required String today,
    String? birthDate,
    String? birthTime,
    String? errorMessage,
  }) {
    final start = DateTime.now();
    final days = List<DailyEnergyDay>.generate(7, (index) {
      final target = start.add(Duration(days: index));
      final date =
          '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      return DailyEnergyDay(
        score: DailyEnergyScore.compute(
          birthDate: birthDate?.isNotEmpty == true ? birthDate : null,
          birthTime: birthTime?.isNotEmpty == true ? birthTime : null,
          forDate: target,
        ),
        content: '',
        date: date,
      );
    });
    return DailyEnergyResult(
      score: days.first.score,
      content: '',
      date: today,
      days: days,
      errorMessage: errorMessage,
    );
  }
}
