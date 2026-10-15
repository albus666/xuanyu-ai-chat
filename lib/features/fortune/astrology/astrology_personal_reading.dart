import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'astrology_models.dart';

const _ink = Color(0xFF263332);
const _muted = Color(0xFF71807D);
const _jade = Color(0xFF2AAFA8);
const _deepJade = Color(0xFF18514D);
const _violet = Color(0xFF6F72B4);
const _line = Color(0xFFE4ECEA);

/// 星盘的个人信息页沿用八字/斗数的信息层级，星灵使用独立的星河灵兽视觉。
class AstrologyPersonalReading extends StatelessWidget {
  const AstrologyPersonalReading({super.key, required this.chart});

  final AstrologyChartData chart;

  @override
  Widget build(BuildContext context) {
    final sun = chart.position('Sun');
    final moon = chart.position('Moon');
    final mercury = chart.position('Mercury');
    final venus = chart.position('Venus');
    final mars = chart.position('Mars');
    final saturn = chart.position('Saturn');
    final asc = chart.ascendant;
    final spirit = _spiritFor(chart);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 34),
      children: [
        _StarSpiritHero(
          spirit: spirit,
          sun: sun,
          moon: moon,
          ascendant: asc,
        ),
        const SizedBox(height: 14),
        _PaperCard(
          title: '你的三重人格',
          subtitle: '同一个你，在不同情境里会启动不同频道',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CoreSignal(
                  icon: Icons.shield_outlined,
                  label: '外在模式',
                  value: _signCue(asc.sign, _CueKind.outer),
                  basis: '上升${asc.sign}',
                  color: _jade,
                ),
              ),
              const _VerticalRule(),
              Expanded(
                child: _CoreSignal(
                  icon: Icons.water_drop_outlined,
                  label: '情绪开关',
                  value: _signCue(moon.sign, _CueKind.emotion),
                  basis: '月亮${moon.sign}',
                  color: const Color(0xFFB46677),
                ),
              ),
              const _VerticalRule(),
              Expanded(
                child: _CoreSignal(
                  icon: Icons.auto_awesome_outlined,
                  label: '核心驱动',
                  value: _signCue(sun.sign, _CueKind.core),
                  basis: '太阳${sun.sign}',
                  color: _violet,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PaperCard(
          title: '关系与表达',
          subtitle: '怎么想、怎么爱、怎么行动，往往是三套程序',
          child: Column(
            children: [
              _InsightRow(
                icon: Icons.chat_bubble_outline_rounded,
                label: '表达习惯',
                value: _signCue(mercury.sign, _CueKind.expression),
                basis: '水星${mercury.sign} · 第${mercury.house}宫',
                color: _jade,
              ),
              const Divider(height: 24, color: _line),
              _InsightRow(
                icon: Icons.favorite_border_rounded,
                label: '靠近方式',
                value: _signCue(venus.sign, _CueKind.love),
                basis: '金星${venus.sign} · 第${venus.house}宫',
                color: const Color(0xFFB46677),
              ),
              const Divider(height: 24, color: _line),
              _InsightRow(
                icon: Icons.bolt_rounded,
                label: '行动节奏',
                value: _signCue(mars.sign, _CueKind.action),
                basis: '火星${mars.sign} · 第${mars.house}宫',
                color: const Color(0xFFBE765C),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PaperCard(
          title: '成长课题',
          subtitle: '最费力的地方，也常是最能练出真本事的地方',
          child: _GrowthLesson(saturn: saturn),
        ),
        const SizedBox(height: 14),
        _EnergyCard(elements: chart.elements, modes: chart.modes),
        if (chart.interpretations.isNotEmpty) ...[
          const SizedBox(height: 14),
          _PaperCard(
            title: '进一步解读',
            subtitle: '结合行星落座、宫位与主要相位',
            child: Column(
              children: [
                for (var index = 0;
                    index < chart.interpretations.length;
                    index++) ...[
                  _ExtendedReading(item: chart.interpretations[index]),
                  if (index != chart.interpretations.length - 1)
                    const Divider(height: 28, color: _line),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          chart.disclaimer,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, height: 1.5, color: _muted),
        ),
      ],
    );
  }
}

class _StarSpiritProfile {
  const _StarSpiritProfile({
    required this.name,
    required this.species,
    required this.assetPath,
    required this.tagline,
    required this.element,
    required this.primary,
    required this.secondary,
    required this.form,
  });

  final String name;
  final String species;
  final String assetPath;
  final String tagline;
  final String element;
  final Color primary;
  final Color secondary;
  final _StarSpiritForm form;
}

_StarSpiritProfile _spiritFor(AstrologyChartData chart) {
  const profiles = <String,
      ({
    String name,
    String species,
    String assetPath,
    Color primary,
    Color secondary,
    _StarSpiritForm form,
  })>{
    '火': (
      name: '曜焰翼狮',
      species: '翼狮',
      assetPath: 'assets/astrology/star_spirit_fire_v2.png',
      primary: Color(0xFFE56F62),
      secondary: Color(0xFFF4B35F),
      form: _StarSpiritForm.flare,
    ),
    '土': (
      name: '星岩灵鹿',
      species: '灵鹿',
      assetPath: 'assets/astrology/star_spirit_earth_v2.png',
      primary: Color(0xFFA27B58),
      secondary: Color(0xFF78A98C),
      form: _StarSpiritForm.crystal,
    ),
    '风': (
      name: '云岚翼狐',
      species: '翼狐',
      assetPath: 'assets/astrology/star_spirit_air_v2.png',
      primary: Color(0xFF5B9DD7),
      secondary: Color(0xFF8A78C5),
      form: _StarSpiritForm.vortex,
    ),
    '水': (
      name: '潮汐海麟',
      species: '海麟',
      assetPath: 'assets/astrology/star_spirit_water_v2.png',
      primary: Color(0xFF327FB3),
      secondary: Color(0xFF4FC2B4),
      form: _StarSpiritForm.tide,
    ),
  };
  final entries = chart.elements.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final dominant = entries.isEmpty ? '水' : entries.first.key;
  final visual = profiles[dominant] ?? profiles['水']!;
  final sun = chart.position('Sun');
  final moon = chart.position('Moon');
  final asc = chart.ascendant;
  return _StarSpiritProfile(
    name: visual.name,
    species: visual.species,
    assetPath: visual.assetPath,
    tagline:
        '${_signCue(asc.sign, _CueKind.outer)}，${_signCue(moon.sign, _CueKind.emotion)}；${_signCue(sun.sign, _CueKind.core)}。',
    element: dominant,
    primary: visual.primary,
    secondary: visual.secondary,
    form: visual.form,
  );
}

enum _StarSpiritForm { flare, crystal, vortex, tide }

class _StarSpiritHero extends StatelessWidget {
  const _StarSpiritHero({
    required this.spirit,
    required this.sun,
    required this.moon,
    required this.ascendant,
  });

  final _StarSpiritProfile spirit;
  final AstrologyPosition sun;
  final AstrologyPosition moon;
  final AstrologyPosition ascendant;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 328,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFF0B1222),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22030A16),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 4,
            bottom: 4,
            width: 202,
            child: IgnorePointer(
              child: Semantics(
                label: '${spirit.name}，由星河与金色星轨构成的${spirit.species}',
                image: true,
                child: Image.asset(
                  spirit.assetPath,
                  key: const ValueKey('astrology-star-spirit-image'),
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 158, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 16, color: Color(0xFF80DDD7)),
                      SizedBox(width: 6),
                      Text(
                        '你的本命星灵',
                        style: TextStyle(
                          color: Color(0xFF80DDD7),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    spirit.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    spirit.tagline,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC8D4E7),
                      fontSize: 13,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${spirit.element}象共振 · 星河${spirit.species}',
                    style: const TextStyle(
                      color: Color(0xFF80DDD7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _AstroChip(label: '太阳${sun.sign}'),
                      _AstroChip(label: '月亮${moon.sign}'),
                      _AstroChip(label: '上升${ascendant.sign}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 星灵只由光、轨道和星座节点构成，刻意不绘制动物、人物或八字命灵素材。
// Retained as a lightweight fallback for platforms that cannot decode the hero asset.
// ignore: unused_element
class _StarSpiritSigil extends StatelessWidget {
  const _StarSpiritSigil({required this.spirit});

  final _StarSpiritProfile spirit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${spirit.name}抽象星图，由星云、星轨与星座节点组成',
      image: true,
      child: CustomPaint(
        key: const ValueKey('astrology-star-spirit-sigil'),
        painter: _StarSpiritSigilPainter(spirit),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StarSpiritSigilPainter extends CustomPainter {
  const _StarSpiritSigilPainter(this.spirit);

  final _StarSpiritProfile spirit;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .52, size.height * .49);
    final radius = math.min(size.width, size.height) * .27;
    final auraBounds = Rect.fromCircle(center: center, radius: radius * 1.85);
    final aura = Paint()
      ..shader = RadialGradient(
        colors: [
          spirit.primary.withValues(alpha: .28),
          spirit.secondary.withValues(alpha: .12),
          Colors.transparent,
        ],
        stops: const [0, .5, 1],
      ).createShader(auraBounds);
    canvas.drawCircle(center, radius * 1.85, aura);

    _drawOrbits(canvas, center, radius);
    _drawConstellation(canvas, size);

    switch (spirit.form) {
      case _StarSpiritForm.flare:
        _drawFlare(canvas, center, radius);
      case _StarSpiritForm.crystal:
        _drawCrystal(canvas, center, radius);
      case _StarSpiritForm.vortex:
        _drawVortex(canvas, center, radius);
      case _StarSpiritForm.tide:
        _drawTide(canvas, center, radius);
    }

    final coreBounds = Rect.fromCircle(center: center, radius: radius * .48);
    canvas.drawCircle(
      center,
      radius * .48,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            spirit.secondary.withValues(alpha: .88),
            spirit.primary,
          ],
          stops: const [0, .42, 1],
        ).createShader(coreBounds),
    );
    canvas.drawCircle(
      center,
      radius * .51,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: .86),
    );
    canvas.drawCircle(
      center - Offset(radius * .13, radius * .14),
      radius * .075,
      Paint()..color = Colors.white.withValues(alpha: .92),
    );
  }

  void _drawOrbits(Canvas canvas, Offset center, double radius) {
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = spirit.primary.withValues(alpha: .3);
    for (final values in const [
      (1.55, .58, -.36),
      (1.42, .72, .48),
      (1.12, .46, 1.02),
    ]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(values.$3);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * values.$1 * 2,
          height: radius * values.$2 * 2,
        ),
        orbit,
      );
      canvas.restore();
    }
  }

  void _drawConstellation(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(size.width * .16, size.height * .23),
      Offset(size.width * .35, size.height * .14),
      Offset(size.width * .56, size.height * .23),
      Offset(size.width * .78, size.height * .12),
      Offset(size.width * .86, size.height * .34),
      Offset(size.width * .74, size.height * .64),
      Offset(size.width * .9, size.height * .8),
      Offset(size.width * .58, size.height * .88),
      Offset(size.width * .29, size.height * .79),
      Offset(size.width * .12, size.height * .62),
    ];
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = spirit.secondary.withValues(alpha: .34);
    final star = Paint()..color = Colors.white.withValues(alpha: .94);
    for (var index = 0; index < points.length - 1; index++) {
      canvas.drawLine(points[index], points[index + 1], line);
    }
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(points[index], index.isEven ? 2.2 : 1.4, star);
    }
  }

  void _drawFlare(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * .11
      ..color = spirit.primary.withValues(alpha: .48);
    for (var index = 0; index < 6; index++) {
      final angle = index * math.pi / 3;
      final start = center + Offset.fromDirection(angle, radius * .6);
      final end = center + Offset.fromDirection(angle + .16, radius * 1.13);
      canvas.drawLine(start, end, paint);
    }
  }

  void _drawCrystal(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2
      ..color = spirit.primary.withValues(alpha: .52);
    for (final scale in const [.72, 1.05]) {
      final path = Path();
      for (var index = 0; index < 6; index++) {
        final point = center +
            Offset.fromDirection(
              -math.pi / 2 + index * math.pi / 3,
              radius * scale,
            );
        index == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawVortex(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = spirit.primary.withValues(alpha: .5);
    for (var index = 0; index < 3; index++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * (.72 + index * .2)),
        -.8 + index * .72,
        math.pi * 1.12,
        false,
        paint,
      );
    }
  }

  void _drawTide(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = spirit.primary.withValues(alpha: .5);
    for (var index = 0; index < 3; index++) {
      final verticalOffset = radius * (-.54 + index * .45);
      final path = Path()
        ..moveTo(center.dx - radius, center.dy + verticalOffset)
        ..cubicTo(
          center.dx - radius * .5,
          center.dy + verticalOffset - radius * .3,
          center.dx + radius * .5,
          center.dy + verticalOffset + radius * .3,
          center.dx + radius,
          center.dy + verticalOffset,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarSpiritSigilPainter oldDelegate) =>
      oldDelegate.spirit.form != spirit.form ||
      oldDelegate.spirit.primary != spirit.primary ||
      oldDelegate.spirit.secondary != spirit.secondary;
}

class _AstroChip extends StatelessWidget {
  const _AstroChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A173F3B),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CoreSignal extends StatelessWidget {
  const _CoreSignal({
    required this.icon,
    required this.label,
    required this.value,
    required this.basis,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String basis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11.5)),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _ink,
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          basis,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 114,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: _line,
      );
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.basis,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String basis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(value,
                  style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(basis, style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GrowthLesson extends StatelessWidget {
  const _GrowthLesson({required this.saturn});
  final AstrologyPosition saturn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F8F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.explore_outlined, color: _jade, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _saturnLesson(saturn),
                  style: const TextStyle(
                    color: _deepJade,
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '土星${saturn.sign} · 第${saturn.house}宫',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EnergyCard extends StatelessWidget {
  const _EnergyCard({required this.elements, required this.modes});
  final Map<String, int> elements;
  final Map<String, int> modes;

  @override
  Widget build(BuildContext context) {
    final maximum = elements.values.fold<int>(1, (a, b) => a > b ? a : b);
    return _PaperCard(
      title: '能量结构',
      subtitle: '不是谁多谁就更好，而是看你习惯先调用哪股能量',
      child: Column(
        children: [
          for (final entry in elements.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(entry.key,
                        style: const TextStyle(
                            color: _ink, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: entry.value / maximum,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFEAF1EF),
                        color: entry.key == '水' || entry.key == '风'
                            ? _jade
                            : _violet,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('${entry.value}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: _muted)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              modes.entries
                  .map((item) => '${item.key}${item.value}')
                  .join(' · '),
              style: const TextStyle(color: _muted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtendedReading extends StatelessWidget {
  const _ExtendedReading({required this.item});
  final AstrologyInterpretation item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title,
            style: const TextStyle(
                color: _deepJade, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(item.subtitle,
            style: const TextStyle(
                color: _violet, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(item.content,
            style: const TextStyle(color: _ink, fontSize: 13.5, height: 1.65)),
      ],
    );
  }
}

enum _CueKind { outer, emotion, core, expression, love, action }

String _signCue(String sign, _CueKind kind) {
  const cues = <String, Map<_CueKind, String>>{
    '白羊座': {
      _CueKind.outer: '先上场再调整',
      _CueKind.emotion: '一点就着，也很快翻篇',
      _CueKind.core: '要活得有冲劲',
      _CueKind.expression: '想到就说，直球不绕路',
      _CueKind.love: '喜欢就会给出明确信号',
      _CueKind.action: '启动快，靠目标续航',
    },
    '金牛座': {
      _CueKind.outer: '稳住场面再行动',
      _CueKind.emotion: '需要确定感才会放松',
      _CueKind.core: '把日子过得可触摸',
      _CueKind.expression: '少说空话，更信实际结果',
      _CueKind.love: '用陪伴和兑现表达在乎',
      _CueKind.action: '慢热启动，进入状态很持久',
    },
    '双子座': {
      _CueKind.outer: '先聊两句摸清频道',
      _CueKind.emotion: '说出来才知道自己怎么想',
      _CueKind.core: '靠好奇心保持鲜活',
      _CueKind.expression: '信息快、转弯快、梗也快',
      _CueKind.love: '能聊到一起才会持续靠近',
      _CueKind.action: '多线并行，变化里找动力',
    },
    '巨蟹座': {
      _CueKind.outer: '先感受氛围是否安全',
      _CueKind.emotion: '嘴上没事，心里都有存档',
      _CueKind.core: '守住真正重要的人和事',
      _CueKind.expression: '会照顾语气，也会藏半句',
      _CueKind.love: '把照顾做进生活细节里',
      _CueKind.action: '情绪有归属，行动才稳定',
    },
    '狮子座': {
      _CueKind.outer: '自然站到有光的位置',
      _CueKind.emotion: '要被认真看见和回应',
      _CueKind.core: '活得真诚，也活得漂亮',
      _CueKind.expression: '有感染力，不爱含糊表态',
      _CueKind.love: '大方偏爱，也期待被珍惜',
      _CueKind.action: '认定舞台后会全力以赴',
    },
    '处女座': {
      _CueKind.outer: '先观察细节和规则',
      _CueKind.emotion: '忙着解决问题来安顿自己',
      _CueKind.core: '让混乱变得清楚可控',
      _CueKind.expression: '重点清晰，细节不肯放水',
      _CueKind.love: '用靠谱和照料替代空口浪漫',
      _CueKind.action: '拆成步骤，越做越顺手',
    },
    '天秤座': {
      _CueKind.outer: '先找到彼此舒服的分寸',
      _CueKind.emotion: '关系失衡时最难装没事',
      _CueKind.core: '在选择中建立自己的尺度',
      _CueKind.expression: '会换位，也怕话说得太满',
      _CueKind.love: '重视平等、体面和共同审美',
      _CueKind.action: '权衡充分后才愿意落子',
    },
    '天蝎座': {
      _CueKind.outer: '先看深浅，不急着交底',
      _CueKind.emotion: '不轻易动，一动就很深',
      _CueKind.core: '要真实，不要表面热闹',
      _CueKind.expression: '话不一定多，但会直指核心',
      _CueKind.love: '确认忠诚后才会完全投入',
      _CueKind.action: '目标越难，韧劲越明显',
    },
    '射手座': {
      _CueKind.outer: '先把可能性打开',
      _CueKind.emotion: '空间够大，心才舒展',
      _CueKind.core: '靠探索和信念向前',
      _CueKind.expression: '坦率带梗，先讲大方向',
      _CueKind.love: '并肩成长比黏在一起重要',
      _CueKind.action: '看见远方就有发动机',
    },
    '摩羯座': {
      _CueKind.outer: '先确认责任和边界',
      _CueKind.emotion: '习惯先扛住，再慢慢消化',
      _CueKind.core: '把承诺做成真正的成果',
      _CueKind.expression: '结论优先，不浪费彼此时间',
      _CueKind.love: '用长期规划表达认真',
      _CueKind.action: '耐得住慢，越做越有分量',
    },
    '水瓶座': {
      _CueKind.outer: '先保持一点独立距离',
      _CueKind.emotion: '需要想明白才肯靠近感受',
      _CueKind.core: '按自己的逻辑活得清醒',
      _CueKind.expression: '观点跳脱，常从系统看问题',
      _CueKind.love: '尊重差异，比时时报备重要',
      _CueKind.action: '新方法比老套路更能点燃你',
    },
    '双鱼座': {
      _CueKind.outer: '先接住现场的情绪',
      _CueKind.emotion: '感受很深，也容易替人共鸣',
      _CueKind.core: '让想象和善意有出口',
      _CueKind.expression: '会留白，也擅长说出氛围',
      _CueKind.love: '需要被理解，而不只是被安排',
      _CueKind.action: '有意义感时，行动格外投入',
    },
  };
  return cues[sign]?[kind] ?? '按自己的节奏认识世界';
}

String _saturnLesson(AstrologyPosition saturn) {
  const lessons = <String, String>{
    '白羊座': '练习坚定地开始，也允许自己不必每次都赢。',
    '金牛座': '安全感不能只靠囤积，稳定也来自相信自己的应变力。',
    '双子座': '把聪明变成可持续的专注，让观点经得住反复推敲。',
    '巨蟹座': '照顾别人之前先安顿自己，温柔也需要清楚边界。',
    '狮子座': '不靠掌声确认价值，把创造力练成稳定的作品。',
    '处女座': '把标准用来改善事情，而不是无限挑剔自己。',
    '天秤座': '关系里的和平不等于回避选择，清楚表达也是一种体面。',
    '天蝎座': '学会在深度信任中放下控制，力量不只来自防备。',
    '射手座': '让远方落到计划里，自由会因为承担而更辽阔。',
    '摩羯座': '可以有目标，也可以休息；你的价值不只等于完成了多少。',
    '水瓶座': '独立思考之外，也练习让真实的人走进你的系统。',
    '双鱼座': '把敏感变成清晰边界，让想象最终拥有现实形状。',
  };
  return lessons[saturn.sign] ?? '把反复遇见的难题，慢慢练成自己的可靠能力。';
}
