import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/common/routers/names.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

/// 统一部落标识（公开场景只显示部落名称，不展示内部成员角色）。
class TeamTitleChip extends StatelessWidget {
  const TeamTitleChip({super.key, this.title, this.userId});

  final String? title;
  final int? userId;

  Future<void> _openTeam(BuildContext context) async {
    final targetUserId = userId;
    if (targetUserId == null || targetUserId <= 0) {
      showAppToast(context, '暂时无法打开该部落');
      return;
    }
    try {
      final response = await apiClient.get('/api/im/user/$targetUserId/team');
      final raw = (response.data as Map?)?['data'];
      if (raw is! Map) throw StateError('team unavailable');
      await Get.toNamed(RouteNames.teamHome,
          arguments: Map<String, dynamic>.from(raw));
    } catch (_) {
      if (context.mounted) showAppToast(context, '暂时无法打开该部落');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = title?.trim() ?? '';
    if (t.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openTeam(context),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22), width: 0.7),
          ),
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            t,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 9,
              height: 1.05,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
