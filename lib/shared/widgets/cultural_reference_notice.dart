import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Shared footer for traditional-culture and entertainment features.
class CulturalReferenceNotice extends StatelessWidget {
  const CulturalReferenceNotice({
    super.key,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  });

  static const text = '本平台提供的内容仅供娱乐参考，请理性看待，不构成现实意义！';

  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: Text(
          text,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: color ?? AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
