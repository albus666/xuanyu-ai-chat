import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'ai_master_chat_page.dart';

class AiSquarePage extends StatelessWidget {
  const AiSquarePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('AI广场', style: AppTextStyles.titleMedium),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '选择你想聊的 AI',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _buildCard(
              context,
              title: 'AI 名师',
              subtitle: '传统文化答疑，温和交流',
              icon: Icons.smart_toy_rounded,
              colors: const [Color(0xFFD97706), Color(0xFFF59E0B)],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiMasterChatPage()),
              ),
            ),
            const SizedBox(height: 14),
            _buildCard(
              context,
              title: '骂醒恋爱脑',
              subtitle: '清醒狠话 + 可执行建议',
              icon: Icons.psychology_alt_rounded,
              colors: const [Color(0xFFDC2626), Color(0xFFEF4444)],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AiMasterChatPage(
                    title: '骂醒恋爱脑',
                    scene: 'love_wake',
                    enableArchive: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: colors[0].withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withOpacity(0.9))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.9), size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
