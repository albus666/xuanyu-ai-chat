import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/fortune/birth_date_form_page.dart';
import '../constants/app_constants.dart';
import '../../features/fortune/paipan/models/region.dart';
import '../network/api_session_scope.dart';
import '../network/account_profile_requests.dart';
import '../utils/app_toast.dart';

/// 账号本人的出生资料。服务端个人资料是唯一数据源，所有“本人”功能共用。
class AccountBirthProfile {
  const AccountBirthProfile({
    required this.nickname,
    required this.birthDate,
    required this.birthTime,
    required this.gender,
    required this.birthPlace,
    required this.birthLongitude,
    required this.birthLatitude,
    required this.birthTimezone,
  });

  final String nickname;
  final String birthDate;
  final String birthTime;
  final int? gender;
  final String birthPlace;
  final double? birthLongitude;
  final double? birthLatitude;
  final String birthTimezone;

  DateTime? get birthDateTime {
    if (birthDate.isEmpty || birthTime.isEmpty) return null;
    final normalizedTime = birthTime.length == 5 ? '$birthTime:00' : birthTime;
    return DateTime.tryParse('${birthDate.split('T').first}T$normalizedTime');
  }

  bool get isComplete => birthDateTime != null && (gender == 1 || gender == 2);

  bool get isAstrologyComplete =>
      isComplete &&
      birthPlace.isNotEmpty &&
      birthLongitude != null &&
      birthLatitude != null &&
      birthTimezone == 'Asia/Shanghai';

  Region? get birthRegion => birthPlace.isEmpty
      ? null
      : Region.placeholder(
          name: birthPlace.split(RegExp(r'\s+')).last,
          extPath: birthPlace,
          lng: birthLongitude,
          lat: birthLatitude,
        );

  bool get isFemale => gender == 2;

  String get safeNickname => nickname.isEmpty ? '我的命盘' : nickname;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'nickname': nickname,
        'birthDate': birthDate,
        'birthTime': birthTime,
        'gender': gender,
        'birthPlace': birthPlace,
        'birthLongitude': birthLongitude,
        'birthLatitude': birthLatitude,
        'birthTimezone': birthTimezone,
      };

  factory AccountBirthProfile.fromMap(Map<dynamic, dynamic>? data) {
    return AccountBirthProfile(
      nickname: data?['nickname']?.toString().trim() ?? '',
      birthDate: data?['birthDate']?.toString().trim() ?? '',
      birthTime: data?['birthTime']?.toString().trim() ?? '',
      gender: (data?['gender'] as num?)?.toInt(),
      birthPlace: data?['birthPlace']?.toString().trim() ?? '',
      birthLongitude: _toDouble(data?['birthLongitude']),
      birthLatitude: _toDouble(data?['birthLatitude']),
      birthTimezone:
          data?['birthTimezone']?.toString().trim() ?? 'Asia/Shanghai',
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class AccountBirthProfileRepository {
  AccountBirthProfileRepository._();

  static const _cachePrefix = 'account_birth_profile_v2_';
  static const _freshFor = Duration(minutes: 10);
  static const _maxAge = Duration(days: 14);
  static final Map<int, _ProfileCacheEntry> _memory = {};
  static final Map<int, Future<AccountBirthProfile>> _inFlight = {};
  static final Map<int, int> _generation = {};

  /// 启动已读入 SharedPreferences 后，供页面首帧同步恢复本人资料。
  static AccountBirthProfile? peek(SharedPreferences prefs) {
    final userId = prefs.getInt(AppConstants.keyUserId);
    if (userId == null) return null;
    final memory = _memory[userId];
    if (memory != null && !_isExpired(memory.cachedAt, _maxAge)) {
      return memory.profile;
    }
    try {
      final decoded = jsonDecode(prefs.getString('$_cachePrefix$userId') ?? '');
      if (decoded is! Map || decoded['profile'] is! Map) return null;
      final cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
      if (cachedAt == null || _isExpired(cachedAt, _maxAge)) return null;
      final profile = AccountBirthProfile.fromMap(decoded['profile'] as Map);
      _memory[userId] = _ProfileCacheEntry(
        profile: profile,
        cachedAt: cachedAt,
      );
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// 缓存优先读取本人资料；缓存超过十分钟时仍立即返回，同时后台校准。
  static Future<AccountBirthProfile> load({
    bool forceRefresh = false,
    bool waitForRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(AppConstants.keyUserId);
    if (userId == null) return _fetch(null);

    if (!forceRefresh) {
      final profile = peek(prefs);
      if (profile != null) {
        if (_isExpired(_memory[userId]!.cachedAt, _freshFor)) {
          if (waitForRefresh) return _refreshOrCached(userId, profile);
          _refreshInBackground(userId);
        }
        return profile;
      }
      // 损坏、过期或旧版本缓存不阻塞回源。
      if (prefs.containsKey('$_cachePrefix$userId')) {
        await prefs.remove('$_cachePrefix$userId');
      }
    }
    return _fetch(userId);
  }

  static Future<AccountBirthProfile> refresh() => load(forceRefresh: true);

  static Future<AccountBirthProfile> _refreshOrCached(
    int userId,
    AccountBirthProfile previous,
  ) async {
    try {
      return await _fetch(userId);
    } on DioException {
      return previous;
    }
  }

  static Future<AccountBirthProfile> _fetch(int? userId) async {
    if (userId != null) {
      final pending = _inFlight[userId];
      if (pending != null) return pending;
    }
    final generation = userId == null ? 0 : (_generation[userId] ?? 0);
    final future = _fetchAndCache(userId, generation);
    if (userId == null) return future;
    _inFlight[userId] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[userId], future)) _inFlight.remove(userId);
    }
  }

  static Future<AccountBirthProfile> _fetchAndCache(
    int? userId,
    int generation,
  ) async {
    final scope = ApiSessionScope();
    final response = await AccountProfileRequests.fetch(scope);
    scope.ensureCurrent();
    final data = (response.data as Map?)?['data'] as Map?;
    final profile = AccountBirthProfile.fromMap(data);
    if (userId != null && (_generation[userId] ?? 0) == generation) {
      final cachedAt = DateTime.now().toUtc();
      final prefs = await SharedPreferences.getInstance();
      scope.ensureCurrent();
      if (prefs.getInt(AppConstants.keyUserId) != userId ||
          (_generation[userId] ?? 0) != generation) {
        return profile;
      }
      _memory[userId] = _ProfileCacheEntry(
        profile: profile,
        cachedAt: cachedAt,
      );
      await prefs.setString(
        '$_cachePrefix$userId',
        jsonEncode(<String, dynamic>{
          'cachedAt': cachedAt.toIso8601String(),
          'profile': profile.toJson(),
        }),
      );
    }
    return profile;
  }

  static void _refreshInBackground(int userId) {
    unawaited(_fetch(userId).then<void>((_) {}, onError: (_) {}));
  }

  static bool _isExpired(DateTime cachedAt, Duration duration) =>
      DateTime.now().toUtc().difference(cachedAt.toUtc()) > duration;

  static Future<void> invalidateCurrent() async {
    AccountProfileRequests.invalidate();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(AppConstants.keyUserId);
    if (userId == null) return;
    _generation[userId] = (_generation[userId] ?? 0) + 1;
    _memory.remove(userId);
    _inFlight.remove(userId);
    await prefs.remove('$_cachePrefix$userId');
  }

  static void clearMemory() {
    AccountProfileRequests.invalidate();
    for (final userId in <int>{..._memory.keys, ..._inFlight.keys}) {
      _generation[userId] = (_generation[userId] ?? 0) + 1;
    }
    _memory.clear();
    _inFlight.clear();
  }

  static Future<void> clearForUser(int userId) async {
    _generation[userId] = (_generation[userId] ?? 0) + 1;
    _memory.remove(userId);
    _inFlight.remove(userId);
    await (await SharedPreferences.getInstance()).remove(
      '$_cachePrefix$userId',
    );
  }

  /// 缺少本人出生资料时统一进入一次性补充页；保存后资料会写回账号。
  static Future<AccountBirthProfile?> ensure(
    BuildContext context, {
    String reason = '用于本人八字、斗数等功能',
  }) async {
    AccountBirthProfile profile;
    try {
      profile = await load();
    } on DioException {
      if (context.mounted) showAppToast(context, '本人资料读取失败，请稍后重试');
      return null;
    }
    if (profile.isComplete) return profile;
    if (!context.mounted) return null;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BirthDateFormPage(
          initialBirthDate: profile.birthDate,
          initialBirthTime: profile.birthTime,
          initialGender: profile.gender,
          reason: reason,
        ),
      ),
    );
    if (saved != true || !context.mounted) return null;
    try {
      final refreshed = await load();
      return refreshed.isComplete ? refreshed : null;
    } on DioException {
      if (context.mounted) showAppToast(context, '资料已保存，请重新进入功能');
      return null;
    }
  }

  /// 星盘必须同时具备精确时辰和出生地；缺任何一项都让用户明确补充。
  static Future<AccountBirthProfile?> ensureAstrology(
    BuildContext context, {
    String reason = '用于准确计算上升、宫位与相位',
  }) async {
    AccountBirthProfile profile;
    try {
      profile = await load(forceRefresh: true);
    } on DioException {
      if (context.mounted) showAppToast(context, '本人资料读取失败，请稍后重试');
      return null;
    }
    if (profile.isAstrologyComplete) return profile;
    if (!context.mounted) return null;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BirthDateFormPage(
          initialBirthDate: profile.birthDate,
          initialBirthTime: profile.birthTime,
          initialGender: profile.gender,
          initialBirthPlace: profile.birthRegion,
          requireBirthPlace: true,
          onlyBirthPlace: profile.isComplete,
          reason: reason,
        ),
      ),
    );
    if (saved != true || !context.mounted) return null;
    try {
      final refreshed = await load(forceRefresh: true);
      return refreshed.isAstrologyComplete ? refreshed : null;
    } on DioException {
      if (context.mounted) showAppToast(context, '资料已保存，请重新进入功能');
      return null;
    }
  }
}

class _ProfileCacheEntry {
  const _ProfileCacheEntry({required this.profile, required this.cachedAt});

  final AccountBirthProfile profile;
  final DateTime cachedAt;
}
