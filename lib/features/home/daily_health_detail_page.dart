import 'package:flutter/material.dart';

import '../../core/widgets/app_gpt_markdown.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 今日养生详情页：根据中医体质 + 24 节气 + 当地天气推荐当日饮食（Markdown 渲染）
class DailyHealthDetailPage extends StatelessWidget {
  const DailyHealthDetailPage({
    super.key,
    required this.content,
    this.date,
    this.constitution,
    this.solarTerm,
    this.weather,
  });

  final String content;
  final String? date;
  final String? constitution;
  final String? solarTerm;
  final Map<String, dynamic>? weather;

  static const Color _textColor = Colors.white;
  static const Color _textColorDim = Color(0xFFE8F5E9);

  String? get _weatherSummary {
    if (weather == null) return null;
    final w = weather!;
    final parts = <String>[];
    if (w['weather'] != null && w['weather'].toString().isNotEmpty)
      parts.add(w['weather'].toString());
    if (w['temperature'] != null) parts.add('${w['temperature']}℃');
    if (w['wind_direction'] != null &&
        w['wind_direction'].toString().isNotEmpty) {
      parts.add(
        (w['wind_direction'] ?? '').toString() +
            (w['wind_power'] ?? '').toString(),
      );
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cleanContent = _stripCodeFence(content);
    final weatherSummary = _weatherSummary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text('今日养生', style: AppTextStyles.titleMedium),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '本内容含AI生成信息，仅供参考',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF059669).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '今日养生',
                        style: TextStyle(
                          color: _textColor.withOpacity(0.95),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const Icon(
                        Icons.eco_rounded,
                        color: _textColor,
                        size: 24,
                      ),
                    ],
                  ),
                  if (date != null && date!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      date!,
                      style: const TextStyle(
                        color: _textColorDim,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if ((constitution != null && constitution!.isNotEmpty) ||
                      (solarTerm != null && solarTerm!.isNotEmpty) ||
                      (weatherSummary != null &&
                          weatherSummary.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (constitution != null && constitution!.isNotEmpty)
                          _buildChip('体质：$constitution'),
                        if (solarTerm != null && solarTerm!.isNotEmpty)
                          _buildChip('节气：$solarTerm'),
                        if (weatherSummary != null && weatherSummary.isNotEmpty)
                          _buildChip('天气：$weatherSummary'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  AppGptMarkdown(
                    data: cleanContent,
                    bodyStyle: AppTextStyles.bodyMedium.copyWith(
                      color: _textColor,
                      height: 1.6,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 去掉 AI 返回内容外的 ```markdown ... ``` 或 ``` ... ``` 包裹
  static String _stripCodeFence(String raw) {
    if (raw.isEmpty) return raw;
    String s = raw.trim();
    if (s.startsWith('```')) {
      final firstLineEnd = s.indexOf('\n');
      if (firstLineEnd != -1) {
        s = s.substring(firstLineEnd + 1);
      } else {
        s = s.replaceFirst(RegExp(r'^```\w*\s*'), '');
      }
    }
    if (s.trimRight().endsWith('```')) {
      s = s.trimRight();
      final lastFence = s.lastIndexOf('```');
      if (lastFence != -1) s = s.substring(0, lastFence).trimRight();
    }
    return s.trim();
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _textColor.withOpacity(0.95),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
