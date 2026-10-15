import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/amap_platform_support.dart';

void main() {
  tearDown(AmapPlatformSupport.clearCache);

  test('Android 不再使用高德 3D 原生控件，避免正式包 JNI abort', () {
    expect(
      AmapPlatformSupport.isAndroidNativeMapSupported(
        abis: const ['arm64-v8a', 'armeabi-v7a'],
        primary: 'arm64-v8a',
        emulator: false,
      ),
      isFalse,
    );
  });

  test('非 Web 平台选点页应展示可交互地图，而不是改成只能手输', () async {
    expect(await AmapPlatformSupport.isMapSupported(), isTrue);
  });
}
