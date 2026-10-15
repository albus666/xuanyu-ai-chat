import 'package:flutter/material.dart';

/// 社区头像统一在线态：在线时仅在头像右下角显示绿色圆点。
class CommunityOnlineIndicator extends StatelessWidget {
  const CommunityOnlineIndicator({
    super.key,
    required this.online,
    required this.child,
    this.dotSize = 11,
    this.borderColor = Colors.white,
  });

  final bool online;
  final Widget child;
  final double dotSize;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    if (!online) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            key: const ValueKey('community-online-dot'),
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: const Color(0xFF35C96F),
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
