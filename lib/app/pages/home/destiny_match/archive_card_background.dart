import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Static artwork only: the actual profile, spirit asset and privacy switch
/// remain independent foreground widgets, never baked into a sample image.
class ArchiveCardBackground extends StatelessWidget {
  const ArchiveCardBackground({super.key});

  static const gradient = LinearGradient(
    begin: Alignment(-1, -.2),
    end: Alignment(1, .25),
    colors: [Color(0xFF2DD3C4), Color(0xFF51BAFA), Color(0xFFA294F3)],
    stops: [0, .58, 1],
  );

  static Offset orbitCenter(Size size) =>
      Offset(size.width * .75, size.height * .54);

  static double orbitRadius(Size size) =>
      math.min(size.height * .37, size.width * .22);

  static Rect orbitOuterBounds(Size size) {
    if (size.isEmpty) return Rect.zero;
    final scale = size.shortestSide / 204;
    final outerRadius = orbitRadius(size) * 1.1 + .38 * scale;
    return Rect.fromCircle(center: orbitCenter(size), radius: outerRadius);
  }

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: gradient),
            child: CustomPaint(
              painter: _ArchiveSkyPainter(),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveSkyPainter extends CustomPainter {
  const _ArchiveSkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.shortestSide / 204;
    final center = ArchiveCardBackground.orbitCenter(size);
    final radius = ArchiveCardBackground.orbitRadius(size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Soft light under the illustration, with no opaque panel behind the text.
    final glowBounds = Rect.fromCircle(
      center: Offset(size.width * .62, size.height * .95),
      radius: size.width * .48,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x3857F0ED), Color(0x0057F0ED)],
        ).createShader(glowBounds),
    );

    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7 * scale
      ..color = Colors.white.withValues(alpha: .22);
    canvas.drawCircle(center, radius, orbit);
    canvas.drawCircle(center, radius * .76, orbit);
    final dotted = Paint()..color = Colors.white.withValues(alpha: .48);
    for (var i = 0; i < 96; i++) {
      final angle = 2 * math.pi * i / 96;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * 1.1);
      canvas.drawCircle(point, .38 * scale, dotted);
    }
    final axis = Paint()
      ..strokeWidth = .55 * scale
      ..color = Colors.white.withValues(alpha: .16);
    canvas.drawLine(
      center - Offset(radius, 0),
      center + Offset(radius, 0),
      axis,
    );
    canvas.drawLine(
      center - Offset(0, radius),
      center + Offset(0, radius),
      axis,
    );

    for (final angle in [-2.38, -.03, .7, 2.76]) {
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * .76);
      canvas.drawCircle(
        point,
        1.7 * scale,
        Paint()..color = Colors.white.withValues(alpha: .66),
      );
    }

    final moonCenter = center + Offset(radius * .57, -radius * .46);
    final moonRadius = 7.2 * scale;
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moonCenter, radius: moonRadius)),
      Path()..addOval(
        Rect.fromCircle(
          center: moonCenter + Offset(3.8 * scale, -2.5 * scale),
          radius: moonRadius,
        ),
      ),
    );
    canvas.drawPath(moon, Paint()..color = Colors.white.withValues(alpha: .65));

    // Keep most sparkle detail beside/behind the spirit, not beneath labels.
    const stars = <(double, double, double)>[
      (.62, .35, 3.8),
      (.69, .51, 2.9),
      (.64, .76, 1.4),
      (.92, .68, 1.7),
      (.94, .85, 1.4),
      (.89, .22, 1.1),
      (.57, .56, .9),
    ];
    for (final (x, y, extent) in stars) {
      _star(canvas, Offset(size.width * x, size.height * y), extent * scale);
    }
    for (final (x, y) in const [
      (.96, .4),
      (.94, .73),
      (.61, .65),
      (.73, .15),
    ]) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        .7 * scale,
        Paint()..color = Colors.white.withValues(alpha: .68),
      );
    }
    canvas.restore();
  }

  void _star(Canvas canvas, Offset center, double radius) {
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final length = i.isEven ? radius : radius * .2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * length;
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white.withValues(alpha: .78));
  }

  @override
  bool shouldRepaint(covariant _ArchiveSkyPainter oldDelegate) => false;
}
