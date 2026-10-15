import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 同心圆装饰背景（语音匹配 3 态共用）
class MatchCircles extends StatelessWidget {
  final Widget center;
  final double size;
  const MatchCircles({super.key, required this.center, this.size = 280});

  Widget _ring(double diameter, {Color? color}) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color ?? const Color(0xFFE6E6E6),
          width: 0.6,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = size.r;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 渐变背景圆
          Container(
            width: s,
            height: s,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0x33B7E1FA),
                  Color(0x22FFCAB1),
                  Colors.transparent,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          _ring(s * 0.95),
          _ring(s * 0.78),
          _ring(s * 0.6),
          // 装饰小点
          Positioned(
            left: s * 0.07,
            top: s * 0.5 - 3,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFCDCDCD),
              ),
            ),
          ),
          Positioned(
            bottom: s * 0.18,
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFCDCDCD),
              ),
            ),
          ),
          center,
        ],
      ),
    );
  }
}
