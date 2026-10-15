import 'package:flutter/services.dart';

class AppHaptics {
  static const _channel = MethodChannel('xuanyu/haptics');

  static Future<void> nudge() async {
    try {
      await _channel.invokeMethod<void>('nudge');
    } on MissingPluginException {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      await HapticFeedback.lightImpact();
    }
  }
}
