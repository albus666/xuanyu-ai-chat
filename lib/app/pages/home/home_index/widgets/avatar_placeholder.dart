import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/style/colors.dart';

/// 头像占位（缺失资源）
class AvatarPlaceholder extends StatelessWidget {
  final String text;
  final double size;
  final List<Color>? colors;

  const AvatarPlaceholder({
    super.key,
    required this.text,
    this.size = 32,
    this.colors,
  });

  static const List<List<Color>> _palettes = [
    [Color(0xFFA0E6E0), Color(0xFF6BC9D6)],
    [Color(0xFFFFCAB1), Color(0xFFFF9A8B)],
    [Color(0xFFB7E1FA), Color(0xFF7BB7E5)],
    [Color(0xFFD8C4F0), Color(0xFFA388C9)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette =
        colors ?? _palettes[text.hashCode.abs() % _palettes.length];
    return Container(
      width: size.r,
      height: size.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        text.isNotEmpty ? text.characters.first : '?',
        style: TextStyle(
          fontSize: (size * 0.4).sp,
          fontWeight: FontWeight.w600,
          color: AppColors.white,
        ),
      ),
    );
  }
}
