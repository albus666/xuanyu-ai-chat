import 'package:flutter/material.dart';

/// 此刻正在做什么；保留历史 code，避免旧状态失效。
enum IdentityType {
  worker('还在工作', '💼', Color(0xFF5B8DEF)),
  entrepreneur('忙自己的事', '🚀', Color(0xFFFF8A4C)),
  examTaker('正在学习', '📚', Color(0xFF7DD7D0)),
  parent('正在带娃', '👶', Color(0xFFF7A0AE)),
  loveBrain('为感情难过', '💕', Color(0xFFC79DEF)),
  commuting('正在通勤', '🚇', Color(0xFF6D9EEB)),
  sleepless('睡不着', '🌙', Color(0xFF8D83C7)),
  alone('一个人待着', '🪟', Color(0xFF70A8A1)),
  resting('刚刚放松', '🍃', Color(0xFF6EBB8B));

  const IdentityType(this.label, this.emoji, this.color);
  final String label;
  final String emoji;
  final Color color;
}

/// 十二时辰
class ShiChen {
  const ShiChen(this.name, this.range, this.branch);
  final String name;
  final String range;
  final String branch;

  static const List<ShiChen> all = [
    ShiChen('子时', '23:00-01:00', '子'),
    ShiChen('丑时', '01:00-03:00', '丑'),
    ShiChen('寅时', '03:00-05:00', '寅'),
    ShiChen('卯时', '05:00-07:00', '卯'),
    ShiChen('辰时', '07:00-09:00', '辰'),
    ShiChen('巳时', '09:00-11:00', '巳'),
    ShiChen('午时', '11:00-13:00', '午'),
    ShiChen('未时', '13:00-15:00', '未'),
    ShiChen('申时', '15:00-17:00', '申'),
    ShiChen('酉时', '17:00-19:00', '酉'),
    ShiChen('戌时', '19:00-21:00', '戌'),
    ShiChen('亥时', '21:00-23:00', '亥'),
  ];

  static ShiChen fromHour(int hour) {
    final h = hour.clamp(0, 23);
    if (h >= 23 || h < 1) return all[0];
    if (h < 3) return all[1];
    if (h < 5) return all[2];
    if (h < 7) return all[3];
    if (h < 9) return all[4];
    if (h < 11) return all[5];
    if (h < 13) return all[6];
    if (h < 15) return all[7];
    if (h < 17) return all[8];
    if (h < 19) return all[9];
    if (h < 21) return all[10];
    return all[11];
  }
}
