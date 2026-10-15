import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 国风精修按钮
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.outline = false,
    this.width,
    this.height = 50,
    this.isFullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outline;
  final double? width;
  final double height;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null || loading;

    return SizedBox(
      width: isFullWidth ? double.infinity : width,
      height: height,
      child: outline ? _buildOutlineButton(isDisabled) : _buildElevatedButton(isDisabled),
    );
  }

  Widget _buildElevatedButton(bool isDisabled) {
    return Container(
      decoration: BoxDecoration(
        gradient: isDisabled ? null : AppColors.primaryGradient,
        color: isDisabled ? AppColors.textHint.withOpacity(0.3) : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white70,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _buildContent(Colors.white),
      ),
    );
  }

  Widget _buildOutlineButton(bool isDisabled) {
    return OutlinedButton(
      onPressed: isDisabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(
          color: isDisabled ? AppColors.divider : AppColors.primary,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: _buildContent(AppColors.primary),
    );
  }

  Widget _buildContent(Color textColor) {
    if (loading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(textColor),
        ),
      );
    }
    return Text(
      label,
      style: AppTextStyles.button.copyWith(color: textColor),
    );
  }
}
