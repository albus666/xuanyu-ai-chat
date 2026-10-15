import 'package:flutter/material.dart';
import 'package:xuanyu/app/pages/home/destiny_match/view.dart' as app_destiny;

/// 兼容旧入口：统一跳转到新壳缘分匹配页（与 flutter_project 对齐样式）。
class FateMatchPage extends StatelessWidget {
  const FateMatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const app_destiny.DestinyMatchPage();
  }
}
