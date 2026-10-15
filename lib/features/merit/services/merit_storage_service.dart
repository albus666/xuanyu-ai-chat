import 'dart:convert';

import 'package:xuanyu/core/local/account_preference_scope.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_cloud_sync_service.dart';

class MeritStorageService {
  MeritStorageService._();
  static const _key = 'merit_save_v1';

  static Future<MeritSaveData> load() async {
    final scope = await AccountPreferenceScope.capture();
    final raw = scope.prefs.getString(scope.key(_key));
    if (raw == null) {
      // 旧公共数据没有可靠归属，不自动认领；只恢复当前账号自己的云存档。
      if (scope.userId != null && scope.session.authenticated) {
        final cloud = await MeritCloudSyncService.fetchCloud();
        scope.ensureCurrent();
        if (cloud != null) {
          await save(cloud, syncCloud: false);
          return cloud;
        }
      }
      return MeritSaveData()..accountScope = scope;
    }
    try {
      return MeritSaveData.fromJson(jsonDecode(raw) as Map<String, dynamic>)
        ..accountScope = scope;
    } catch (_) {
      return MeritSaveData()..accountScope = scope;
    }
  }

  static Future<void> save(
    MeritSaveData data, {
    bool syncCloud = true,
    bool immediateCloud = false,
  }) async {
    final scope = data.accountScope ?? await AccountPreferenceScope.capture();
    data.accountScope = scope;
    if (!scope.current) return;
    await scope.prefs.setString(scope.key(_key), jsonEncode(data.toJson()));
    if (!scope.current) return;
    if (!syncCloud) return;
    if (immediateCloud) {
      await MeritCloudSyncService.flushUpload(data);
    } else {
      MeritCloudSyncService.scheduleUpload(data);
    }
  }

  static Future<void> resetAll() async {
    final scope = await AccountPreferenceScope.capture();
    await scope.prefs.remove(scope.key(_key));
    await MeritCloudSyncService.deleteCloud(scope: scope);
  }

  /// 每日 0 点重置当日文案记录
  static void refreshDaily(MeritSaveData data) {
    final today = _dateKey(DateTime.now());
    if (data.lastDailyDate == today) return;
    data.lastDailyDate = today;
    data.todayShownTextIds = [];
    data.todayTaps = 0;

    if (data.lastPlayDate.isEmpty) {
      data.dailyStreak = 1;
    } else {
      final last = DateTime.parse(data.lastPlayDate);
      final diff = DateTime.now()
          .difference(DateTime(last.year, last.month, last.day))
          .inDays;
      if (diff == 1) {
        data.dailyStreak += 1;
      } else if (diff > 1) {
        data.dailyStreak = 1;
      }
    }
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
