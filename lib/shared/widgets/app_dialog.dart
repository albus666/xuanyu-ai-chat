import 'package:flutter/material.dart';
import '../../core/theme/app_text_styles.dart';
import 'app_button.dart';

/// 国风风格确认弹窗
class AppDialog {
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    String? content,
    String confirmLabel = '确定',
    String cancelLabel = '取消',
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: AppTextStyles.titleMedium),
        content: content != null
            ? Text(content, style: AppTextStyles.bodyMedium)
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel, style: AppTextStyles.label),
          ),
          AppButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
