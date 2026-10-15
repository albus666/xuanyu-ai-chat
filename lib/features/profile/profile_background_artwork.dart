import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'profile_background_presets.dart';

/// Shared by the owner's page, visitor page, and fitting room.
class ProfileBackgroundArtwork extends StatelessWidget {
  const ProfileBackgroundArtwork({
    super.key,
    this.backgroundId,
    this.legacyUrl,
    this.dim = 0,
    this.fit = BoxFit.cover,
  });

  final String? backgroundId;
  final String? legacyUrl;
  final double dim;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final preset = profileBackgroundById(backgroundId);
    final url = legacyUrl?.trim() ?? '';
    return RepaintBoundary(
      child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          if (preset != null) ...[
            DecoratedBox(
                decoration:
                    BoxDecoration(gradient: profileBackgroundGradient(preset))),
            if (preset.assetPath != null) _assetArtwork(preset),
            CustomPaint(painter: _BackgroundPainter(preset)),
          ] else ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF55AEB7),
                    Color(0xFF72C6BD),
                    Color(0xFFB6D8C5)
                  ],
                  stops: [0, .52, 1],
                ),
              ),
            ),
            if (url.isNotEmpty)
              Image.network(url,
                  fit: fit,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ],
          if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ]),
      ),
    );
  }

  Widget _assetArtwork(ProfileBackgroundPreset preset) {
    final assetPath = preset.assetPath!;
    return Image.asset(
      assetPath,
      key: ValueKey(assetPath),
      alignment:
          preset.foregroundAsset ? Alignment.center : Alignment.topCenter,
      fit: fit,
      gaplessPlayback: true,
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.preset);

  final ProfileBackgroundPreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    const phase = 0.0;
    if (preset.assetPath == null) {
      canvas.drawRect(
          rect,
          Paint()
            ..shader = profileBackgroundGradient(preset).createShader(rect));
    }
    final glowCenter = Offset(size.width * .78, size.height * .2);
    final radius = size.longestSide * .48;
    canvas.drawCircle(
        glowCenter,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [
            preset.accent.withValues(alpha: .28),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: glowCenter, radius: radius)));

    if (preset.motion == ProfileBackgroundMotion.tide) {
      canvas.drawCircle(glowCenter, size.shortestSide * .07,
          Paint()..color = preset.accent.withValues(alpha: .85));
    }
    final hasFullBleedAsset =
        preset.assetPath != null && !preset.foregroundAsset;
    final waves = hasFullBleedAsset
        ? 0
        : preset.motion == ProfileBackgroundMotion.aurora
            ? 5
            : 3;
    for (var i = 0; i < waves; i++) {
      const sway = 0.0;
      final path = Path()
        ..moveTo(-size.width * .1, size.height * (.60 + i * .085 + sway))
        ..cubicTo(
            size.width * .22,
            size.height * (.44 + i * .075 - sway),
            size.width * .60,
            size.height * (.86 + i * .04 + sway),
            size.width * 1.1,
            size.height * (.54 + i * .075 - sway));
      canvas.drawPath(
          path,
          Paint()
            ..color = preset.accent.withValues(alpha: .12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = preset.motion == ProfileBackgroundMotion.aurora
                ? size.shortestSide * (.022 + i * .006)
                : 1.8
            ..strokeCap = StrokeCap.round);
    }

    final count = switch (preset.motion) {
      ProfileBackgroundMotion.stars => 32,
      ProfileBackgroundMotion.swim ||
      ProfileBackgroundMotion.drift ||
      ProfileBackgroundMotion.pulse ||
      ProfileBackgroundMotion.snowfall =>
        26,
      _ => 18,
    };
    for (var i = 0; i < count; i++) {
      final angle = phase + i * 1.73;
      final drift = preset.motion == ProfileBackgroundMotion.fireflies ||
          preset.foregroundAsset;
      final point = Offset(
        size.width *
            (((i * 193 + 41) % 997) / 997 +
                (drift ? math.sin(angle) * .022 : 0)),
        size.height *
            (((i * 127 + 83) % 787) / 787 +
                (drift ? math.cos(angle) * .03 : 0)),
      );
      const opacity = .3;
      final particleRadius = preset.motion == ProfileBackgroundMotion.snowfall
          ? 1.2 + (i % 3) * .55
          : 1.0 + (i % 3) * .65;
      canvas.drawCircle(point, particleRadius,
          Paint()..color = preset.accent.withValues(alpha: opacity));
      if (drift) {
        final halo = preset.motion == ProfileBackgroundMotion.swim ||
                preset.motion == ProfileBackgroundMotion.drift ||
                preset.motion == ProfileBackgroundMotion.pulse
            ? 5.5 + (i % 3) * 1.8
            : 5.0;
        canvas.drawCircle(
            point,
            halo,
            Paint()
              ..style = preset.motion == ProfileBackgroundMotion.swim ||
                      preset.motion == ProfileBackgroundMotion.drift ||
                      preset.motion == ProfileBackgroundMotion.pulse
                  ? PaintingStyle.stroke
                  : PaintingStyle.fill
              ..strokeWidth = 1
              ..color = preset.accent.withValues(alpha: opacity * .16));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      oldDelegate.preset != preset;
}
