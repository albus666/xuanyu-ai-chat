import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../network/api_client.dart';

const String _configuredDistributionChannel = String.fromEnvironment(
  'APP_DISTRIBUTION_CHANNEL',
  defaultValue: '',
);

class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.available,
    required this.required,
    required this.latestVersion,
    required this.latestBuild,
    required this.title,
    required this.message,
    required this.releaseNotes,
    required this.updateUrl,
    required this.delivery,
    required this.checkIntervalHours,
  });

  factory AppUpdatePolicy.fromJson(Map<dynamic, dynamic> json) {
    return AppUpdatePolicy(
      available: json['updateAvailable'] == true,
      required: json['required'] == true,
      latestVersion: json['latestVersion']?.toString() ?? '',
      latestBuild: int.tryParse(json['latestBuild']?.toString() ?? '') ?? 0,
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : '发现新版本',
      message: json['message']?.toString().trim() ?? '',
      releaseNotes: (json['releaseNotes'] is List)
          ? (json['releaseNotes'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const [],
      updateUrl: json['updateUrl']?.toString().trim() ?? '',
      delivery: json['delivery']?.toString() ?? 'external',
      checkIntervalHours:
          int.tryParse(json['checkIntervalHours']?.toString() ?? '') ?? 24,
    );
  }

  final bool available;
  final bool required;
  final String latestVersion;
  final int latestBuild;
  final String title;
  final String message;
  final List<String> releaseNotes;
  final String updateUrl;
  final String delivery;
  final int checkIntervalHours;
}

class AppUpdateCheck {
  const AppUpdateCheck({required this.policy, required this.packageInfo});

  final AppUpdatePolicy policy;
  final PackageInfo packageInfo;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();
  static const MethodChannel _playCoreChannel = MethodChannel(
    'xuanyu/app_update',
  );
  static const _installationKey = 'app_update_installation_id_v1';
  static const _lastCheckKey = 'app_update_last_check_at_v1';
  static const _intervalKey = 'app_update_check_interval_hours_v1';
  static const _snoozedDateKey = 'app_update_snoozed_local_date_v1';

  bool _checking = false;

  static String distributionChannelFor(PackageInfo packageInfo) {
    if ((defaultTargetPlatform == TargetPlatform.iOS)) return 'app_store';
    if (_configuredDistributionChannel.isNotEmpty) {
      return _configuredDistributionChannel;
    }
    final installer = (packageInfo.installerStore ?? '').toLowerCase();
    if (installer == 'com.android.vending') return 'google_play';
    const packageInstallers = {
      'com.android.packageinstaller',
      'com.google.android.packageinstaller',
      'com.miui.packageinstaller',
      'com.samsung.android.packageinstaller',
    };
    if (installer.isNotEmpty && !packageInstallers.contains(installer)) {
      return 'android_store';
    }
    return 'official_apk';
  }

  Future<AppUpdateCheck?> check({bool manual = false}) async {
    if (_checking ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!manual &&
          !(prefs.getBool(AppConstants.keyAgreementAccepted) ?? false)) {
        return null;
      }
      if (!manual && !_isCheckDue(prefs)) return null;
      final packageInfo = await PackageInfo.fromPlatform();
      final channel = distributionChannelFor(packageInfo);
      final installationId = await _installationId(prefs);
      final response = await apiClient.get(
        '/api/config/app-update',
        queryParameters: {
          'platform':
              (defaultTargetPlatform == TargetPlatform.iOS) ? 'ios' : 'android',
          'currentVersion': packageInfo.version,
          'currentBuild': packageInfo.buildNumber,
          'channel': channel,
          'installationId': installationId,
        },
      );
      final envelope = response.data;
      if (envelope is! Map ||
          envelope['code'] != 0 ||
          envelope['data'] is! Map) {
        throw const FormatException('更新服务返回格式错误');
      }
      final policy = AppUpdatePolicy.fromJson(envelope['data'] as Map);
      final snoozedDate = prefs.getString(_snoozedDateKey);
      if (snoozedDate != null && snoozedDate != localDateKey(DateTime.now())) {
        await prefs.remove(_snoozedDateKey);
      }
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_intervalKey, policy.checkIntervalHours.clamp(1, 168));
      return AppUpdateCheck(policy: policy, packageInfo: packageInfo);
    } finally {
      _checking = false;
    }
  }

  // 按设备当地自然日记录，跨午夜即可再次提示，手动检查和强制更新不受影响。
  static String localDateKey(DateTime now) =>
      '${now.year}-${now.month}-${now.day}';

  static bool shouldSuppressPrompt({
    required String? snoozedDate,
    required DateTime now,
    bool manual = false,
    bool requiredUpdate = false,
  }) =>
      !manual && !requiredUpdate && snoozedDate == localDateKey(now);

  Future<void> snoozeToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snoozedDateKey, localDateKey(DateTime.now()));
  }

  Future<bool> shouldPrompt(
    AppUpdatePolicy policy, {
    bool manual = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return !shouldSuppressPrompt(
      snoozedDate: prefs.getString(_snoozedDateKey),
      now: DateTime.now(),
      manual: manual,
      requiredUpdate: policy.required,
    );
  }

  Future<bool> startUpdate(AppUpdatePolicy policy) async {
    if ((defaultTargetPlatform == TargetPlatform.android) &&
        policy.delivery == 'play_core') {
      try {
        final result = await _playCoreChannel.invokeMapMethod<String, dynamic>(
          'startUpdate',
          {'immediate': policy.required},
        );
        if (result?['started'] == true) return true;
      } on PlatformException {
        // Google Play 不可用时继续尝试后台配置的商店落地页。
      }
    }
    if (policy.updateUrl.isEmpty) return false;
    final uri = Uri.tryParse(policy.updateUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> completeFlexibleUpdate() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _playCoreChannel.invokeMethod<void>('completeFlexibleUpdate');
  }

  void setPlayCoreHandler(Future<void> Function()? onDownloaded) {
    _playCoreChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFlexibleUpdateDownloaded') {
        await onDownloaded?.call();
      }
    });
  }

  bool _isCheckDue(SharedPreferences prefs) {
    final snoozedDate = prefs.getString(_snoozedDateKey);
    if (snoozedDate != null && snoozedDate != localDateKey(DateTime.now())) {
      return true;
    }
    final last = prefs.getInt(_lastCheckKey) ?? 0;
    final interval = (prefs.getInt(_intervalKey) ?? 24).clamp(1, 168);
    return DateTime.now().millisecondsSinceEpoch - last >=
        Duration(hours: interval).inMilliseconds;
  }

  Future<String> _installationId(SharedPreferences prefs) async {
    final existing = prefs.getString(_installationKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final value = List.generate(
      4,
      (_) => random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0'),
    ).join();
    await prefs.setString(_installationKey, value);
    return value;
  }
}
