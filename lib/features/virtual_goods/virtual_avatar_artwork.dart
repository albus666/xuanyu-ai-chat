import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'virtual_avatar_catalog.dart';

/// 只渲染已经合成并通过人工检查的完整成品头像。
///
/// 旧版可编辑配置会回落到平台免费初始款，避免任何分层五官再次错位。
class VirtualAvatarArtwork extends StatelessWidget {
  const VirtualAvatarArtwork({
    super.key,
    required this.config,
    this.fit = BoxFit.cover,
    this.thumbnail = false,
    this.circular = false,
  });

  final Map<String, dynamic> config;
  final BoxFit fit;
  final bool thumbnail;
  final bool circular;

  static String assetPath(Map<String, dynamic> config) =>
      VirtualAvatarCatalog.assetPath(config) ??
      VirtualAvatarCatalog.finishedAssets['micro_jinglan']!;

  static List<String> assetPaths(Map<String, dynamic> config) =>
      [assetPath(config)];

  static ImageProvider<Object> imageProvider(
    Map<String, dynamic> config, {
    bool thumbnail = false,
  }) {
    final remoteUrl = thumbnail
        ? VirtualAvatarCatalog.thumbnailUrl(config)
        : VirtualAvatarCatalog.assetUrl(config);
    final ImageProvider<Object> provider = remoteUrl != null
        ? NetworkImage(remoteUrl)
        : AssetImage(assetPath(config));
    // Thumbnails share a bounded decode; previews and exports keep originals.
    return thumbnail ? ResizeImage(provider, width: 320) : provider;
  }

  static Future<void> precache(
    BuildContext context,
    Map<String, dynamic> config,
  ) =>
      precacheImage(imageProvider(config), context);

  /// Export the approved original independently of the preview's paint state.
  /// Cloud products keep their original URL through the server save endpoint.
  static Future<Uint8List> exportLocalPng(
    Map<String, dynamic> config, {
    int pixels = 1024,
  }) async {
    final source = await rootBundle.load(assetPath(config));
    final codec = await ui.instantiateImageCodec(
        source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes));
    ui.Image? original;
    ui.Image? output;
    ui.Picture? picture;
    try {
      original = (await codec.getNextFrame()).image;
      final edge = original.width < original.height
          ? original.width.toDouble()
          : original.height.toDouble();
      final target = Rect.fromLTWH(0, 0, pixels.toDouble(), pixels.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..clipPath(Path()..addOval(target));
      canvas.drawImageRect(
          original,
          Rect.fromLTWH((original.width - edge) / 2,
              (original.height - edge) / 2, edge, edge),
          target,
          Paint()..filterQuality = FilterQuality.high);
      picture = recorder.endRecording();
      output = await picture.toImage(pixels, pixels);
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('avatar encode failed');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      output?.dispose();
      picture?.dispose();
      original?.dispose();
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: imageProvider(config,
          thumbnail: thumbnail || MediaQuery.disableAnimationsOf(context)),
      fit: fit,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: const Color(0xFFE7EFEC),
          child: Center(
            child: SizedBox.square(
              dimension: thumbnail ? 20 : 28,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFFE7EFEC),
        child: Center(
          child: Icon(
            Icons.person_rounded,
            size: 72,
            color: Color(0xFF68847D),
          ),
        ),
      ),
    );
    return circular ? ClipOval(child: image) : image;
  }
}
