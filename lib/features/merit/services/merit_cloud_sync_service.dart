import 'dart:async';
import 'dart:convert';

import 'package:xuanyu/core/local/account_preference_scope.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

/// 定时器、认证与返回结果均绑定发起账号，切号后不上传旧进度。
class MeritCloudSyncService {
  MeritCloudSyncService._();
  static Timer? _uploadDebounce;
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    apiSessionChanges.addListener(() => _uploadDebounce?.cancel());
  }

  static Future<bool> isLoggedIn() async => ApiSessionScope().authenticated;

  static int progressScore(MeritSaveData data) =>
      data.totalTaps + data.reincarnationCount * 100000;

  static MeritSaveData merge(MeritSaveData local, MeritSaveData cloud) =>
      progressScore(cloud) > progressScore(local) ? cloud : local;

  static Future<MeritSaveData?> fetchCloud() async {
    try {
      final scope = await AccountPreferenceScope.capture();
      if (!scope.session.authenticated || scope.userId == null) return null;
      final res = await scope.session.get('/api/merit/save');
      scope.ensureCurrent();
      final body = res.data;
      final payload = body is Map && body['code'] == 0 ? body['data'] : null;
      final save = payload is Map ? payload['saveData'] : null;
      if (save is! Map) return null;
      return MeritSaveData.fromJson(Map<String, dynamic>.from(save))
        ..accountScope = scope;
    } catch (_) {
      return null;
    }
  }

  static void scheduleUpload(MeritSaveData data) {
    _listen();
    _uploadDebounce?.cancel();
    final session = data.accountScope?.session ?? ApiSessionScope();
    final snapshot = MeritSaveData.fromJson(data.toJson())
      ..accountScope = data.accountScope;
    _uploadDebounce = Timer(const Duration(seconds: 2), () {
      if (session.current) unawaited(upload(snapshot, session: session));
    });
  }

  static Future<void> flushUpload(MeritSaveData data) async {
    _uploadDebounce?.cancel();
    await upload(data);
  }

  static Future<void> upload(MeritSaveData data,
      {ApiSessionScope? session}) async {
    try {
      final scope = data.accountScope ??
          await AccountPreferenceScope.capture(session: session);
      scope.ensureCurrent();
      if (!scope.session.authenticated || scope.userId == null) return;
      final res = await scope.session
          .put('/api/merit/save', data: {'saveData': data.toJson()});
      scope.ensureCurrent();
      final body = res.data;
      if (body is Map && body['code'] == 409) {
        final serverData = (body['data'] as Map?)?['saveData'];
        if (serverData is Map) {
          final cloud =
              MeritSaveData.fromJson(Map<String, dynamic>.from(serverData));
          await scope.prefs.setString(
              scope.key('merit_save_v1'), jsonEncode(cloud.toJson()));
        }
      }
    } catch (_) {
      // 本地存档保留，下次当前账号保存时再同步。
    }
  }

  static Future<void> deleteCloud({AccountPreferenceScope? scope}) async {
    _uploadDebounce?.cancel();
    try {
      final bound = scope ?? await AccountPreferenceScope.capture();
      bound.ensureCurrent();
      if (!bound.session.authenticated || bound.userId == null) return;
      await bound.session.delete('/api/merit/save');
    } catch (_) {}
  }
}
