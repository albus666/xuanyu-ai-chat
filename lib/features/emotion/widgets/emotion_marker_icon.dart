import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';

/// 把情绪气泡画成 PNG，供高德 Marker 使用。
class EmotionMarkerIcon {
  EmotionMarkerIcon._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static Future<BitmapDescriptor> get({
    required String emoji,
    required Color color,
    required int count,
    bool selected = false,
  }) async {
    final key = '$emoji|${color.r}|${color.g}|${color.b}|$count|$selected';
    final cached = _cache[key];
    if (cached != null) return cached;

    final bytes = await _paintPng(
      emoji: emoji,
      color: color,
      count: count,
      selected: selected,
    );
    final icon = BitmapDescriptor.fromBytes(bytes);
    _cache[key] = icon;
    return icon;
  }

  static Future<Uint8List> _paintPng({
    required String emoji,
    required Color color,
    required int count,
    required bool selected,
  }) async {
    const double logical = 96;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(logical / 2, logical / 2 + 4);
    final radius = selected ? 30.0 : 26.0;

    // 阴影
    canvas.drawCircle(
      center.translate(0, 2),
      radius + 2,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    // 白边
    canvas.drawCircle(center, radius + 3, Paint()..color = Colors.white);
    // 情绪色底
    canvas.drawCircle(center, radius, Paint()..color = color);

    final emojiTp = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: selected ? 28 : 24),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    emojiTp.paint(
      canvas,
      Offset(
        center.dx - emojiTp.width / 2,
        center.dy - emojiTp.height / 2 - 1,
      ),
    );

    if (count > 0) {
      final label = count > 99 ? '99+' : '$count';
      final countTp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final badgeCenter =
          Offset(center.dx + radius * 0.72, center.dy - radius * 0.72);
      final badgeR =
          (countTp.width > countTp.height ? countTp.width : countTp.height) /
                  2 +
              5;
      canvas.drawCircle(
          badgeCenter, badgeR + 1.5, Paint()..color = Colors.white);
      canvas.drawCircle(
          badgeCenter, badgeR, Paint()..color = const Color(0xFFEF4444));
      countTp.paint(
        canvas,
        Offset(
          badgeCenter.dx - countTp.width / 2,
          badgeCenter.dy - countTp.height / 2,
        ),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(logical.toInt(), logical.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
