import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/style/colors.dart';

/// 新 UI 壳层主题（与 `core/theme/app_theme.dart` 区分命名）。
class ShellTheme {
  ShellTheme._();

  static const SystemUiOverlayStyle immersiveOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  static ThemeData light() {
    return ThemeData(
      useMaterial3: false,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
      ),
      fontFamily: 'PingFang SC',
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.45);
          }
          return AppColors.textHint.withValues(alpha: 0.35);
        }),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: immersiveOverlay,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFFFEFC),
        surfaceTintColor: Colors.transparent,
        elevation: 22,
        shadowColor: const Color(0x3D123B49),
        barrierColor: const Color(0x99091924),
        insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: Color(0xFFE7F0EF), width: 0.8),
        ),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19.sp,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: const Color(0xFF5F7075),
          fontSize: 14.sp,
          height: 1.65,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFFFFEFC),
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: Color(0x35123B49),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        dragHandleColor: Color(0xFFD3E0DF),
        dragHandleSize: Size(42, 4),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFEFC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xEE163A41),
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13.sp),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
