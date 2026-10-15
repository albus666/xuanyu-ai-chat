import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// 图片压缩工具：在上传前将图片压缩为较小尺寸
class ImageUtils {
  ImageUtils._();

  /// 头像压缩：最大边长 400px，质量 80
  static const int avatarMaxSize = 400;
  static const int avatarQuality = 80;

  /// 动态图片压缩：最大边长 1200px，质量 85
  static const int postMaxSize = 1200;
  static const int postQuality = 85;

  /// 压缩图片，返回压缩后的临时文件；失败时返回原文件
  static Future<File> compressForUpload(
    File file, {
    int maxSize = postMaxSize,
    int quality = postQuality,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        minWidth: maxSize,
        minHeight: maxSize,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result != null) return File(result.path);
    } catch (_) {}
    return file;
  }

  /// 压缩头像
  static Future<File> compressAvatar(File file) =>
      compressForUpload(file, maxSize: avatarMaxSize, quality: avatarQuality);

  /// 压缩动态图片
  static Future<File> compressPostImage(File file) =>
      compressForUpload(file, maxSize: postMaxSize, quality: postQuality);
}
