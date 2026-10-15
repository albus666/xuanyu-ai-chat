import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'post_publish',
  '发帖通知',
  description: '发布完成后提醒',
  importance: Importance.high,
  playSound: true,
);

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

Future<bool> isPostPublishNotificationEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(AppConstants.keyPostPublishNotificationEnabled) ?? true;
}

Future<void> setPostPublishNotificationEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(AppConstants.keyPostPublishNotificationEnabled, enabled);
}

/// 初始化本地通知（在 main 中调用一次）。返回是否请求到权限（iOS）。
Future<bool> initAppNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await _plugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
  if (Platform.isAndroid) {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }
  if (Platform.isIOS) {
    if (!await isPostPublishNotificationEnabled()) return false;
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    return granted ?? false;
  }
  return true;
}

/// 发帖前调用，请求通知权限（Android 13+ 与 iOS 必须授权后才能收到通知）
Future<void> requestNotificationPermission() async {
  if (!await isPostPublishNotificationEnabled()) return;
  if (Platform.isAndroid) {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
  if (Platform.isIOS) {
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }
}

/// 发布成功时展示本地通知
Future<void> showPostPublishSuccess({String message = '您的动态已发布，可到社区查看'}) async {
  if (!await isPostPublishNotificationEnabled()) return;
  await _plugin.show(
    1,
    '发布成功',
    message,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    ),
  );
}

/// 发布失败时展示本地通知
Future<void> showPostPublishFailure(String message) async {
  if (!await isPostPublishNotificationEnabled()) return;
  final msg = message.length > 50 ? '${message.substring(0, 50)}…' : message;
  await _plugin.show(
    2,
    '发布失败',
    msg,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    ),
  );
}
