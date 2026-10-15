import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/tool_share_message.dart';

class ToolSharePreview extends StatelessWidget {
  const ToolSharePreview({super.key, required this.message});
  final ToolShareMessage message;

  @override
  Widget build(BuildContext context) => InkWell(
        key: const ValueKey('chat-tool-share-card'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Get.toNamed(message.route),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome_outlined,
                    size: 22, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(message.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15))),
              ]),
              const SizedBox(height: 8),
              Text(message.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
              const SizedBox(height: 10),
              const Row(children: [
                Expanded(
                    child: Text('玄遇工具',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary))),
                Text('打开工具',
                    style: TextStyle(fontSize: 12, color: AppColors.primary)),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.primary),
              ]),
            ],
          ),
        ),
      );
}
