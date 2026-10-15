import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/pages/main/controller.dart';
import 'package:xuanyu/app/bootstrap/startup_gate.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/auth/saved_account_store.dart';
import 'package:xuanyu/core/local/archive_cloud_sync.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';
import 'package:xuanyu/core/privacy/consent_services.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';
import 'package:xuanyu/core/utils/user_cache_utils.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/fortune/fortune_preload_coordinator.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';

/// 根路由依赖的登录态（协议、Token、未成年人模式等），与 Get 路由联动刷新。
class AuthState extends GetxController {
  AuthState(this.prefs);

  final SharedPreferences prefs;

  bool get agreementAccepted =>
      (prefs.getBool(AppConstants.keyAgreementAccepted) ?? false) &&
      prefs.getString(AppConstants.keyAgreementVersion) ==
          '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}';

  bool get hasToken =>
      (prefs.getString(AppConstants.keyToken) ?? '').isNotEmpty;

  int? get userId => prefs.getInt(AppConstants.keyUserId);

  bool get needOnboarding =>
      prefs.getBool(AppConstants.keyNeedOnboarding) ?? false;

  bool get isMinorMode => prefs.getBool(AppConstants.keyMinorMode) ?? false;

  String _todayString() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshDailyHealthCacheOnAppStart() async {
    if (!hasToken) return;
    final scope = ApiSessionScope();
    final dateKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthDate);
    final dataKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthCache);
    final today = _todayString();
    final cachedDate = prefs.getString(dateKey);
    final cached = prefs.getString(dataKey);
    if (cachedDate != today) {
      // 跨天自动清除旧缓存，避免展示昨天内容
      await prefs.remove(dataKey);
      if (!scope.current) return;
      await prefs.remove(dateKey);
    } else if (cached != null && cached.isNotEmpty) {
      // 当天有缓存就直接使用，不重复请求
      return;
    }
    try {
      final res = await scope.get('/api/fortune/daily-health');
      final data = (res.data as Map?)?['data'];
      if (data is Map) {
        await prefs.setString(dateKey, today);
        if (!scope.current) return;
        await prefs.setString(
          dataKey,
          jsonEncode(Map<String, dynamic>.from(data)),
        );
      }
    } catch (_) {
      // 启动预热失败不阻塞主流程，页面层会按自身逻辑重试/兜底
    }
  }

  Future<void> markAgreementAccepted() async {
    await prefs.setBool(AppConstants.keyAgreementAccepted, true);
    await prefs.setString(AppConstants.keyAgreementAcceptedAt,
        DateTime.now().toUtc().toIso8601String());
    await prefs.setString(AppConstants.keyAgreementVersion,
        '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}');
    await initializeConsentDependentServices();
    await _syncLegalConsent();
    update();
  }

  Future<void> _syncLegalConsent() async {
    if (!hasToken || !agreementAccepted) return;
    try {
      await apiClient.post('/api/auth/legal/consent', data: {
        'accepted': true,
        'userAgreementVersion': AppConstants.userAgreementVersion,
        'privacyPolicyVersion': AppConstants.privacyPolicyVersion,
        'acceptedAt': prefs.getString(AppConstants.keyAgreementAcceptedAt),
        'scene': 'app_start',
      });
    } catch (_) {
      // 网络恢复或下次登录时继续同步，不阻断用户进入。
    }
  }

  Future<void> setMinorMode(bool value) async {
    var effective = value;
    try {
      final response = await apiClient.post('/api/auth/minor-mode', data: {
        'enabled': value,
      });
      effective = (response.data as Map?)?['data']?['enabled'] == true;
    } catch (_) {
      // 服务端拒绝关闭或网络异常时不降低未成年人保护。
      if (!value) effective = true;
    }
    await prefs.setBool(AppConstants.keyMinorMode, effective);
    if (effective && Get.isRegistered<MainController>()) {
      final m = Get.find<MainController>();
      if (m.currentIndex == 2 || m.currentIndex == 3) {
        m.currentIndex = 0;
        m.update(['main']);
      }
    }
    update();
  }

  void completeOnboarding() {
    prefs.setBool(AppConstants.keyNeedOnboarding, false);
    update();
  }

  void notifyAuthChanged() {
    ArchiveCloudSync.start();
    _refreshDailyHealthCacheOnAppStart();
    _syncLegalConsent();
    unawaited(AppSettingsStore.instance.syncFromServer().catchError((_) {}));
    FortunePreloadCoordinator.schedule();
    update();
  }

  Future<bool> prepareSessionChange() async {
    final room = VoiceRoomOverlayController.instance;
    if (!room.hasActiveRoom) return true;
    room.restore();
    await room.requestClose();
    // 房主/付费连线取消退出或服务端退出失败时，保留原账号及房间。
    return !room.hasActiveRoom;
  }

  Future<bool> logout() async {
    if (!await prepareSessionChange()) return false;
    final currentUserId = userId;
    try {
      await apiClient.post('/api/auth/logout');
    } catch (_) {}
    if (currentUserId != null) {
      await FortunePreloadCoordinator.clearForUser(currentUserId);
    }
    await prefs.remove(AppConstants.keyToken);
    await prefs.remove(AppConstants.keyUserId);
    await clearUserDependentCache();
    if (currentUserId != null) await SavedAccountStore.remove(currentUserId);
    setupApiClientToken(null);
    update();
    return true;
  }

  Future<bool> prepareAddAccount() async {
    if (!await prepareSessionChange()) return false;
    FortunePreloadCoordinator.clearMemory();
    await prefs.remove(AppConstants.keyToken);
    await prefs.remove(AppConstants.keyUserId);
    await clearUserDependentCache();
    setupApiClientToken(null);
    update();
    return true;
  }

  Future<bool> activateSavedAccount(SavedAccountSession account) async {
    if (!await prepareSessionChange()) return false;
    FortunePreloadCoordinator.clearMemory();
    await clearUserDependentCache();
    await prefs.setString(AppConstants.keyToken, account.token);
    await prefs.setInt(AppConstants.keyUserId, account.userId);
    await prefs.setBool(AppConstants.keyMinorMode, account.minorMode);
    setupApiClientToken(account.token);
    await SavedAccountStore.rememberLogin(
      token: account.token,
      userId: account.userId,
      account: account.account,
      nickname: account.nickname,
      avatarUrl: account.avatarUrl,
      minorMode: account.minorMode,
    );
    notifyAuthChanged();
    return true;
  }

  void _onUnauthorized() {
    final message = (lastUnauthorizedMessage ?? '').trim();
    lastUnauthorizedMessage = null;
    showGlobalAppToast(
      message.isNotEmpty ? message : '登录已失效，请重新登录',
    );
    update();
  }

  @override
  void onInit() {
    super.onInit();
    unauthorizedTrigger.addListener(_onUnauthorized);
    unawaited(_warmCachesAfterStartup());
  }

  Future<void> _warmCachesAfterStartup() async {
    await StartupGate.ready;
    _refreshDailyHealthCacheOnAppStart();
    if (hasToken) {
      ArchiveCloudSync.start();
      unawaited(AppSettingsStore.instance.syncFromServer().catchError((_) {}));
      FortunePreloadCoordinator.schedule();
    }
  }

  @override
  void onClose() {
    unauthorizedTrigger.removeListener(_onUnauthorized);
    super.onClose();
  }
}
