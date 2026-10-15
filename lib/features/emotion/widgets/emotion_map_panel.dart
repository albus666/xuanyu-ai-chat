import 'package:flutter/material.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';
import 'package:xuanyu/features/emotion/models/identity_type.dart';
import 'package:xuanyu/features/emotion/widgets/china_emotion_map_widget.dart';

/// 全国情绪地图面板
class EmotionMapPanel extends StatefulWidget {
  const EmotionMapPanel({
    super.key,
    required this.provinceDominant,
    required this.totalCheckIns,
    this.filterIdentity,
    this.onFilterChanged,
  });

  final Map<String, EmotionType> provinceDominant;
  final int totalCheckIns;
  final IdentityType? filterIdentity;
  final ValueChanged<IdentityType?>? onFilterChanged;

  @override
  State<EmotionMapPanel> createState() => _EmotionMapPanelState();
}

class _EmotionMapPanelState extends State<EmotionMapPanel> {
  String? _tappedProvince;
  EmotionType? _tappedEmotion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '全国情绪地图',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '共 ${widget.totalCheckIns} 人打卡',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '矢量中国地图 · 各省情绪一目了然',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _FilterChip(
                label: '全部',
                selected: widget.filterIdentity == null,
                onTap: () => widget.onFilterChanged?.call(null),
              ),
              ...IdentityType.values.map(
                (id) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _FilterChip(
                    label: '${id.emoji} ${id.label}',
                    selected: widget.filterIdentity == id,
                    color: id.color,
                    onTap: () => widget.onFilterChanged?.call(id),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ChinaEmotionMapWidget(
          provinceEmotions: widget.provinceDominant,
          onProvinceTap: (province, emotion) {
            setState(() {
              _tappedProvince = province;
              _tappedEmotion = emotion;
            });
          },
        ),
        if (_tappedProvince != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (_tappedEmotion?.color ?? Colors.blueGrey)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_tappedEmotion?.color ?? Colors.blueGrey)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _tappedEmotion == null
                  ? '$_tappedProvince · 暂无公开情绪'
                  : '$_tappedProvince · ${_tappedEmotion!.emoji} ${_tappedEmotion!.label}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _EmotionLegend(),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1AC4C4);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.2) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? c : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _EmotionLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: EmotionType.values.map((e) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('${e.emoji} ${e.label}', style: const TextStyle(fontSize: 10)),
          ],
        );
      }).toList(),
    );
  }
}
