import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';
import 'package:xuanyu/features/emotion/services/emotion_pet_service.dart';

/// 情绪宠物牛：健康值越低越枯萎
class EmotionPetCow extends StatelessWidget {
  const EmotionPetCow({
    super.key,
    required this.health,
    this.size = 120,
    this.emotion,
    this.animate = true,
  });

  final int health;
  final double size;
  final EmotionType? emotion;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.1,
      child: CustomPaint(
        painter: _CowPainter(
          health: health,
          emotion: emotion,
          time: animate ? DateTime.now().millisecondsSinceEpoch / 1000.0 : 0,
        ),
      ),
    );
  }
}

class _CowPainter extends CustomPainter {
  _CowPainter({
    required this.health,
    this.emotion,
    required this.time,
  });

  final int health;
  final EmotionType? emotion;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final vitality = (health / 100).clamp(0.1, 1.0);
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h * 0.55;

    final grassPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(const Color(0xFF8BC34A), const Color(0xFFBDBDBD), 1 - vitality)!,
          Color.lerp(const Color(0xFF4CAF50), const Color(0xFF9E9E9E), 1 - vitality)!,
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.75, w, h * 0.25));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), grassPaint);

    final bodyColor = Color.lerp(
      const Color(0xFFF5F0E8),
      const Color(0xFFD7CCC8),
      1 - vitality,
    )!;
    final bodyPaint = Paint()..color = bodyColor;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy + 4),
        width: w * 0.72,
        height: h * 0.42,
      ),
      const Radius.circular(28),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    final spotPaint = Paint()
      ..color = Color.lerp(const Color(0xFF5D4037), const Color(0xFF9E9E9E), 1 - vitality)!
          .withValues(alpha: 0.5);
    canvas.drawCircle(Offset(cx - w * 0.15, cy), w * 0.06, spotPaint);
    canvas.drawCircle(Offset(cx + w * 0.12, cy + 8), w * 0.05, spotPaint);

    final headPaint = Paint()..color = bodyColor;
    canvas.drawCircle(Offset(cx, cy - h * 0.18), w * 0.28, headPaint);

    final earPaint = Paint()..color = const Color(0xFFE8D5C4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - w * 0.22, cy - h * 0.28), width: w * 0.12, height: h * 0.08),
      earPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + w * 0.22, cy - h * 0.28), width: w * 0.12, height: h * 0.08),
      earPaint,
    );

    final hornPaint = Paint()
      ..color = Color.lerp(const Color(0xFF8D6E63), const Color(0xFFBDBDBD), 1 - vitality)!
      ..style = PaintingStyle.fill;
    final hornPath = Path()
      ..moveTo(cx - w * 0.12, cy - h * 0.32)
      ..quadraticBezierTo(cx - w * 0.18, cy - h * 0.48, cx - w * 0.08, cy - h * 0.42);
    canvas.drawPath(hornPath, hornPaint);
    final hornPath2 = Path()
      ..moveTo(cx + w * 0.12, cy - h * 0.32)
      ..quadraticBezierTo(cx + w * 0.18, cy - h * 0.48, cx + w * 0.08, cy - h * 0.42);
    canvas.drawPath(hornPath2, hornPaint);

    final eyeOpen = vitality > 0.3;
    final eyePaint = Paint()..color = const Color(0xFF333333);
    if (eyeOpen) {
      final bounce = math.sin(time * 2) * 1.5 * vitality;
      canvas.drawCircle(Offset(cx - w * 0.1, cy - h * 0.2 + bounce), w * 0.035, eyePaint);
      canvas.drawCircle(Offset(cx + w * 0.1, cy - h * 0.2 + bounce), w * 0.035, eyePaint);
      final hiPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(cx - w * 0.08, cy - h * 0.22 + bounce), w * 0.012, hiPaint);
      canvas.drawCircle(Offset(cx + w * 0.12, cy - h * 0.22 + bounce), w * 0.012, hiPaint);
    } else {
      final linePaint = Paint()
        ..color = const Color(0xFF666666)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx - w * 0.14, cy - h * 0.2), Offset(cx - w * 0.06, cy - h * 0.2), linePaint);
      canvas.drawLine(Offset(cx + w * 0.06, cy - h * 0.2), Offset(cx + w * 0.14, cy - h * 0.2), linePaint);
    }

    final nosePaint = Paint()..color = const Color(0xFFFFAB91);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - h * 0.08), width: w * 0.18, height: h * 0.07),
      nosePaint,
    );
    final nostrilPaint = Paint()..color = const Color(0xFFBF360C);
    canvas.drawCircle(Offset(cx - w * 0.03, cy - h * 0.08), w * 0.015, nostrilPaint);
    canvas.drawCircle(Offset(cx + w * 0.03, cy - h * 0.08), w * 0.015, nostrilPaint);

    final mouthPaint = Paint()
      ..color = const Color(0xFF795548)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (emotion == EmotionType.happy || emotion == EmotionType.excited) {
      final smile = Path()
        ..moveTo(cx - w * 0.06, cy - h * 0.02)
        ..quadraticBezierTo(cx, cy + h * 0.02, cx + w * 0.06, cy - h * 0.02);
      canvas.drawPath(smile, mouthPaint);
    } else if (vitality < 0.4) {
      canvas.drawLine(Offset(cx - w * 0.05, cy), Offset(cx + w * 0.05, cy), mouthPaint);
    }

    final legPaint = Paint()..color = bodyColor;
    for (final dx in [-0.22, -0.08, 0.08, 0.22]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + w * dx, cy + h * 0.22), width: w * 0.1, height: h * 0.12),
          const Radius.circular(6),
        ),
        legPaint,
      );
    }

    if (emotion != null && vitality > 0.2) {
      final bubblePaint = Paint()..color = emotion!.color.withValues(alpha: 0.9);
      canvas.drawCircle(Offset(cx + w * 0.32, cy - h * 0.38), w * 0.14, bubblePaint);
      final tp = TextPainter(
        text: TextSpan(text: emotion!.emoji, style: TextStyle(fontSize: w * 0.12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx + w * 0.32 - tp.width / 2, cy - h * 0.38 - tp.height / 2));
    }

    if (vitality < 0.5) {
      final wiltPaint = Paint()
        ..color = const Color(0xFF9E9E9E).withValues(alpha: 0.4)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < 5; i++) {
        final x = w * 0.15 + i * w * 0.17;
        canvas.drawLine(Offset(x, h * 0.78), Offset(x - 3, h * 0.72), wiltPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CowPainter old) =>
      old.health != health || old.emotion != emotion;
}

class PetStatusCard extends StatelessWidget {
  const PetStatusCard({super.key, required this.state});

  final PetState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          EmotionPetCow(
            health: state.health,
            emotion: state.lastEmotion,
            size: 80,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  state.statusText,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.health / 100,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      state.health >= 60
                          ? const Color(0xFF1AC4C4)
                          : state.health >= 30
                              ? const Color(0xFFFFB572)
                              : const Color(0xFFFF6B6B),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '元气 ${state.health}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
