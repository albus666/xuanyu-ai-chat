import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallBackgroundAudio {
  static const _channel = MethodChannel('xuanyu/voice_room_audio');

  static Future<void> update(
    String owner,
    bool active, {
    String title = '玄遇通话进行中',
    bool microphone = true,
    bool camera = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(active ? 'start' : 'stop', {
        'owner': owner,
        if (active) ...{
          'title': title,
          'microphone': microphone,
          'camera': camera
        },
      });
    } on MissingPluginException {
      // No native service in widget tests or unsupported hosts.
    } on PlatformException {
      // The current connection remains usable if the native service is unavailable.
    }
  }
}
