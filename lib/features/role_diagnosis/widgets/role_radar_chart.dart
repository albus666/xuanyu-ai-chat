import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xuanyu/features/role_diagnosis/models/role_diagnosis_models.dart';

/// 六维雷达图（星宿金描边）
class RoleRadarChart extends StatelessWidget {
  const RoleRadarChart({
    super.key,
    required this.radar,
    this.size = 180,
  });

  final RadarScores radar;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadarPainter(radar: radar),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.radar});

  final RadarScores radar;

  static const _labels = ['搞钱', '抗压', '桃花', '嘴炮', '背锅', '摸鱼'];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.32;
    final n = 6;
    final values = radar.values01;

    final grid = Paint()
      ..color = RoleDiagColors.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 1; ring <= 4; ring++) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / n;
        final p = c + Offset(math.cos(a), math.sin(a)) * (r * ring / 4.0);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, grid);
    }

    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawLine(c, p, grid);
    }

    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * values[i].clamp(0.1, 1.0);
      if (i == 0) {
        dataPath.moveTo(p.dx, p.dy);
      } else {
        dataPath.lineTo(p.dx, p.dy);
      }
    }
    dataPath.close();
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = RoleDiagColors.gold.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = RoleDiagColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final labelR = r + 18;
      final p = c + Offset(math.cos(a), math.sin(a)) * labelR;
      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: const TextStyle(
            color: RoleDiagColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.radar != radar;
}

/// 匹配指数圆环
class MatchRing extends StatelessWidget {
  const MatchRing({super.key, required this.score, this.size = 88});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(score: score),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: const TextStyle(
                  color: RoleDiagColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                '匹配',
                style: TextStyle(color: RoleDiagColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.score});
  final int score;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final bg = Paint()
      ..color = RoleDiagColors.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        colors: const [RoleDiagColors.gold, RoleDiagColors.trustBlue, RoleDiagColors.gold],
      ).createShader(Rect.fromCircle(center: c, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * (score / 100),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.score != score;
}
