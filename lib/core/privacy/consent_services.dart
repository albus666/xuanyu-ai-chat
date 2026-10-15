import 'dart:io';

import 'package:fluwx/fluwx.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/notification/app_notifications.dart';

bool _initialized = false;

/// 只有用户同意协议后才初始化通知、微信等非必要第三方能力。
Future<void> initializeConsentDependentServices() async {
  if (_initialized) return;
  try {
    await initAppNotifications();
  } catch (_) {}
  try {
    if (AppConstants.wxAppId != null && AppConstants.wxAppId!.isNotEmpty) {
      await Fluwx().registerApi(
        appId: AppConstants.wxAppId!,
        universalLink: Platform.isIOS
            ? (AppConstants.wxUniversalLink ?? 'https://xuanyu.app/wx/')
            : null,
      );
    }
  } catch (_) {}
  _initialized = true;
}
