import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/style/colors.dart';

/// 圆环 + 中心分数（首页运势卡 / 今日运势页头部 共用）
class FortuneScoreRing extends StatelessWidget {
  final int score;
  final double size;
  final String? bottomLabel;
  final bool large;

  const FortuneScoreRing({
    super.key,
    required this.score,
    this.size = 56,
    this.bottomLabel,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = size.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: s,
          height: s,
          child: CustomPaint(
            painter: _RingPainter(score: score),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: large ? 24.sp : 20.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        if (bottomLabel != null) ...[
          SizedBox(height: 4.h),
          Text(bottomLabel!,
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.textSecondary,
              )),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final int score;
  _RingPainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.12;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final bg = Paint()
      ..color = const Color(0xFFE7F4FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);

    final ratio = (score.clamp(0, 100)) / 100.0;
    final fg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF8DA4F1), Color(0xFF7DD7D0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.score != score;
}
