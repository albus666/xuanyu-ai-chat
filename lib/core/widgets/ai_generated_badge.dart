import 'package:flutter/material.dart';

/// 显示在模型生成结果附近，供用户在浏览、截图和分享时识别内容来源。
class AiGeneratedBadge extends StatelessWidget {
  const AiGeneratedBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AI生成内容，仅供参考',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8FF),
          border: Border.all(color: const Color(0xFF9BCBEE)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'AI生成内容 · 仅供参考',
          style: TextStyle(
            color: const Color(0xFF176792),
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
