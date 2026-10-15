import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/style/colors.dart';

/// 通用主按钮：青绿渐变 + 圆角，整宽
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double? height;
  final double? radius;
  final bool enabled;
  final EdgeInsetsGeometry? margin;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.height,
    this.radius,
    this.enabled = true,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? 10.r;
    final h = height ?? 48.h;
    return Container(
      width: double.infinity,
      height: h,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: enabled
            ? const LinearGradient(
                colors: AppColors.primaryGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: enabled ? null : AppColors.disabledBg,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: enabled ? Colors.white : AppColors.textHint,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
