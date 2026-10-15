/// Tab4：基础分析（日干论命、月日时命理）
library;
import 'package:flutter/material.dart';
import 'utils/bazi_result.dart';
import 'share/paipan_smart_analysis_data_service.dart';
import 'share/paipan_shared.dart';

class PaipanSmartAnalysisTab extends StatelessWidget {
  final BaziResult result;
  final bool isFemale;

  const PaipanSmartAnalysisTab({
    super.key,
    required this.result,
    required this.isFemale,
  });

  static const _dayOrder = [
    '日干心性', '日干层次', '日干支分析', '性格分析',
    '爱情分析', '事业分析', '财运分析', '健康分析',
  ];
  static const _monthOrder = ['月', '日', '时'];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SmartAnalysisResult>(
      future: loadSmartAnalysisFromData(result, isFemale: isFemale),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: paipanPurple),
                  SizedBox(height: 16),
                  Text('加载基础分析…', style: TextStyle(fontSize: 14, color: paipanGrey)),
                ],
              ),
            ),
          );
        }
        final d = snapshot.data;
        if (d == null) {
          return Container(
            color: Colors.white,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                paipanFlatSection('基础分析', [
                  const Text('加载失败，请稍后重试。', style: TextStyle(fontSize: 14, color: paipanGrey)),
                ]),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: PaipanDisclaimer()),
              ],
            ),
          );
        }
        return Container(
          color: Colors.white,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              paipanFlatSection('日干论命', [
                for (final key in _dayOrder)
                  if (d.dayGanSection[key] != null && d.dayGanSection[key]!.isNotEmpty) ...[
                    Text(key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(d.dayGanSection[key]!, style: const TextStyle(fontSize: 14, height: 1.6)),
                    const SizedBox(height: 12),
                  ],
              ]),
              paipanFlatSection('月日时命理', [
                for (final key in _monthOrder)
                  if (d.monthDayHourSection[key] != null && d.monthDayHourSection[key]!.isNotEmpty) ...[
                    Text(key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(d.monthDayHourSection[key]!, style: const TextStyle(fontSize: 14, height: 1.6)),
                    const SizedBox(height: 12),
                  ],
              ]),
              const SizedBox(height: 24),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: PaipanDisclaimer()),
            ],
          ),
        );
      },
    );
  }
}
