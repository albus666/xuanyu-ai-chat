import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 地图选点是否可用。Android 10+ 走瓦片地图，不再创建高德 3D [AMapWidget]
///（11.2.100 在 Android 10 正式包的 GL 线程 `loadLibrary` 会 JNI abort）。
class AmapPlatformSupport {
  AmapPlatformSupport._();

  static const _channel = MethodChannel('xuanyu/device_abi');
  static bool? _cachedMapSupported;

  /// iOS 继续用原生高德 3D；Android / 其它非 Web 平台用瓦片选点。
  static bool get useNativeAmapWidget =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 当前设备是否展示可点选的地图（不是改成只能手输）。
  static Future<bool> isMapSupported() async {
    if (_cachedMapSupported != null) return _cachedMapSupported!;
    if (kIsWeb) {
      _cachedMapSupported = false;
      return false;
    }
    if (useNativeAmapWidget) {
      _cachedMapSupported = true;
      return true;
    }
    // Android 10+ 以及模拟器都用瓦片地图，不再探测 ABI。
    _cachedMapSupported = true;
    return true;
  }

  /// 仅 iOS 走原生 3D。Android 上创建 [AMapWidget] 会在 vivo/Android 10 正式包闪退。
  static bool isAndroidNativeMapSupported({
    required List<String> abis,
    required String primary,
    required bool emulator,
  }) {
    return false;
  }

  /// 保留通道读取，供诊断；选点页不再用它决定是否渲染地图。
  static Future<Map<String, dynamic>?> readAbiInfo() async {
    try {
      final info =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getAbiInfo');
      return info?.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return null;
    }
  }

  /// 测试或热更新后清缓存。
  static void clearCache() => _cachedMapSupported = null;
}
