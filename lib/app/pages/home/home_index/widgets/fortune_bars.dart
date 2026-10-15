import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/style/colors.dart';

class FortuneBarItem {
  final String label;
  final int value;
  final Color color;
  const FortuneBarItem(this.label, this.value, this.color);
}

/// 五维度运势柱状图（爱情 / 财富 / 事业 / 学习 / 人际）
class FortuneBars extends StatelessWidget {
  final List<FortuneBarItem> items;
  final double maxBarHeight;
  final bool compact;

  const FortuneBars({
    super.key,
    List<FortuneBarItem>? items,
    this.maxBarHeight = 50,
    this.compact = false,
  }) : items = items ?? _defaultItems;

  static const List<FortuneBarItem> _defaultItems = [
    FortuneBarItem('爱情', 88, Color(0xFFF7A0AE)),
    FortuneBarItem('财富', 96, Color(0xFFFFB572)),
    FortuneBarItem('事业', 95, Color(0xFF8DA4F1)),
    FortuneBarItem('学习', 86, Color(0xFF7DD7D0)),
    FortuneBarItem('人际', 92, Color(0xFFC79DEF)),
  ];

  Widget _buildBar(FortuneBarItem item) {
    final ratio = item.value.clamp(0, 100) / 100.0;
    final maxH = maxBarHeight.h;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: compact ? 6.w : 7.w,
          height: maxH,
          child: Stack(
            children: [
              // 半透明背景轨道
              Container(
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
              // 实际填充
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: maxH * ratio,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [item.color.withValues(alpha: 0.4), item.color],
                    ),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          '${item.value}',
          style: TextStyle(
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          item.label,
          style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: items.map(_buildBar).toList(),
    );
  }
}
