import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'astrology_models.dart';

class AstrologyChartWheel extends StatelessWidget {
  const AstrologyChartWheel({super.key, required this.chart});

  final AstrologyChartData chart;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: _chartSemantics(chart),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _AstrologyWheelPainter(
            chart,
            Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
        ),
      ),
    );
  }
}

String _chartSemantics(AstrologyChartData chart) {
  final positions = chart.planets.map((planet) {
    final house = planet.house == null ? '' : '，第${planet.house}宫';
    final retrograde = planet.retrograde ? '，逆行' : '';
    return '${planet.name}${planet.sign}${planet.degreeText}$house$retrograde';
  }).join('；');
  return '${chart.chartTitle}。$positions；'
      '上升${chart.ascendant.sign}${chart.ascendant.degreeText}；'
      '天顶${chart.midheaven.sign}${chart.midheaven.degreeText}';
}

class _AstrologyWheelPainter extends CustomPainter {
  _AstrologyWheelPainter(this.chart, this.fontFamily);

  final AstrologyChartData chart;
  final String? fontFamily;

  static const _signNames = <String>[
    '白羊',
    '金牛',
    '双子',
    '巨蟹',
    '狮子',
    '处女',
    '天秤',
    '天蝎',
    '射手',
    '摩羯',
    '水瓶',
    '双鱼',
  ];

  static const _signColors = <Color>[
    Color(0xFFC45E68),
    Color(0xFFA47A45),
    Color(0xFF278E89),
    Color(0xFF4F71B0),
    Color(0xFFC45E68),
    Color(0xFFA47A45),
    Color(0xFF278E89),
    Color(0xFF4F71B0),
    Color(0xFFC45E68),
    Color(0xFFA47A45),
    Color(0xFF278E89),
    Color(0xFF4F71B0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final showFirdaria = chart.chartType == AstrologyChartType.firdaria &&
        chart.firdaria.isNotEmpty;
    final wheelRadius = showFirdaria ? radius * .76 : radius;

    if (showFirdaria) {
      _drawFirdariaRings(canvas, center, radius);
    }
    _drawNatalWheel(canvas, center, wheelRadius);
  }

  void _drawNatalWheel(Canvas canvas, Offset center, double radius) {
    final asc = chart.ascendant.longitude;
    const lineColor = Color(0xFFAAB4C4);
    const textColor = Color(0xFF17233D);
    const accent = Color(0xFF16AAA7);
    const comparisonColor = Color(0xFF756FC0);
    final hasComparison = chart.hasComparison;

    canvas.drawCircle(center, radius, Paint()..color = Colors.white);

    for (var index = 0; index < 12; index++) {
      final sector = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          _angle(index * 30, asc),
          -math.pi / 6,
          false,
        )
        ..close();
      canvas.drawPath(
        sector,
        Paint()
          ..color =
              index.isEven ? const Color(0xFFF5F8FA) : const Color(0xFFFCFDFE),
      );
    }
    canvas.drawCircle(center, radius * .80, Paint()..color = Colors.white);

    final ringPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (final fraction in <double>[1, .91, .80, .66, .43]) {
      canvas.drawCircle(
        center,
        radius * fraction,
        fraction == 1
            ? (Paint()
              ..color = textColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.05)
            : ringPaint,
      );
    }

    for (var degree = 0; degree < 360; degree++) {
      final angle = _angle(degree.toDouble(), asc);
      final inner = degree % 10 == 0
          ? .865
          : degree % 5 == 0
              ? .878
              : .891;
      canvas.drawLine(
        _point(center, radius * inner, angle),
        _point(center, radius * .91, angle),
        ringPaint,
      );
    }

    for (var i = 0; i < 12; i++) {
      final longitude = i * 30.0;
      final angle = _angle(longitude, asc);
      final outer = _point(center, radius, angle);
      final inner = _point(center, radius * .80, angle);
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = textColor
          ..strokeWidth = .9,
      );
      _text(
        canvas,
        _signNames[i],
        _point(center, radius * .955, _angle(longitude + 15, asc)),
        8.8,
        _signColors[i],
        FontWeight.w700,
      );
    }

    for (var index = 0; index < chart.houses.length; index++) {
      final cusp = chart.houses[index];
      final angle = _angle(cusp.longitude, asc);
      final house = cusp.house ?? index + 1;
      final strong = house == 1 || house == 4 || house == 7 || house == 10;
      final paint = Paint()
        ..color = house == 1 ? accent : (strong ? textColor : lineColor)
        ..strokeWidth = house == 1 ? 1.5 : (strong ? 1.05 : .65);
      canvas.drawLine(
        _point(center, radius * .18, angle),
        _point(center, radius * .80, angle),
        paint,
      );
      final next = chart.houses[(index + 1) % chart.houses.length].longitude;
      final span = (next - cusp.longitude + 360) % 360;
      _text(
        canvas,
        '$house宫',
        _point(
          center,
          radius * .745,
          _angle(cusp.longitude + span / 2, asc),
        ),
        7.2,
        const Color(0xFF697386),
        FontWeight.w500,
      );
    }

    _drawAxis(
      canvas,
      center,
      radius,
      asc,
      chart.ascendant.longitude,
      '上升',
      accent,
    );
    _drawAxis(
      canvas,
      center,
      radius,
      asc,
      chart.ascendant.longitude + 180,
      '下降',
      accent.withValues(alpha: .82),
    );
    _drawAxis(
      canvas,
      center,
      radius,
      asc,
      chart.midheaven.longitude,
      '天顶',
      comparisonColor,
    );
    _drawAxis(
      canvas,
      center,
      radius,
      asc,
      chart.midheaven.longitude + 180,
      '天底',
      comparisonColor.withValues(alpha: .82),
    );

    if (hasComparison) {
      final natalPoints = _aspectPoints(
        chart.comparisonPlanets,
        center,
        radius * .34,
        asc,
      );
      final activePoints = _aspectPoints(
        chart.planets,
        center,
        radius * .54,
        asc,
      );
      for (final aspect in chart.crossAspects) {
        final from = natalPoints[aspect.body1];
        final to = activePoints[aspect.body2];
        if (from == null || to == null) continue;
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = _aspectColor(aspect).withValues(alpha: .34)
            ..strokeWidth = .72,
        );
      }
      _drawPlanetLayer(
        canvas,
        center,
        radius,
        asc,
        chart.comparisonPlanets,
        glyphRadius: .45,
        degreeRadius: .385,
        tickRadius: .34,
        color: comparisonColor,
        minimumGap: 12,
      );
      _drawPlanetLayer(
        canvas,
        center,
        radius,
        asc,
        chart.planets,
        glyphRadius: .65,
        degreeRadius: .585,
        tickRadius: .54,
        color: const Color(0xFF159F9C),
        minimumGap: 12,
      );
    } else {
      final positions = _aspectPoints(
        chart.planets,
        center,
        radius * .40,
        asc,
      );
      for (final aspect in chart.aspects) {
        final from = positions[aspect.body1];
        final to = positions[aspect.body2];
        if (from == null || to == null) continue;
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = _aspectColor(aspect).withValues(alpha: .40)
            ..strokeWidth = .78,
        );
      }
      _drawPlanetLayer(
        canvas,
        center,
        radius,
        asc,
        chart.planets,
        glyphRadius: .60,
        degreeRadius: .525,
        tickRadius: .46,
        color: textColor,
        minimumGap: 13,
      );
    }

    if (hasComparison) {
      _text(
        canvas,
        '${chart.comparisonLabel}内圈\n${chart.activeLabel}外圈',
        center,
        8.2,
        textColor,
        FontWeight.w600,
        maxWidth: radius * .34,
      );
    } else {
      canvas.drawCircle(center, 2.6, Paint()..color = accent);
    }
  }

  Map<String, Offset> _aspectPoints(
    List<AstrologyPosition> planets,
    Offset center,
    double radius,
    double asc,
  ) =>
      {
        for (final planet in planets)
          planet.key: _point(center, radius, _angle(planet.longitude, asc)),
      };

  Color _aspectColor(AstrologyAspect aspect) => switch (aspect.type) {
        'Trine' || 'Sextile' => const Color(0xFF467CC7),
        'Conjunction' => const Color(0xFF16AAA7),
        _ => const Color(0xFFD86870),
      };

  void _drawAxis(
    Canvas canvas,
    Offset center,
    double radius,
    double asc,
    double longitude,
    String label,
    Color color,
  ) {
    final angle = _angle(longitude, asc);
    canvas.drawLine(
      _point(center, radius * .18, angle),
      _point(center, radius * .80, angle),
      Paint()
        ..color = color.withValues(alpha: .72)
        ..strokeWidth = 1.35,
    );
    _text(
      canvas,
      label,
      _point(center, radius * .84, angle),
      7,
      color,
      FontWeight.w800,
    );
  }

  void _drawPlanetLayer(
    Canvas canvas,
    Offset center,
    double radius,
    double asc,
    List<AstrologyPosition> planets, {
    required double glyphRadius,
    required double degreeRadius,
    required double tickRadius,
    required Color color,
    required double minimumGap,
  }) {
    final displayed = _spreadLongitudes(planets, minimumGap);
    final layout = planets.map((planet) {
      final actualAngle = _angle(planet.longitude, asc);
      final displayAngle = _angle(displayed[planet.key]!, asc);
      return (
        planet: planet,
        actual: _point(center, radius * tickRadius, actualAngle),
        degreeAnchor: _point(center, radius * degreeRadius, displayAngle),
        glyphAnchor: _point(center, radius * glyphRadius, displayAngle),
      );
    }).toList();

    // 所有真实落点和引线先画，避免后画的点压住已经绘制的星体文字。
    for (final item in layout) {
      canvas.drawCircle(
        item.actual,
        2.2,
        Paint()..color = color.withValues(alpha: .95),
      );
      canvas.drawLine(
        item.actual,
        item.degreeAnchor,
        Paint()
          ..color = color.withValues(alpha: .48)
          ..strokeWidth = .65,
      );
    }

    // 文字最后统一绘制，并使用白色描边隔离其下方的点和线。
    for (final item in layout) {
      final planet = item.planet;
      _text(
        canvas,
        _planetShortName(planet),
        item.glyphAnchor,
        12.5,
        planet.retrograde ? const Color(0xFFE07882) : color,
        FontWeight.w700,
        haloColor: Colors.white,
        haloWidth: 2.6,
      );
      _text(
        canvas,
        '${planet.degreeText}${planet.retrograde ? '逆' : ''}',
        item.degreeAnchor,
        6,
        planet.retrograde
            ? const Color(0xFFE07882)
            : color.withValues(alpha: .90),
        FontWeight.w600,
        haloColor: Colors.white,
        haloWidth: 1.8,
      );
    }
  }

  Map<String, double> _spreadLongitudes(
    List<AstrologyPosition> planets,
    double minimumGap,
  ) {
    if (planets.isEmpty) return const {};
    if (planets.length == 1) {
      return {planets.first.key: planets.first.longitude};
    }
    final sorted = [...planets]
      ..sort((a, b) => a.longitude.compareTo(b.longitude));
    var largestGap = -1.0;
    var startIndex = 0;
    for (var index = 0; index < sorted.length; index++) {
      final next = sorted[(index + 1) % sorted.length].longitude +
          (index == sorted.length - 1 ? 360 : 0);
      final gap = next - sorted[index].longitude;
      if (gap > largestGap) {
        largestGap = gap;
        startIndex = (index + 1) % sorted.length;
      }
    }
    final ordered = <AstrologyPosition>[];
    final originals = <double>[];
    for (var offset = 0; offset < sorted.length; offset++) {
      final index = (startIndex + offset) % sorted.length;
      ordered.add(sorted[index]);
      originals.add(
        sorted[index].longitude + (index < startIndex ? 360 : 0),
      );
    }
    final adjusted = <double>[originals.first];
    for (var index = 1; index < originals.length; index++) {
      adjusted.add(math.max(originals[index], adjusted.last + minimumGap));
    }
    return {
      for (var index = 0; index < ordered.length; index++)
        ordered[index].key: adjusted[index] % 360,
    };
  }

  void _drawFirdariaRings(Canvas canvas, Offset center, double radius) {
    final periods = chart.firdaria
        .where((item) => item.startDate != null && item.endDate != null)
        .toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
    if (periods.isEmpty) return;

    final start = periods.first.startDate!;
    final end = periods
        .map((item) => item.endDate!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final span = end.difference(start).inMilliseconds;
    if (span <= 0) return;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFE7EEF3)],
          stops: [.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    final major = periods.where((item) => item.level == 1).toList();
    final minor = periods.where((item) => item.level != 1).toList();
    _drawPeriodBand(
      canvas,
      center,
      radius * .90,
      radius,
      major,
      start,
      span,
      activeColor: const Color(0xFF159F9C),
      baseColors: const [Color(0xFFDCE9EC), Color(0xFFE7EFF3)],
      fontSize: 9,
    );
    _drawPeriodBand(
      canvas,
      center,
      radius * .81,
      radius * .90,
      minor,
      start,
      span,
      activeColor: const Color(0xFF756FC0),
      baseColors: const [Color(0xFFEDEAF7), Color(0xFFE6F1F1)],
      fontSize: 8,
    );

    final linePaint = Paint()
      ..color = const Color(0xFFA9B7C5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (final fraction in <double>[.76, .81, .90, 1]) {
      canvas.drawCircle(center, radius * fraction, linePaint);
    }

    for (final period in major) {
      final periodStart = period.startDate!;
      final ratio =
          periodStart.difference(start).inMilliseconds / span.toDouble();
      final angle = -math.pi + ratio * math.pi * 2;
      final age = periodStart.difference(start).inDays / 365.2425;
      _text(
        canvas,
        '${age.floor()}岁',
        _point(center, radius * .785, angle + .025),
        7.5,
        const Color(0xFF526176),
        FontWeight.w600,
      );
    }
  }

  void _drawPeriodBand(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
    List<AstrologyTimePeriod> periods,
    DateTime timelineStart,
    int timelineSpan, {
    required Color activeColor,
    required List<Color> baseColors,
    required double fontSize,
  }) {
    for (var index = 0; index < periods.length; index++) {
      final period = periods[index];
      final startRatio =
          period.startDate!.difference(timelineStart).inMilliseconds /
              timelineSpan;
      final endRatio =
          period.endDate!.difference(timelineStart).inMilliseconds /
              timelineSpan;
      final startAngle = -math.pi + startRatio * math.pi * 2;
      final sweep =
          math.max(.001, (endRatio - startRatio) * math.pi * 2).toDouble();
      final path = Path()
        ..arcTo(
          Rect.fromCircle(center: center, radius: outerRadius),
          startAngle,
          sweep,
          false,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: innerRadius),
          startAngle + sweep,
          -sweep,
          false,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = period.active
              ? activeColor
              : baseColors[index % baseColors.length],
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFAAB7C5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );

      if (sweep >= .055) {
        _text(
          canvas,
          _periodShortName(period),
          _point(
            center,
            (innerRadius + outerRadius) / 2,
            startAngle + sweep / 2,
          ),
          fontSize,
          period.active ? Colors.white : const Color(0xFF33445C),
          period.active ? FontWeight.w800 : FontWeight.w600,
        );
      }
    }
  }

  String _periodShortName(AstrologyTimePeriod period) {
    const names = <String, String>{
      '太阳': '日',
      '月亮': '月',
      '水星': '水',
      '金星': '金',
      '火星': '火',
      '木星': '木',
      '土星': '土',
      '北交点': '北',
      '南交点': '南',
    };
    return names[period.planetName] ??
        (period.planetName.isEmpty ? '星' : period.planetName.substring(0, 1));
  }

  String _planetShortName(AstrologyPosition planet) {
    const names = <String, String>{
      'Sun': '日',
      'Moon': '月',
      'Mercury': '水',
      'Venus': '金',
      'Mars': '火',
      'Jupiter': '木',
      'Saturn': '土',
      'Uranus': '天',
      'Neptune': '海',
      'Pluto': '冥',
    };
    return names[planet.key] ??
        (planet.name.length <= 2 ? planet.name : planet.name.substring(0, 1));
  }

  double _angle(double longitude, double asc) =>
      math.pi - ((longitude - asc) * math.pi / 180);

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
    Color? haloColor,
    double haloWidth = 0,
  }) {
    TextPainter painterFor(TextStyle style) => TextPainter(
          text: TextSpan(text: value, style: style),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth ?? double.infinity);

    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: 1.35,
      color: color,
      fontWeight: weight,
    );
    final painter = painterFor(baseStyle);
    final offset = Offset(
      center.dx - painter.width / 2,
      center.dy - painter.height / 2,
    );
    if (haloColor != null && haloWidth > 0) {
      final haloPainter = painterFor(
        baseStyle.copyWith(
          color: null,
          foreground: Paint()
            ..color = haloColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = haloWidth
            ..strokeJoin = StrokeJoin.round,
        ),
      );
      haloPainter.paint(
        canvas,
        Offset(
          center.dx - haloPainter.width / 2,
          center.dy - haloPainter.height / 2,
        ),
      );
    }
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AstrologyWheelPainter oldDelegate) =>
      oldDelegate.chart != chart || oldDelegate.fontFamily != fontFamily;
}
