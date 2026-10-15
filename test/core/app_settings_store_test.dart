import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/device/app_device_identity.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('客户端偏好从本地恢复且安装设备标识保持稳定', () async {
    SharedPreferences.setMockInitialValues({
      'app_setting_reduceMotion': true,
      'app_setting_largerText': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await AppSettingsStore.instance.initialize(prefs);

    expect(AppSettingsStore.instance.boolValue('reduceMotion'), isTrue);
    expect(AppSettingsStore.instance.boolValue('largerText'), isTrue);

    final first = await appDevicePayload();
    final second = await appDevicePayload();
    expect(first['deviceId'], isNotEmpty);
    expect(second['deviceId'], first['deviceId']);
    expect(first['platform'], isNotEmpty);
  });
}
