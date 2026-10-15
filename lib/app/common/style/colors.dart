import 'package:flutter/material.dart';

/// 玄遇 App 主题色板
class AppColors {
  AppColors._();

  // 主色：青绿
  static const Color primary = Color(0xFF1AC4C4);
  static const Color primaryLight = Color(0xFF6BE5DD);
  static const Color primaryDark = Color(0xFF12A8A8);

  // 主按钮渐变（青→蓝绿）
  static const List<Color> primaryGradient = [
    Color(0xFF21D4C5),
    Color(0xFF1FB6C0),
  ];

  // 顶部页面背景渐变（浅蓝→浅青→浅紫）
  static const List<Color> pageBgGradient = [
    Color(0xFFCDEBF6),
    Color(0xFFE6F4F8),
    Color(0xFFF1ECF7),
  ];

  // 首页背景渐变（仅顶部浅青，向下迅速过渡到白）
  static const List<Color> homeBgGradient = [
    Color(0xFF88E5FE),
    Color(0xffF6F6F6),
    Color(0xffF6F6F6),
  ];
  static const List<double> homeBgGradientStops = [0.0, 0.30, 1.0];

  // 文字色
  static const Color textPrimary = Color(0xFF222222);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textHint = Color(0xFF7A8794);
  static const Color textWhite = Color(0xFFFFFFFF);

  // 中性色
  static const Color white = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFEFEFEF);
  static const Color disabledBg = Color(0xFFF2F2F2);
  static const Color inputBg = Color(0xFFF7F7F7);

  // 标签 / 角标
  static const Color tagBg = Color(0xFFE6FAF7);
  static const Color tagText = Color(0xFF1AC4C4);

  // 五维度运势条
  static const List<Color> fortuneBars = [
    Color(0xFFF7A0AE), // 爱情
    Color(0xFFFFB572), // 财富
    Color(0xFF8DA4F1), // 事业
    Color(0xFF7DD7D0), // 学习
    Color(0xFFC79DEF), // 人际
  ];
}
