import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// 系统定位。Android 10 上高德 `libapssdk` 会在 LocationScheduler 线程 JNI abort。
class DeviceLocation {
  DeviceLocation._();

  static Future<({double latitude, double longitude})?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      return (latitude: last.latitude, longitude: last.longitude);
    }
  }
}
