import 'dart:convert';

import 'package:xuanyu/core/local/account_preference_scope.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';

import '../models/life_atlas_models.dart';

class LifeAtlasStore {
  LifeAtlasStore._();

  static Future<AccountPreferenceScope?> _scope(
      ApiSessionScope? session) async {
    try {
      return await AccountPreferenceScope.capture(session: session);
    } on ApiSessionChangedException {
      return null;
    }
  }

  static const _answersKey = 'life_atlas_answers_v1';
  static const _mainTitleKey = 'life_atlas_main_title_v1';
  static const _achievementsKey = 'life_atlas_achievements_v2';

  static String profileKey({
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) {
    return '${birth.year.toString().padLeft(4, '0')}-'
        '${birth.month.toString().padLeft(2, '0')}-'
        '${birth.day.toString().padLeft(2, '0')}_'
        '${hour.toString().padLeft(2, '0')}_${isMale ? 1 : 0}';
  }

  static Future<Map<String, LifeAtlasAnswer>> loadAnswers({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return {};
    final raw = scope.prefs.getString(scope.key(_answersKey));
    if (raw == null || raw.isEmpty) return {};
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final entry = Map<String, dynamic>.from(
        root[profileKey(birth: birth, hour: hour, isMale: isMale)] as Map? ??
            const {},
      );
      return {
        for (final item in entry.entries)
          if (LifeAtlasAnswer.tryParse(item.value?.toString()) != null)
            item.key: LifeAtlasAnswer.tryParse(item.value?.toString())!,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveAnswers({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
    required Map<String, LifeAtlasAnswer> answers,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return;
    final raw = scope.prefs.getString(scope.key(_answersKey));
    Map<String, dynamic> root;
    try {
      root = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      root = <String, dynamic>{};
    }
    root[profileKey(birth: birth, hour: hour, isMale: isMale)] = {
      for (final item in answers.entries) item.key: item.value.storageValue,
    };
    await scope.prefs.setString(scope.key(_answersKey), jsonEncode(root));
  }

  static Future<String?> loadMainTitleId({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return null;
    return scope.prefs.getString(
      scope.key(
          '$_mainTitleKey:${profileKey(birth: birth, hour: hour, isMale: isMale)}'),
    );
  }

  static Future<void> saveMainTitleId({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
    required String achievementId,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return;
    await scope.prefs.setString(
      scope.key(
          '$_mainTitleKey:${profileKey(birth: birth, hour: hour, isMale: isMale)}'),
      achievementId,
    );
  }

  static Future<List<LifeAtlasAchievement>> loadAchievements({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return const [];
    final raw = scope.prefs.getString(scope.key(_achievementsKey));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final items = root[profileKey(
        birth: birth,
        hour: hour,
        isMale: isMale,
      )] as List?;
      return (items ?? const [])
          .whereType<Map>()
          .map((item) => LifeAtlasAchievement.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<LifeAtlasAchievement>> saveAchievement({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
    required LifeAtlasAchievement achievement,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return const [];
    final raw = scope.prefs.getString(scope.key(_achievementsKey));
    Map<String, dynamic> root;
    try {
      root = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      root = <String, dynamic>{};
    }
    final key = profileKey(birth: birth, hour: hour, isMale: isMale);
    final current = (root[key] as List? ?? const [])
        .whereType<Map>()
        .map((item) => LifeAtlasAchievement.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.id != achievement.id)
        .toList();
    current.insert(0, achievement);
    final limited = current.take(200).toList(growable: false);
    root[key] = limited.map((item) => item.toJson()).toList(growable: false);
    await scope.prefs.setString(scope.key(_achievementsKey), jsonEncode(root));
    return limited;
  }
}
