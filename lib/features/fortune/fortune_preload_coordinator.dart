import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/account_scoped_json_cache.dart';
import '../../core/constants/app_constants.dart';
import '../../core/profile/account_birth_profile.dart';
import '../../core/profile/destiny_archive_repository.dart';
import 'astrology/astrology_models.dart';
import 'astrology/astrology_service.dart';
import 'paipan/bazi_calculation_cache.dart';
import 'paipan/utils/region_loader.dart';
import 'qizheng/qizheng_models.dart';
import 'qizheng/qizheng_service.dart';
import 'ziwei/ziwei_models.dart';
import 'ziwei/ziwei_service.dart';

/// 登录后的低优先级命盘预热。
///
/// 只预热本人最常用的本命盘，不预取流年切换、媒体或付费内容。所有异常均由
/// 页面正常兜底，不阻塞登录和首页首帧。
class FortunePreloadCoordinator {
  FortunePreloadCoordinator._();

  static Timer? _timer;
  static final Map<int, Future<void>> _running = {};

  static void schedule({
    Duration delay = const Duration(milliseconds: 900),
    bool forceProfileRefresh = false,
  }) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      unawaited(warmUp(forceProfileRefresh: forceProfileRefresh));
    });
  }

  static Future<void> warmUp({bool forceProfileRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(AppConstants.keyUserId);
    if (userId == null ||
        (prefs.getString(AppConstants.keyToken) ?? '').isEmpty) {
      return;
    }
    final existing = _running[userId];
    if (existing != null && !forceProfileRefresh) return existing;
    final future = _warmUser(userId, forceProfileRefresh: forceProfileRefresh);
    _running[userId] = future;
    try {
      await future;
    } finally {
      if (identical(_running[userId], future)) _running.remove(userId);
    }
  }

  static Future<void> _warmUser(
    int userId, {
    required bool forceProfileRefresh,
  }) async {
    RegionLoader.preload();
    final AccountBirthProfile profile;
    try {
      profile = await AccountBirthProfileRepository.load(
        forceRefresh: forceProfileRefresh,
      );
    } catch (_) {
      return;
    }
    if (!await _stillCurrent(userId) || !profile.isComplete) return;

    final birth = profile.birthDateTime!;
    try {
      await BaziCalculationCache.calculate(birth, isFemale: profile.isFemale);
    } catch (_) {}
    if (!await _stillCurrent(userId)) return;

    final now = DateTime.now();
    final ziwei = ZiweiProfile(
      name: profile.safeNickname,
      gender: profile.isFemale ? '女' : '男',
      clockBirthDate: birth,
      effectiveBirthDate: birth,
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
      birthPlace: profile.birthPlace.isEmpty ? null : profile.birthPlace,
      longitude: profile.birthLongitude,
      latitude: profile.birthLatitude,
    );
    final tasks = <Future<dynamic>>[
      DestinyArchiveRepository.load(),
      ZiweiService.calculate(
        profile: ziwei,
        targetDate: now,
        targetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
      ),
    ];
    if (profile.isAstrologyComplete) {
      tasks
        ..add(AstrologyService.calculate(AstrologyProfile.fromAccount(profile)))
        ..add(QizhengService.calculate(QizhengProfile.fromAccount(profile)));
    }
    await Future.wait(tasks.map((task) => task.catchError((_) => null)));
  }

  static Future<bool> _stillCurrent(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppConstants.keyUserId) == userId &&
        (prefs.getString(AppConstants.keyToken) ?? '').isNotEmpty;
  }

  static void clearMemory() {
    _timer?.cancel();
    _timer = null;
    AccountScopedJsonCache.clearMemory();
    AccountBirthProfileRepository.clearMemory();
    BaziCalculationCache.clear();
    ZiweiService.clearMemory();
    AstrologyService.clearMemory();
    QizhengService.clearMemory();
  }

  static Future<void> clearForUser(int userId) async {
    clearMemory();
    await AccountBirthProfileRepository.clearForUser(userId);
    await DestinyArchiveRepository.clearForUser(userId);
    await AccountScopedJsonCache.clearForUser(userId);
  }
}
