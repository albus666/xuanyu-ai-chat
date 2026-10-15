import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'qizheng_models.dart';

@visibleForTesting
Map<String, double> spreadQizhengBodyLabelLongitudes(
  Map<String, double> longitudes, {
  required double minimumGap,
}) {
  if (longitudes.isEmpty) return const {};
  if (longitudes.length == 1) {
    final entry = longitudes.entries.single;
    return {entry.key: entry.value % 360};
  }
  final sorted = longitudes.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  var largestGap = -1.0;
  var startIndex = 0;
  for (var index = 0; index < sorted.length; index++) {
    final next = sorted[(index + 1) % sorted.length].value +
        (index == sorted.length - 1 ? 360 : 0);
    final gap = next - sorted[index].value;
    if (gap > largestGap) {
      largestGap = gap;
      startIndex = (index + 1) % sorted.length;
    }
  }

  final ordered = <MapEntry<String, double>>[];
  for (var offset = 0; offset < sorted.length; offset++) {
    final index = (startIndex + offset) % sorted.length;
    final entry = sorted[index];
    ordered.add(MapEntry(
      entry.key,
      entry.value + (index < startIndex ? 360 : 0),
    ));
  }
  final adjusted = <double>[ordered.first.value];
  for (var index = 1; index < ordered.length; index++) {
    adjusted.add(math.max(ordered[index].value, adjusted.last + minimumGap));
  }
  return {
    for (var index = 0; index < ordered.length; index++)
      ordered[index].key: adjusted[index] % 360,
  };
}

/// 七政四余专用盘面：外圈为动态距星二十八宿，中圈为十二宫与宫职，
/// 内圈显示七政四余及传统宫位关系。这里不使用西洋星盘的星座或相位结构。
class QizhengChartWheel extends StatelessWidget {
  const QizhengChartWheel({super.key, required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _QizhengWheelPainter(chart)),
    );
  }
}

class _QizhengWheelPainter extends CustomPainter {
  _QizhengWheelPainter(this.chart);

  final QizhengChartData chart;

  static const _violet = Color(0xFFB7A7FF);
  static const _jade = Color(0xFF58DDD4);
  static const _line = Color(0xFF55709D);
  static const _paper = Color(0xFFF2F5FF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final asc = chart.lifeDegree.longitude;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF263978), Color(0xFF142957), Color(0xFF091832)],
          stops: [0, .52, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    _drawStarField(canvas, center, radius);

    for (final band in <(double, Color)>[
      (.89, const Color(0xC9112249)),
      (.73, const Color(0xD9172D5E)),
      (.55, const Color(0xD90D1D3E)),
      (.31, const Color(0xEB172B57)),
    ]) {
      canvas.drawCircle(center, radius * band.$1, Paint()..color = band.$2);
    }

    final ring = Paint()
      ..color = _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (final fraction in <double>[1, .89, .73, .55, .31]) {
      canvas.drawCircle(center, radius * fraction, ring);
    }

    _drawMansions(canvas, center, radius, asc);
    _drawPalaces(canvas, center, radius, asc);
    _drawRelationships(canvas, center, radius, asc);
    _drawBodies(canvas, center, radius, asc);

    canvas.drawCircle(
      center,
      radius * .205,
      Paint()..color = const Color(0xF2152852),
    );
    canvas.drawCircle(
      center,
      radius * .205,
      Paint()
        ..color = _jade.withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .85,
    );

    _text(
      canvas,
      '命',
      _point(center, radius * .95, math.pi),
      9.5,
      _jade,
      FontWeight.w800,
    );
    _text(
      canvas,
      '命${chart.lifeDegree.palace.replaceAll('宫', '')}\n${chart.lifeDegree.mansion}宿 ${_degreeText(chart.lifeDegree.mansionDegree)}',
      center,
      7.6,
      _paper,
      FontWeight.w700,
      maxWidth: radius * .35,
    );
  }

  void _drawStarField(Canvas canvas, Offset center, double radius) {
    for (var index = 0; index < 46; index++) {
      final angle = index * 2.399963229728653;
      final distance = radius * (.12 + ((index * 37) % 82) / 100);
      final point = _point(center, distance, angle);
      final bright = index % 7 == 0;
      canvas.drawCircle(
        point,
        bright ? .85 : .42,
        Paint()
          ..color =
              (bright ? _jade : _paper).withValues(alpha: bright ? .48 : .25),
      );
    }
  }

  void _drawMansions(Canvas canvas, Offset center, double radius, double asc) {
    final boundaryPaint = Paint()
      ..color = const Color(0xFF526275)
      ..strokeWidth = .65;
    for (final mansion in chart.mansions) {
      final start = _angle(mansion.longitude, asc);
      canvas.drawLine(
        _point(center, radius * .89, start),
        _point(center, radius, start),
        boundaryPaint,
      );
      final middle = _angle(mansion.longitude + mansion.width / 2, asc);
      _text(
        canvas,
        mansion.name,
        _point(center, radius * .945, middle),
        mansion.width < 8 ? 6.2 : 7.4,
        _quadrantColor(mansion.quadrant),
        FontWeight.w700,
      );
    }
  }

  void _drawPalaces(Canvas canvas, Offset center, double radius, double asc) {
    for (final palace in chart.palaces) {
      final start = _angle(palace.startLongitude, asc);
      canvas.drawLine(
        _point(center, radius * .55, start),
        _point(center, radius * .89, start),
        Paint()
          ..color = palace.role == '命宫' || palace.role == '官禄宫'
              ? _jade.withValues(alpha: .85)
              : _line
          ..strokeWidth = palace.role == '命宫' ? 1.5 : .75,
      );
      final middle = _angle(palace.startLongitude + 15, asc);
      _text(
        canvas,
        '${palace.branch}${palace.element}',
        _point(center, radius * .81, middle),
        8.2,
        palace.role == '命宫' ? _jade : _violet,
        FontWeight.w700,
      );
      _text(
        canvas,
        palace.role.replaceAll('宫', ''),
        _point(center, radius * .64, middle),
        6.6,
        _paper.withValues(alpha: .7),
        FontWeight.w500,
      );
    }
  }

  void _drawRelationships(
    Canvas canvas,
    Offset center,
    double radius,
    double asc,
  ) {
    final byKey = <String, QizhengBodyPosition>{
      for (final body in chart.bodies) body.key: body,
    };
    for (final relation in chart.relationships.take(24)) {
      final first = byKey[relation.body1];
      final second = byKey[relation.body2];
      if (first == null || second == null) continue;
      final harmonious = relation.type == '拱' || relation.type == '辅';
      canvas.drawLine(
        _point(center, radius * .29, _angle(first.longitude, asc)),
        _point(center, radius * .29, _angle(second.longitude, asc)),
        Paint()
          ..color = (harmonious ? _jade : const Color(0xFFC8666D))
              .withValues(alpha: relation.type == '守' ? .3 : .42)
          ..strokeWidth = .75,
      );
    }
  }

  void _drawBodies(Canvas canvas, Offset center, double radius, double asc) {
    if (chart.bodies.isEmpty) return;
    final labelDistance = radius * .49;
    final markerDistance = math.max(radius * .32, labelDistance - 16);
    final minimumGap =
        (20 / labelDistance * 180 / math.pi).clamp(12.0, 20.0).toDouble();
    final displayed = spreadQizhengBodyLabelLongitudes(
      {for (final body in chart.bodies) body.key: body.longitude},
      minimumGap: minimumGap,
    );
    final layout = chart.bodies.map((body) {
      final actualAngle = _angle(body.longitude, asc);
      final labelAngle = _angle(displayed[body.key]!, asc);
      return (
        body: body,
        marker: _point(center, markerDistance, actualAngle),
        lineEnd: _point(center, labelDistance - 9, labelAngle),
        label: _point(center, labelDistance, labelAngle),
      );
    }).toList();

    // 真实经度点与引线先画；点固定在独立内圈，不再与文字共用半径。
    for (final item in layout) {
      final color = _color(item.body.colorHex);
      canvas.drawLine(
        item.marker,
        item.lineEnd,
        Paint()
          ..color = color.withValues(alpha: .52)
          ..strokeWidth = .7,
      );
      canvas.drawCircle(item.marker, 2.2, Paint()..color = color);
    }

    // 所有文字最后绘制，密集星曜沿文字圈展开并由引线对应真实落点。
    for (final item in layout) {
      final body = item.body;
      final color = _color(body.colorHex);
      _text(
        canvas,
        '${body.shortName}${body.retrograde ? '逆' : ''}',
        item.label,
        9.3,
        color,
        FontWeight.w800,
      );
    }
  }

  Color _quadrantColor(String value) {
    if (value.contains('青龙')) return const Color(0xFF4CC5A5);
    if (value.contains('玄武')) return const Color(0xFF7993D8);
    if (value.contains('白虎')) return const Color(0xFFC8B7FF);
    return const Color(0xFFFF929F);
  }

  Color _color(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.tryParse('FF$clean', radix: 16) ?? 0xFFB7A7FF);
  }

  String _degreeText(double value) {
    final totalMinutes = (value * 60).round();
    return '${totalMinutes ~/ 60}°${(totalMinutes % 60).toString().padLeft(2, '0')}′';
  }

  double _angle(double longitude, double asc) =>
      math.pi + (longitude - asc) * math.pi / 180;

  Offset _point(Offset center, double radius, double angle) => Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

  void _text(
    Canvas canvas,
    String value,
    Offset center,
    double size,
    Color color,
    FontWeight weight, {
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          height: 1.25,
          fontWeight: weight,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _QizhengWheelPainter oldDelegate) =>
      oldDelegate.chart != chart;
}
