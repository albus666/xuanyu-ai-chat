import 'package:flutter/material.dart';

/// 当下情绪：用于情绪地图打卡及历史命灵互动。
enum EmotionType {
  happy('开心', '😊', Color(0xFFFFD166)),
  tired('疲惫', '😮‍💨', Color(0xFF9CA3AF)),
  angry('暴躁', '😤', Color(0xFFFF6B6B)),
  zen('平静', '🧘', Color(0xFF7DD7D0)),
  anxious('焦虑', '😰', Color(0xFF8DA4F1)),
  slacking('放空', '🫠', Color(0xFFFFB572)),
  excited('兴奋', '🔥', Color(0xFFFF8A4C)),
  emo('低落', '🌧️', Color(0xFFC79DEF));

  const EmotionType(this.label, this.emoji, this.color);
  final String label;
  final String emoji;
  final Color color;

  /// 喂养宠物时增加的健康值
  int get feedBoost => switch (this) {
        EmotionType.happy => 12,
        EmotionType.zen => 10,
        EmotionType.excited => 8,
        EmotionType.tired => 6,
        EmotionType.slacking => 5,
        EmotionType.anxious => 4,
        EmotionType.angry => 3,
        EmotionType.emo => 2,
      };
}
