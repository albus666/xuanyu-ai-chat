import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:xuanyu/core/utils/android_media_picker.dart';

class _OtherPicker extends ImagePickerPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImagePickerPlatform previous;
  setUp(() => previous = ImagePickerPlatform.instance);
  tearDown(() => ImagePickerPlatform.instance = previous);

  test('Android 启用系统照片选择器且不替换当前平台实例', () {
    final picker = ImagePickerAndroid();
    ImagePickerPlatform.instance = picker;
    expect(picker.useAndroidPhotoPicker, isFalse);
    configureAndroidMediaPicker();
    expect(ImagePickerPlatform.instance, same(picker));
    expect(picker.useAndroidPhotoPicker, isTrue);
    configureAndroidMediaPicker();
    expect(picker.useAndroidPhotoPicker, isTrue);
  });

  test('iOS等其他平台实现保持原有选择流程', () {
    final picker = _OtherPicker();
    ImagePickerPlatform.instance = picker;
    configureAndroidMediaPicker();
    expect(ImagePickerPlatform.instance, same(picker));
  });
}
