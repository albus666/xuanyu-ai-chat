import 'package:flutter/material.dart';
import 'package:xuanyu/app/pages/voice/voice_match/view.dart' as app_voice;

/// 兼容旧入口：统一跳转到新壳语音匹配页（与 flutter_project 对齐样式）。
class VoiceMatchPage extends StatelessWidget {
  const VoiceMatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const app_voice.VoiceMatchPage();
  }
}
