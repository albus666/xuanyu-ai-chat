import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/theme/app_colors.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

class MeritShareCard extends StatelessWidget {
  const MeritShareCard({
    super.key,
    required this.title,
    required this.text,
    required this.taps,
  });

  final String title;
  final String text;
  final int taps;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('玄遇·敲木鱼', style: TextStyle(color: MeritColors.gold, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: MeritColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('「$text」', style: const TextStyle(color: MeritColors.textSecondary, fontSize: 13, height: 1.5)),
          const SizedBox(height: 12),
          Text('本世敲击 $taps 次', style: const TextStyle(color: MeritColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(4),
                child: QrImageView(
                  data: AppConstants.appDownloadUrl,
                  size: 48,
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
