import 'package:flutter/material.dart';

/// 国风主题色值（与 Shell 青绿主题统一）
class AppColors {
  AppColors._();

  // 主色调：青绿
  static const Color primary = Color(0xFF1AC4C4);
  static const Color primaryDark = Color(0xFF12A8A8);
  static const Color primaryLight = Color(0xFFE6FAF7);

  // 辅助色：琥珀金
  static const Color accentGold = Color(0xFFB45309);
  static const Color goldLight = Color(0xFFFEF3C7);

  // 中性色
  static const Color textPrimary = Color(0xFF222222);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textHint = Color(0xFF7A8794);

  // 背景色
  static const Color background = Color(0xFFF8FAFC);
  static const Color backgroundDeep = Color(0xFFEEF2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFF1F5F9);

  static const LinearGradient scaffoldBodyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, backgroundDeep],
  );

  // 社区采用编辑式白色画布。层级由排版和留白建立，避免大面积渐变
  // 与卡片底色打断阅读。
  static const Color communityScaffold = Color(0xFFFFFFFF);
  static const Color communityScaffoldDeep = Color(0xFFFFFFFF);
  static const Color communityAccent = Color(0xFF1AC4C4);
  static const LinearGradient communityBodyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [communityScaffold, communityScaffoldDeep],
  );
  static const Color communityInsetSurface = Color(0xFFF7F8F9);

  // 社区信息层级专用中性色。避免复用全站偏深的 textHint，导致时间、
  // 属地与操作抢正文。
  static const Color communityText = Color(0xFF303236);
  static const Color communityName = Color(0xFF858A91);
  static const Color communityMeta = Color(0xFFADB2B8);
  static const Color communityDivider = Color(0xFFECEEF1);

  static const Color divider = Color(0xFFE2E8F0);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);

  static const Color chatBubbleMe = Color(0xFFDCFCE7);
  static const Color chatBubbleOther = Color(0xFFFFFFFF);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF21D4C5), Color(0xFF1FB6C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
