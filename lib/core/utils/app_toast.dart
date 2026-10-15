import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

final Set<OverlayEntry> _activeAppToasts = <OverlayEntry>{};

void _removeAppToast(OverlayEntry entry) {
  if (!_activeAppToasts.remove(entry)) return;
  // inserted 与 mounted 不同：同一帧的新提示尚未 build，也必须移除。
  entry.remove();
  entry.dispose();
}

/// 页面切换时清理短提示，避免提示残留到上一页或首页。
void dismissAllAppToasts() {
  for (final entry in _activeAppToasts.toList(growable: false)) {
    _removeAppToast(entry);
  }
}

/// 在屏幕顶部显示提示（替代底部 SnackBar，统一顶部展示）
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  showGlobalAppToast(message, context: context, duration: duration);
}

/// 无 BuildContext 时也可调用（如 GetX Controller），自动查找 root Overlay。
void showGlobalAppToast(
  String message, {
  BuildContext? context,
  OverlayState? overlayState,
  Duration duration = const Duration(seconds: 2),
}) {
  dismissAllAppToasts();

  OverlayState? overlay = overlayState;
  final ctx = context ?? Get.context;
  if (ctx != null && overlay == null) {
    overlay = Overlay.maybeOf(ctx, rootOverlay: true);
  }
  overlay ??= Get.key.currentState?.overlay;

  if (overlay != null) {
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopToast(message: message),
    );
    _activeAppToasts.add(entry);
    overlay.insert(entry);
    if (context != null) {
      ModalRoute.of(context)?.popped.then((_) => _removeAppToast(entry));
    }
    Future.delayed(duration, () => _removeAppToast(entry));
    return;
  }

  Get.snackbar(
    '提示',
    message,
    snackPosition: SnackPosition.TOP,
    margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
    duration: duration,
    backgroundColor: AppColors.surface,
    colorText: AppColors.textPrimary,
  );
}

/// 在屏幕底部显示提示（用于表单保存等反馈）
void showAppBottomToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  Color? backgroundColor,
  Color? textColor,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message,
          style: AppTextStyles.bodyMedium
              .copyWith(color: textColor ?? AppColors.textPrimary)),
      duration: duration,
      backgroundColor: backgroundColor ?? AppColors.surface,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.divider.withValues(alpha: 0.45),
          width: 0.6,
        ),
      ),
      elevation: 0,
    ),
  );
  ModalRoute.of(context)?.popped.then((_) => controller.close());
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
  });

  final String message;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                top: topPadding > 0 ? 0 : 8, left: 16, right: 16),
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: AppColors.divider, width: 0.5),
                  ),
                  child: Text(
                    widget.message,
                    style: AppTextStyles.bodyMedium
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
