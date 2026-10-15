import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/fortune/paipan/bazi_calculation_cache.dart';
import '../../features/fortune/paipan/mingling_identity.dart';
import '../../features/fortune/ziwei/ziwei_models.dart';
import '../../features/fortune/ziwei/ziwei_pattern.dart';
import '../../features/fortune/ziwei/ziwei_service.dart';
import '../constants/app_constants.dart';
import '../network/api_session_scope.dart';
import 'account_birth_profile.dart';

/// 一张卡片作为一个快照发布，避免姓名、标签、人物分批出现在屏幕上。
class DestinyArchiveSnapshot {
  const DestinyArchiveSnapshot({
    required this.profileKey,
    required this.cachedAt,
    required this.birthDate,
    required this.title,
    required this.temperament,
    required this.assetPath,
    required this.xishen,
    required this.yongshen,
    required this.zodiac,
    required this.constellation,
    required this.ziweiPattern,
    required this.complete,
  });

  final String profileKey;
  final DateTime cachedAt;
  final String birthDate;
  final String title;
  final String temperament;
  final String? assetPath;
  final String xishen;
  final String yongshen;
  final String zodiac;
  final String constellation;
  final String ziweiPattern;
  final bool complete;

  Map<String, dynamic> toJson() => {
        'profileKey': profileKey,
        'cachedAt': cachedAt.toIso8601String(),
        'birthDate': birthDate,
        'title': title,
        'temperament': temperament,
        'assetPath': assetPath,
        'xishen': xishen,
        'yongshen': yongshen,
        'zodiac': zodiac,
        'constellation': constellation,
        'ziweiPattern': ziweiPattern,
        'complete': complete,
      };

  factory DestinyArchiveSnapshot.fromJson(Map<String, dynamic> data) =>
      DestinyArchiveSnapshot(
        profileKey: data['profileKey'] as String,
        cachedAt: DateTime.parse(data['cachedAt'] as String),
        birthDate: data['birthDate'] as String,
        title: data['title'] as String,
        temperament: data['temperament'] as String,
        assetPath: data['assetPath'] as String?,
        xishen: data['xishen'] as String,
        yongshen: data['yongshen'] as String,
        zodiac: data['zodiac'] as String,
        constellation: data['constellation'] as String,
        ziweiPattern: data['ziweiPattern'] as String,
        complete: data['complete'] as bool,
      );
}

class DestinyArchiveRepository {
  DestinyArchiveRepository._();

  static const cachePrefix = 'destiny_archive_v1_';
  static const hideBirthDatePrefix = 'destiny_match_hide_birth_date_v1_';
  static final _inFlight = <String, Future<DestinyArchiveSnapshot>>{};

  static String profileKey(AccountBirthProfile profile) =>
      jsonEncode(profile.toJson());

  static DestinyArchiveSnapshot? peek(SharedPreferences prefs) {
    final userId = prefs.getInt(AppConstants.keyUserId);
    final profile = AccountBirthProfileRepository.peek(prefs);
    if (userId == null || profile == null) return null;
    try {
      final snapshot = DestinyArchiveSnapshot.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(prefs.getString('$cachePrefix$userId') ?? '') as Map,
        ),
      );
      if (snapshot.profileKey != profileKey(profile) ||
          DateTime.now().toUtc().difference(snapshot.cachedAt) >
              const Duration(days: 14)) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static Future<DestinyArchiveSnapshot> load() async {
    final scope = ApiSessionScope();
    final prefs = await SharedPreferences.getInstance();
    scope.ensureCurrent();
    final userId = prefs.getInt(AppConstants.keyUserId);
    if (userId == null) throw const ApiSessionChangedException();
    final profile =
        await AccountBirthProfileRepository.load(waitForRefresh: true);
    scope.ensureCurrent();
    final cached = peek(prefs);
    if (cached != null &&
        cached.complete &&
        DateTime.now().toUtc().difference(cached.cachedAt) <
            const Duration(minutes: 10)) {
      return cached;
    }
    final key = '$userId|${scope.session}|${profileKey(profile)}';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _calculate(profile, scope, cached).then((snapshot) async {
      scope.ensureCurrent();
      final current = AccountBirthProfileRepository.peek(prefs);
      if (prefs.getInt(AppConstants.keyUserId) != userId ||
          current == null ||
          profileKey(current) != snapshot.profileKey) {
        throw const ApiSessionChangedException();
      }
      await prefs.setString(
        '$cachePrefix$userId',
        jsonEncode(snapshot.toJson()),
      );
      return snapshot;
    });
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  static Future<DestinyArchiveSnapshot> _calculate(
    AccountBirthProfile profile,
    ApiSessionScope scope,
    DestinyArchiveSnapshot? previous,
  ) async {
    final birth = profile.birthDateTime;
    if (!profile.isComplete || birth == null) {
      return DestinyArchiveSnapshot(
        profileKey: profileKey(profile),
        cachedAt: DateTime.now().toUtc(),
        birthDate: profile.birthDate.split('T').first,
        title: '八字命灵',
        temperament: '完善出生日期时辰后生成',
        assetPath: null,
        xishen: '',
        yongshen: '',
        zodiac: '',
        constellation: '',
        ziweiPattern: '',
        complete: true,
      );
    }
    final bazi = await BaziCalculationCache.calculate(
      birth,
      isFemale: profile.isFemale,
    );
    scope.ensureCurrent();
    final identity = minglingIdentityForDayGan(bazi.dayGan);
    var xi = previous?.xishen ?? '';
    var yong = previous?.yongshen ?? '';
    var pattern = previous?.ziweiPattern ?? '';
    var complete = true;
    Future<void> loadXiYong() async {
      try {
        final response = await scope.get('/api/fortune/xiyongshen');
        final data = (response.data as Map?)?['data'] as Map?;
        final x = data?['喜神']?.toString().trim() ?? '';
        final y = data?['用神']?.toString().trim() ?? '';
        if (x.isEmpty || y.isEmpty) complete = false;
        if (x.isNotEmpty) xi = '喜神 $x';
        if (y.isNotEmpty) yong = '用神 $y';
      } catch (_) {
        complete = false;
      }
    }

    Future<void> loadPattern() async {
      try {
        final now = DateTime.now();
        final chart = await ZiweiService.calculate(
          profile: ZiweiProfile(
            name: profile.safeNickname,
            gender: profile.isFemale ? '女' : '男',
            clockBirthDate: birth,
            effectiveBirthDate: birth,
            calendarTypeIndex: 0,
            settings: const ZiweiSettings(),
            birthPlace: profile.birthPlace.isEmpty ? null : profile.birthPlace,
            longitude: profile.birthLongitude,
            latitude: profile.birthLatitude,
          ),
          targetDate: now,
          targetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
        );
        pattern = ZiweiPatternRecognizer.recognize(chart).name.trim();
      } catch (_) {
        complete = false;
      }
    }

    await Future.wait([loadXiYong(), loadPattern()]);
    scope.ensureCurrent();
    return DestinyArchiveSnapshot(
      profileKey: profileKey(profile),
      cachedAt: DateTime.now().toUtc(),
      birthDate: profile.birthDate.split('T').first,
      title: '你好，我是${bazi.dayGan.trim()}${bazi.dayZhi.trim()}',
      temperament: identity?.temperament ?? '',
      assetPath: identity?.assetPath,
      xishen: xi,
      yongshen: yong,
      zodiac: bazi.shengXiao.trim(),
      constellation: bazi.xingZuo.trim(),
      ziweiPattern: pattern,
      complete: complete,
    );
  }

  static Future<void> clearForUser(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$cachePrefix$userId');
  }
}
