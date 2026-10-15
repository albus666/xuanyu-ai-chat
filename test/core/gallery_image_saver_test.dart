import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/gallery_image_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xuanyu/media_save');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final bytes = Uint8List.fromList([1, 2, 3]);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('existing photo library responses remain compatible', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments['fileName'], 'card.png');
      return 'content://media/new-image';
    });
    expect(await GalleryImageSaver.savePng(bytes, fileName: 'card'),
        GalleryImageSaveDestination.gallery);
  });

  test('system document export is reported as a file, not a gallery save',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'uri': 'content://documents/new-image',
              'destination': 'file',
            });
    expect(await GalleryImageSaver.savePng(bytes, fileName: 'card.png'),
        GalleryImageSaveDestination.file);
  });

  test('invalid or empty export results are not reported as success', () async {
    for (final result in [
      null,
      '',
      {'uri': '', 'destination': 'file'},
      {'uri': 7, 'destination': 'file'},
      {'uri': 'content://new', 'destination': 'unknown'}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => result);
      await expectLater(GalleryImageSaver.savePng(bytes, fileName: 'card'),
          throwsA(isA<GalleryImageSaveException>()));
    }
  });

  test('cancelling the system save dialog remains a cancellation', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
            code: 'PHOTO_SAVE_CANCELLED', message: '已取消保存图片'));
    await expectLater(
        GalleryImageSaver.savePng(bytes, fileName: 'card'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'PHOTO_SAVE_CANCELLED')));
  });
}
