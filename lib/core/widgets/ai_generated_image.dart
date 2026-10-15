import 'package:flutter/material.dart';

import '../utils/ai_generated_mark.dart';

/// 在 AI 生成图片右下角叠显式水印「AI生成内容」。
class AiGeneratedImage extends StatelessWidget {
  const AiGeneratedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        children: [
          Image.network(
            imageUrl,
            width: width ?? double.infinity,
            height: height,
            fit: fit,
            loadingBuilder: (_, child, loading) => loading == null
                ? child
                : const SizedBox(
                    height: 120,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          const Positioned(
            right: 8,
            bottom: 8,
            child: AiGeneratedImageWatermark(),
          ),
        ],
      ),
    );
  }
}

class AiGeneratedImageWatermark extends StatelessWidget {
  const AiGeneratedImageWatermark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC111111),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 3 : 4,
        ),
        child: Text(
          AiGeneratedMark.imageWatermark,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
