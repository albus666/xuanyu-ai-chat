import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'qizheng_models.dart';

const _page = Color(0xFFF4F1EA);
const _paper = Color(0xFFFFFDFC);
const _ink = Color(0xFF263332);
const _muted = Color(0xFF74817E);
const _jade = Color(0xFF246E69);
const _jadeSoft = Color(0xFFE7F0ED);
const _gold = Color(0xFFB58A45);
const _line = Color(0xFFE5E2D9);
const _night = Color(0xFF102A34);
const _governorKeys = <String>{
  'Sun',
  'Moon',
  'Mercury',
  'Venus',
  'Mars',
  'Jupiter',
  'Saturn',
};

/// 面向普通用户的七政四余解读。所有结论只消费后端已计算的宿、宫、
/// 殿垣与会照数据，不在前端重新推算天体位置。
class QizhengPersonalReading extends StatelessWidget {
  const QizhengPersonalReading({super.key, required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    final insights = _buildInsights(chart);
    return ColoredBox(
      color: _page,
      child: ListView(
        key: const ValueKey('qizheng-personal-reading'),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
        children: [
          _CelestialHero(chart: chart),
          const SizedBox(height: 12),
          _InsightPanel(insights: insights),
          const SizedBox(height: 12),
          _SevenGovernorsPanel(chart: chart),
          const SizedBox(height: 12),
          _FourRemaindersBanner(chart: chart),
          const SizedBox(height: 12),
          _PalaceLifeMap(chart: chart),
          if (chart.interpretations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FullReadingSection(chart: chart),
          ],
          const SizedBox(height: 18),
          Text(
            chart.disclaimer,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: _muted, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _CelestialHero extends StatelessWidget {
  const _CelestialHero({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    final moon = chart.body('Moon');
    final mansion = chart.birthMansion;
    return Container(
      height: 340,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [_night, Color(0xFF123A3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2608171C),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: 39,
            width: 196,
            height: 196,
            child: CustomPaint(
              key: const ValueKey('qizheng-personal-orbit'),
              painter: _CelestialOrbitPainter(chart: chart),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _night.withValues(alpha: .97),
                    _night.withValues(alpha: .7),
                    Colors.transparent,
                  ],
                  stops: const [0, .34, .72],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 18,
            top: 18,
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: Color(0xFFD8BC78),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '你的本命气象 · ${mansion.quadrant}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE4D4A8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            top: 67,
            width: 174,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '月宿于${moon.mansion}\n${mansion.ruler}曜为引',
                  style: const TextStyle(
                    color: Color(0xFFF1D8A0),
                    fontSize: 27,
                    height: 1.34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  mansion.tone,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .83),
                    fontSize: 12.5,
                    height: 1.65,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            height: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _HeroCoordinate(
                      label: '命度',
                      value:
                          '${chart.lifeDegree.mansion}宿 ${_compactDegree(chart.lifeDegree.mansionDegree)}',
                    ),
                  ),
                  _heroDivider(),
                  Expanded(
                    child: _HeroCoordinate(
                      label: '月躔',
                      value:
                          '${moon.mansion}宿 ${_compactDegree(moon.mansionDegree)}',
                    ),
                  ),
                  _heroDivider(),
                  Expanded(
                    child: _HeroCoordinate(
                      label: '命宫',
                      value: chart.lifeDegree.palace,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroDivider() => Container(
        width: .7,
        height: 34,
        color: Colors.white.withValues(alpha: .2),
      );
}

class _HeroCoordinate extends StatelessWidget {
  const _HeroCoordinate({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .6),
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CelestialOrbitPainter extends CustomPainter {
  const _CelestialOrbitPainter({required this.chart});

  final QizhengChartData chart;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 9;
    final ringPaint = Paint()
      ..color = const Color(0xFFCFB36F).withValues(alpha: .27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (final scale in const [.3, .45, .6, .75, .91]) {
      canvas.drawCircle(center, radius * scale, ringPaint);
    }

    final highlighted = chart.mansions.where(
      (item) => item.name == chart.birthMansion.name,
    );
    if (highlighted.isNotEmpty) {
      final mansion = highlighted.first;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * .91),
        _angle(mansion.longitude),
        mansion.width * math.pi / 180,
        false,
        Paint()
          ..color = const Color(0xFFE6C36E).withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    }

    final tickPaint = Paint()
      ..color = const Color(0xFFD9C588).withValues(alpha: .5)
      ..strokeWidth = .7;
    for (final mansion in chart.mansions) {
      final angle = _angle(mansion.longitude);
      canvas.drawLine(
        _point(center, radius * .84, angle),
        _point(center, radius * .97, angle),
        tickPaint,
      );
    }

    for (var index = 0; index < chart.bodies.length; index++) {
      final body = chart.bodies[index];
      final angle = _angle(body.longitude);
      final orbit = radius * (.31 + (index % 4) * .14);
      final point = _point(center, orbit, angle);
      final color = _bodyColor(body);
      final isGovernor = _governorKeys.contains(body.key);
      canvas.drawCircle(
        point,
        isGovernor ? 6.2 : 4.6,
        Paint()
          ..color =
              isGovernor ? color.withValues(alpha: .2) : Colors.transparent
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        point,
        isGovernor ? 3.7 : 3.1,
        Paint()
          ..color = isGovernor ? color : const Color(0xFFD9C588)
          ..style = isGovernor ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final labelPainter = TextPainter(
        text: TextSpan(
          text: body.shortName,
          style: TextStyle(
            color: isGovernor ? Colors.white : const Color(0xFFE1CA8F),
            fontSize: isGovernor ? 8.5 : 7.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(canvas, point + const Offset(5, -12));
    }

    canvas.drawCircle(
      center,
      4,
      Paint()..color = const Color(0xFFE2BD62),
    );
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = const Color(0xFFE2BD62).withValues(alpha: .52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  double _angle(double longitude) => longitude * math.pi / 180 - math.pi / 2;

  Offset _point(Offset center, double radius, double angle) => Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

  @override
  bool shouldRepaint(covariant _CelestialOrbitPainter oldDelegate) =>
      oldDelegate.chart != chart;
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.insights});

  final List<_Insight> insights;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: '先看懂这三件事',
      child: Column(
        children: [
          for (var index = 0; index < insights.length; index++) ...[
            _InsightRow(
              index: index + 1,
              insight: insights[index],
              onTap: () => _showReadingSheet(context, insights[index]),
            ),
            if (index != insights.length - 1)
              const Divider(height: 1, color: _line),
          ],
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.index,
    required this.insight,
    required this.onTap,
  });

  final int index;
  final _Insight insight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${insight.title}，${insight.summary}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: _jade,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  insight.title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  insight.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF9B9589),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SevenGovernorsPanel extends StatelessWidget {
  const _SevenGovernorsPanel({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    final bodies = <QizhengBodyPosition>[
      chart.body('Sun'),
      chart.body('Moon'),
      chart.body('Jupiter'),
    ];
    return _SectionPanel(
      title: '七政落点',
      trailing: TextButton(
        onPressed: () => _showBodySheet(
          context,
          title: '全部七政',
          subtitle: '日月五星在宿度与十二宫中的真实落点',
          bodies: _governorKeys.map(chart.body).toList(growable: false),
        ),
        style: TextButton.styleFrom(
          foregroundColor: _jade,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('全部七政', style: TextStyle(fontSize: 11.5)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < bodies.length; index++) ...[
            Expanded(
              child: _BodySpot(
                body: bodies[index],
                onTap: () => _showBodySheet(
                  context,
                  title: bodies[index].name,
                  subtitle: '以实际落宫、入宿和殿垣状态综合观察',
                  bodies: [bodies[index]],
                ),
              ),
            ),
            if (index != bodies.length - 1)
              Container(width: 1, height: 78, color: _line),
          ],
        ],
      ),
    );
  }
}

class _BodySpot extends StatelessWidget {
  const _BodySpot({required this.body, required this.onTap});

  final QizhengBodyPosition body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _bodyColor(body);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-.3, -.35),
                  colors: [Colors.white, color.withValues(alpha: .55), color],
                  stops: const [0, .48, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                body.shortName,
                style: const TextStyle(
                  color: _night,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              body.name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                body.palaceRole,
                maxLines: 1,
                style: const TextStyle(color: _muted, fontSize: 10.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body.dignities.isEmpty
                  ? '${body.mansion}宿'
                  : body.dignities.take(2).join('·'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _jade, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _FourRemaindersBanner extends StatelessWidget {
  const _FourRemaindersBanner({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    final bodies = <QizhengBodyPosition>[
      chart.body('Rahu'),
      chart.body('Ketu'),
      chart.body('PurpleQi'),
      chart.body('Yuebei'),
    ];
    final interpretation = _findInterpretation(chart, ['四余课题']);
    return Material(
      color: const Color(0xFFF4EBD8),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showBodySheet(
          context,
          title: '四余提醒',
          subtitle:
              interpretation?.content ?? '四余是计算点，用于提示容易反复牵动的议题，需结合七政一起判断。',
          bodies: bodies,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _paper.withValues(alpha: .72),
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold.withValues(alpha: .45)),
                ),
                child: const Icon(Icons.flare_rounded, color: _gold, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '四余提醒',
                      style: TextStyle(
                        color: Color(0xFF8B642C),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '罗睺落${bodies[0].palaceRole}，月孛落${bodies[3].palaceRole}；要结合七政看牵动的议题。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF645A49),
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '查看依据',
                    style: TextStyle(
                      color: Color(0xFF8B642C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF9C7337),
                    size: 17,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PalaceLifeMap extends StatelessWidget {
  const _PalaceLifeMap({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: '十二宫人生地图',
      trailing: const Text(
        '左右滑动',
        style: TextStyle(color: _muted, fontSize: 11.5),
      ),
      child: SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: chart.palaces.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (_, index) {
            final palace = chart.palaces[index];
            return _PalaceCard(
              key: ValueKey('qizheng-palace-${palace.name}'),
              palace: palace,
              occupantNames: _occupantNames(chart, palace),
              onTap: () => _showPalaceSheet(context, chart, palace),
            );
          },
        ),
      ),
    );
  }
}

class _PalaceCard extends StatelessWidget {
  const _PalaceCard({
    super.key,
    required this.palace,
    required this.occupantNames,
    required this.onTap,
  });

  final QizhengPalace palace;
  final String occupantNames;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAF8F2),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          width: 142,
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 11),
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      palace.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: _gold,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                palace.name,
                style: const TextStyle(color: _gold, fontSize: 11.5),
              ),
              const Spacer(),
              Text(
                occupantNames.isEmpty ? '无曜 · 借看会照' : occupantNames,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _jade,
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullReadingSection extends StatelessWidget {
  const _FullReadingSection({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: '完整解读依据',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _jadeSoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '${chart.interpretations.length}项',
          style: const TextStyle(
            color: _jade,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 13),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '结合七政、四余、宫度与会照的实际排盘结果',
                style: TextStyle(color: _muted, fontSize: 11.5),
              ),
            ),
          ),
          for (var index = 0;
              index < chart.interpretations.length;
              index++) ...[
            _InlineReadingRow(item: chart.interpretations[index]),
            if (index != chart.interpretations.length - 1)
              const Divider(height: 24, color: _line),
          ],
        ],
      ),
    );
  }
}

class _InlineReadingRow extends StatelessWidget {
  const _InlineReadingRow({required this.item});

  final QizhengInterpretation item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _jadeSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _jade,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.subtitle,
                style: const TextStyle(
                  color: _gold,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.content,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  height: 1.65,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _paper,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _Insight {
  const _Insight({
    required this.title,
    required this.summary,
    required this.subtitle,
    required this.detail,
  });

  final String title;
  final String summary;
  final String subtitle;
  final String detail;
}

List<_Insight> _buildInsights(QizhengChartData chart) {
  final moon = chart.body('Moon');
  final venus = chart.body('Venus');
  final jupiter = chart.body('Jupiter');
  final saturn = chart.body('Saturn');
  final birth = _findInterpretation(chart, ['本命星宿']);
  final relation = _findInterpretation(chart, ['情感与连接']);
  final growth = _findInterpretation(chart, ['行动与事业']);
  return [
    _Insight(
      title: '性格底色',
      summary: chart.birthMansion.tone,
      subtitle: birth?.subtitle ??
          '${chart.birthMansion.name}宿 · ${chart.birthMansion.quadrant}',
      detail: birth?.content ?? chart.birthMansion.tone,
    ),
    _Insight(
      title: '关系感受',
      summary: '太阴在${moon.palaceRole}，金星在${venus.palaceRole}；先安顿感受，再说清需要。',
      subtitle:
          relation?.subtitle ?? '月${moon.palaceRole} · 金${venus.palaceRole}',
      detail: relation?.content ??
          '太阴躔${moon.mansion}宿，金星躔${venus.mansion}宿。关系感受要结合两者的落宫、入宿和殿垣状态一起观察。',
    ),
    _Insight(
      title: '成长节奏',
      summary: '木星落${jupiter.palaceRole}打开机会，土星落${saturn.palaceRole}帮你守住长期积累。',
      subtitle:
          growth?.subtitle ?? '木${jupiter.palaceRole} · 土${saturn.palaceRole}',
      detail: growth?.content ??
          '木星主扩展，土星主建设与约束。两者分别落在${jupiter.palace}和${saturn.palace}，适合将机会与责任分开安排。',
    ),
  ];
}

QizhengInterpretation? _findInterpretation(
  QizhengChartData chart,
  List<String> titles,
) {
  for (final item in chart.interpretations) {
    if (titles.any((title) => item.title.contains(title))) return item;
  }
  return null;
}

void _showReadingSheet(BuildContext context, _Insight insight) {
  _showSheet(
    context,
    title: insight.title,
    subtitle: insight.subtitle,
    children: [
      Text(
        insight.detail,
        style: const TextStyle(color: _ink, fontSize: 15, height: 1.8),
      ),
    ],
  );
}

void _showBodySheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<QizhengBodyPosition> bodies,
}) {
  _showSheet(
    context,
    title: title,
    subtitle: subtitle,
    children: [
      for (var index = 0; index < bodies.length; index++) ...[
        _SheetBodyRow(body: bodies[index]),
        if (index != bodies.length - 1) const Divider(height: 26, color: _line),
      ],
    ],
  );
}

void _showPalaceSheet(
  BuildContext context,
  QizhengChartData chart,
  QizhengPalace palace,
) {
  final occupants = _occupantNames(chart, palace);
  _showSheet(
    context,
    title: palace.role,
    subtitle: '${palace.name} · ${palace.element}',
    children: [
      const Text(
        '本宫落入星曜',
        style: TextStyle(color: _muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Text(
        occupants.isEmpty ? '本宫无七政四余直接落入' : occupants,
        style: const TextStyle(
          color: _ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        occupants.isEmpty
            ? '这是传统命盘中的正常“空宫”，不是数据缺失。需要借看对宫、三方四正和会照星曜。'
            : '宫位不宜单独定吉凶，还需要与星曜状态、宿度及会照关系一起阅读。',
        style: const TextStyle(color: _muted, fontSize: 13, height: 1.65),
      ),
    ],
  );
}

void _showSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<Widget> children,
}) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: .68,
      minChildSize: .38,
      maxChildSize: .92,
      expand: false,
      builder: (_, controller) => Material(
        color: _paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7D3CA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: _jade, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _SheetBodyRow extends StatelessWidget {
  const _SheetBodyRow({required this.body});

  final QizhengBodyPosition body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _bodyColor(body).withValues(alpha: .13),
            shape: BoxShape.circle,
          ),
          child: Text(
            body.shortName,
            style: TextStyle(
              color: _bodyColor(body),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    body.name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (body.retrograde) ...[
                    const SizedBox(width: 6),
                    const Text(
                      '逆',
                      style: TextStyle(color: Color(0xFFB45F58), fontSize: 11),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${body.palace} · ${body.palaceRole}  |  ${body.mansion}宿 ${_degree(body.mansionDegree)}',
                style:
                    const TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 3),
              Text(
                body.dignities.isEmpty
                    ? '无额外殿垣标记，需结合会照'
                    : '传统状态：${body.dignities.join('、')}',
                style: const TextStyle(color: _jade, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _occupantNames(QizhengChartData chart, QizhengPalace palace) {
  final occupantKeys = palace.occupants.toSet();
  final bodies = chart.bodies.where(
    (body) =>
        occupantKeys.contains(body.key) ||
        body.palace == palace.name ||
        body.palaceRole == palace.role,
  );
  return bodies.map((body) => body.name).toSet().join('·');
}

Color _bodyColor(QizhengBodyPosition body) {
  const fallback = <String, Color>{
    'Sun': Color(0xFFD2A348),
    'Moon': Color(0xFFC5CFD1),
    'Mercury': Color(0xFF52A9A1),
    'Venus': Color(0xFFD5B277),
    'Mars': Color(0xFFC86E56),
    'Jupiter': Color(0xFF55988D),
    'Saturn': Color(0xFF9B8761),
  };
  final raw = body.colorHex.replaceFirst('#', '');
  final parsed = int.tryParse(raw, radix: 16);
  if (parsed != null && raw.length == 6) return Color(0xFF000000 | parsed);
  return fallback[body.key] ?? const Color(0xFFB99A62);
}

String _degree(double value) {
  final degree = value.floor();
  var minute = ((value - degree) * 60).round();
  var normalizedDegree = degree;
  if (minute == 60) {
    normalizedDegree += 1;
    minute = 0;
  }
  return '$normalizedDegree°${minute.toString().padLeft(2, '0')}′';
}

String _compactDegree(double value) {
  final degree = value.floor();
  return '${degree.toString().padLeft(2, '0')}°';
}
