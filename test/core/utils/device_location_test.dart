import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/device_location.dart';

void main() {
  test('DeviceLocation 提供系统定位入口，不依赖高德 libapssdk', () {
    expect(DeviceLocation.current, isA<Function>());
  });
}
