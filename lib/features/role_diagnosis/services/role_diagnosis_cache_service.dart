import 'dart:convert';

import 'package:xuanyu/core/local/account_preference_scope.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/role_diagnosis/models/role_diagnosis_models.dart';

/// 角色诊断书缓存：同一生辰、时辰和性别始终复用同一份确定性报告。
class RoleDiagnosisCacheService {
  RoleDiagnosisCacheService._();

  static Future<AccountPreferenceScope?> _scope(
      ApiSessionScope? session) async {
    try {
      return await AccountPreferenceScope.capture(session: session);
    } on ApiSessionChangedException {
      return null;
    }
  }

  /// v8：完整社会故事与六维长报告均由后台生成并通过校验。
  static const _prefsKey = 'role_diagnosis_cache_v8';

  static String entryKey({
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) {
    final birthKey =
        '${birth.year}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}';
    return '${birthKey}_${hour}_${isMale ? 1 : 0}';
  }

  static Future<RoleDiagnosisReport?> load({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return null;
    final raw = scope.prefs.getString(scope.key(_prefsKey));
    if (raw == null) return null;
    try {
      final root = jsonDecode(raw) as Map<String, dynamic>;
      final item = root[entryKey(birth: birth, hour: hour, isMale: isMale)];
      if (item is! Map<String, dynamic>) return null;
      return RoleDiagnosisReport.fromJson(item);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
    required RoleDiagnosisReport report,
  }) async {
    final scope = await _scope(session);
    if (scope == null) return;
    final key = entryKey(birth: birth, hour: hour, isMale: isMale);
    final raw = scope.prefs.getString(scope.key(_prefsKey));
    final root = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    root[key] = report.toJson();
    await scope.prefs.setString(scope.key(_prefsKey), jsonEncode(root));
  }
}
