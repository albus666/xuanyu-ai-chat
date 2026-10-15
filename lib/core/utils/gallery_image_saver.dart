import 'package:flutter/services.dart';

enum GalleryImageSaveDestination { gallery, file }

/// Saves to the photo library, or a user-selected file on older Android.
class GalleryImageSaver {
  GalleryImageSaver._();

  static const MethodChannel _channel = MethodChannel('xuanyu/media_save');

  static Future<GalleryImageSaveDestination> savePng(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (bytes.isEmpty) throw const GalleryImageSaveException('图片生成失败');
    final saved = await _channel.invokeMethod<Object>('savePng', {
      'bytes': bytes,
      'fileName': fileName.endsWith('.png') ? fileName : '$fileName.png',
    });
    if (saved is String && saved.isNotEmpty) {
      return GalleryImageSaveDestination.gallery;
    }
    if (saved is Map &&
        saved['uri'] is String &&
        (saved['uri'] as String).isNotEmpty &&
        saved['destination'] == 'file') {
      return GalleryImageSaveDestination.file;
    }
    throw const GalleryImageSaveException('图片保存失败');
  }
}

class GalleryImageSaveException implements Exception {
  const GalleryImageSaveException(this.message);

  final String message;
}
