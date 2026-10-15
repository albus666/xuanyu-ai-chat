import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/style/colors.dart';

/// 声波小芯片（圆形 + 内嵌声波）
class SoundWaveChip extends StatelessWidget {
  final double size;
  final Color background;
  final Color barColor;

  const SoundWaveChip({
    super.key,
    this.size = 36,
    this.background = Colors.white,
    this.barColor = AppColors.primary,
  });

  Widget _bar(double height) {
    return Container(
      width: 2,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: 1.w),
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = size.r;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _bar(8.h),
          _bar(14.h),
          _bar(6.h),
          _bar(11.h),
        ],
      ),
    );
  }
}
