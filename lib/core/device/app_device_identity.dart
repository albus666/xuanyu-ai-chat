import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _deviceIdKey = 'xuanyu_installation_device_id';

Future<Map<String, String>> appDevicePayload() async {
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString(_deviceIdKey);
  if (deviceId == null || deviceId.isEmpty) {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    deviceId = '${DateTime.now().microsecondsSinceEpoch}_$suffix';
    await prefs.setString(_deviceIdKey, deviceId);
  }
  final platform = Platform.operatingSystem;
  final deviceName = switch (platform) {
    'android' => 'Android 设备',
    'ios' => 'iPhone / iPad',
    'windows' => 'Windows 设备',
    'macos' => 'Mac 设备',
    _ => '当前设备',
  };
  return {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
  };
}
