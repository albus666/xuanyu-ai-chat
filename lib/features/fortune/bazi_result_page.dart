import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 八字排盘结果页
class BaziResultPage extends StatelessWidget {
  const BaziResultPage({super.key, required this.result});

  final Map<String, dynamic> result;

  static String _str(dynamic v) {
    if (v == null) return '-';
    if (v is List) return v.join(' ');
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pillar = result['pillar'] as Map<String, dynamic>? ?? {};
    final shishen = result['shishen'] as Map<String, dynamic>? ?? {};
    final shensha = result['shensha'];
    final xiyongshen = result['xiyongshen'] as Map<String, dynamic>? ?? {};
    final birthDate = result['birthDate'] as String? ?? '';
    final birthTime = result['birthTime'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('排盘结果')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('出生信息', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 4),
                  Text('$birthDate ${birthTime.isNotEmpty ? birthTime : ""}', style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('四柱', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 12),
                  _row(
                    '年', _str(pillar['year']),
                    '月', _str(pillar['month']),
                    '日', _str(pillar['day']),
                    '时', _str(pillar['hour']),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('十神', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '年 ${shishen['year']} · 月 ${shishen['month']} · 日 ${shishen['day']} · 时 ${shishen['hour']}',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          if (shensha != null && (shensha is List && (shensha).isNotEmpty || shensha is String)) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('神煞', style: AppTextStyles.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                      shensha is List ? (shensha).join(' · ') : shensha.toString(),
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (xiyongshen.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('喜用神', style: AppTextStyles.titleSmall),
                    const SizedBox(height: 8),
                    ...xiyongshen.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${e.key} ${e.value}', style: AppTextStyles.bodyMedium),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String l1, String v1, String l2, String v2, [String? l3, String? v3, String? l4, String? v4]) {
    return Row(
      children: [
        _cell(l1, v1),
        if (l2.isNotEmpty) _cell(l2, v2),
        if (l3 != null && l3.isNotEmpty) _cell(l3, v3 ?? '-'),
        if (l4 != null && l4.isNotEmpty) _cell(l4, v4 ?? '-'),
      ],
    );
  }

  Widget _cell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }
}
