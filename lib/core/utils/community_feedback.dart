import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class NotInterestedReason {
  const NotInterestedReason({
    required this.code,
    required this.label,
    required this.group,
  });

  final String code;
  final String label;
  final String group;
}

const notInterestedReasons = <NotInterestedReason>[
  NotInterestedReason(
    code: 'less_author',
    label: '不喜欢该作者',
    group: '💔  不感兴趣',
  ),
  NotInterestedReason(
    code: 'dislike_post',
    label: '不喜欢该内容',
    group: '💔  不感兴趣',
  ),
  NotInterestedReason(
    code: 'clickbait',
    label: '标题党博眼球',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'fraudulent',
    label: '虚假欺诈',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'suspected_marketing',
    label: '疑似广告',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'too_similar',
    label: '相似过多',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'sexual',
    label: '色情低俗',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'uncomfortable',
    label: '引起不适',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'negative_emotion',
    label: '负向情绪',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'conflict_bait',
    label: '对立引战',
    group: '🙃  内容反馈',
  ),
  NotInterestedReason(
    code: 'fake_persona',
    label: '假人设',
    group: '🙃  内容反馈',
  ),
];

Future<NotInterestedReason?> showNotInterestedReasonSheet(
  BuildContext context,
) {
  final groups = <String, List<NotInterestedReason>>{};
  for (final reason in notInterestedReasons) {
    groups.putIfAbsent(reason.group, () => []).add(reason);
  }
  return showModalBottomSheet<NotInterestedReason>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 17, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded, size: 30),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '选择不喜欢的原因，减少相似推荐',
                      maxLines: 1,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: const Color(0xFF25262A),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 23),
              for (final entry in groups.entries) ...[
                Text(
                  entry.key,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.communityMeta,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: entry.value
                      .map(
                        (reason) => InkWell(
                          onTap: () => Navigator.pop(sheetContext, reason),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            constraints: BoxConstraints(
                              minWidth:
                                  (MediaQuery.sizeOf(sheetContext).width - 44) /
                                      2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.communityDivider,
                              ),
                            ),
                            child: Text(
                              reason.label,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.communityText,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Future<bool> confirmUnfollow(
  BuildContext context, {
  required String nickname,
}) async {
  final displayName = nickname.trim().isEmpty ? 'TA' : nickname.trim();
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            '不再关注$displayName了？',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          content: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F2F4),
                      foregroundColor: AppColors.textSecondary,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.communityAccent,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('不再关注'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ) ??
      false;
}
