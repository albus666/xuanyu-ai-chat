import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 中文界面优先使用系统字体：iOS 为苹方、Android 为 Noto Sans CJK。
/// 不在运行时下载字体，弱网与离线环境也能稳定显示，不会出现首屏跳字。
class AppTextStyles {
  AppTextStyles._();

  static const _fallback = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
  ];

  static TextStyle get displayLarge => const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get titleLarge => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get titleMedium => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get titleSmall => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get bodyLarge => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.5,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.4,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get bodySmall => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get label => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get hint => const TextStyle(
        fontSize: 14,
        color: AppColors.textHint,
        fontFamilyFallback: _fallback,
      );

  static TextStyle get button => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        fontFamilyFallback: _fallback,
      );
}
