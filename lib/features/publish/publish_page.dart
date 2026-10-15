import 'package:flutter/material.dart';
import '../../core/theme/app_text_styles.dart';

/// 发布：中央按钮弹出菜单 - 发布动态、快速排盘
class PublishPage extends StatelessWidget {
  const PublishPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布')),
      body: Center(
        child: Text('发布动态 · 快速排盘', style: AppTextStyles.bodyLarge),
      ),
    );
  }
}
