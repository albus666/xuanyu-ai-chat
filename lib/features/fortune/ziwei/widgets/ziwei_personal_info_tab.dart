import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../shared/widgets/cultural_reference_notice.dart';
import 'package:lunar/lunar.dart';

import '../ziwei_models.dart';
import '../ziwei_pattern.dart';
import '../ziwei_single_star_readings.dart';
import '../ziwei_timeline.dart';

const _page = Color(0xFFF4F3EE);
const _paper = Color(0xFFFCFBF8);
const _ink = Color(0xFF263332);
const _muted = Color(0xFF75807C);
const _jade = Color(0xFF3C847C);
const _jadeDark = Color(0xFF173F3B);
const _jadeMist = Color(0xFFE6F0EC);
const _champagne = Color(0xFFB99A62);
const _plum = Color(0xFF75667E);
const _coral = Color(0xFFB6635F);
const _line = Color(0xFFE2E3DE);

class ZiweiPersonalInfoTab extends StatelessWidget {
  const ZiweiPersonalInfoTab({
    super.key,
    required this.data,
    required this.profile,
    required this.targetDate,
    required this.loading,
    required this.onSelectDecadal,
    required this.onSelectYear,
  });

  final ZiweiChartData data;
  final ZiweiProfile profile;
  final DateTime targetDate;
  final bool loading;
  final ValueChanged<ZiweiTimelineItem> onSelectDecadal;
  final ValueChanged<ZiweiTimelineItem> onSelectYear;

  @override
  Widget build(BuildContext context) {
    final pattern = ZiweiPatternRecognizer.recognize(data);
    return ColoredBox(
      color: _page,
      child: ListView(
        key: const PageStorageKey('ziwei-personal-info-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          _PatternHero(pattern: pattern, data: data),
          if (pattern.relatedPatterns.isNotEmpty ||
              pattern.attentionPatterns.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PatternRelations(pattern: pattern),
          ],
          const SizedBox(height: 12),
          _StageSection(
            data: data,
            profile: profile,
            targetDate: targetDate,
            loading: loading,
            onSelectDecadal: onSelectDecadal,
            onSelectYear: onSelectYear,
          ),
          const SizedBox(height: 12),
          _PalaceMap(data: data),
          const SizedBox(height: 12),
          _MutagenSection(data: data),
          const SizedBox(height: 12),
          _LifeTopics(data: data),
          const CulturalReferenceNotice(),
        ],
      ),
    );
  }
}

class _PatternRelations extends StatelessWidget {
  const _PatternRelations({required this.pattern});

  final ZiweiPatternProfile pattern;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pattern.relatedPatterns.isNotEmpty) ...[
            _relationRow(
              label: '同时成立',
              values: pattern.relatedPatterns,
              color: _jade,
            ),
          ],
          if (pattern.relatedPatterns.isNotEmpty &&
              pattern.attentionPatterns.isNotEmpty)
            const SizedBox(height: 9),
          if (pattern.attentionPatterns.isNotEmpty)
            _relationRow(
              label: '需结合全盘',
              values: pattern.attentionPatterns,
              color: _coral,
            ),
        ],
      ),
    );
  }

  Widget _relationRow({
    required String label,
    required List<String> values,
    required Color color,
  }) {
    final shown = values.take(4).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in shown)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _ink,
                    ),
                  ),
                ),
              if (values.length > shown.length)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    '+${values.length - shown.length}',
                    style: const TextStyle(fontSize: 10.5, color: _muted),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PatternHero extends StatelessWidget {
  const _PatternHero({required this.pattern, required this.data});

  final ZiweiPatternProfile pattern;
  final ZiweiChartData data;

  @override
  Widget build(BuildContext context) {
    final palettes = <List<Color>>[
      const [Color(0xFF102D2A), Color(0xFF1C3540), Color(0xFF302738)],
      const [Color(0xFF24332F), Color(0xFF36312D), Color(0xFF443443)],
      const [Color(0xFF18323A), Color(0xFF273443), Color(0xFF46373D)],
      const [Color(0xFF25302F), Color(0xFF372D35), Color(0xFF422C31)],
      const [Color(0xFF183735), Color(0xFF273940), Color(0xFF3B3341)],
    ];
    final palette = palettes[pattern.paletteIndex % palettes.length];
    final decadalName = _scopePalaceName(data.horoscope.decadal);
    final yearlyName = _scopePalaceName(data.horoscope.yearly);
    return Container(
      height: 292,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24172625),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PatternPainter(
                visual: pattern.visual,
                stars: pattern.keyStars,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: .24),
                    Colors.transparent,
                    Colors.black.withValues(alpha: .08),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      pattern.classic ? '本命格局' : '本命主轴',
                      style: const TextStyle(
                        fontSize: 12,
                        letterSpacing: 2,
                        color: Color(0xFFD8C89E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .13),
                        ),
                      ),
                      child: Text(
                        pattern.badgeLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFE2E4DF),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  pattern.name,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1,
                    color: Color(0xFFF4EAD2),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: 230,
                  child: Text(
                    pattern.headline,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in pattern.tags.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFD9E3DF),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  pattern.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: Color(0xFFBFCBC7),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '当前激活',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFD2C59F),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '大限 · $decadalName   流年 · $yearlyName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE7EBE7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter({required this.visual, required this.stars});

  final ZiweiPatternVisual visual;
  final List<String> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * .77, size.height * .34);
    final radius = math.min(size.width, size.height) * .19;
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x8AD7E1D9), Color(0x14D7E1D9), Colors.transparent],
      ).createShader(Rect.fromCircle(center: origin, radius: radius * 1.8));
    canvas.drawCircle(origin, radius * 1.8, glow);

    final orbit = Paint()
      ..color = const Color(0x4AD8D0B7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final bright = Paint()..color = const Color(0xFFD6C28E);
    final pale = Paint()..color = const Color(0xFFC9DDD7);
    final points = _points(origin, radius);
    for (var ring = 1; ring <= 3; ring++) {
      canvas.drawCircle(origin, radius * (.55 + ring * .25), orbit);
    }
    if (visual == ZiweiPatternVisual.triad && points.length >= 3) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < 3; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      canvas.drawPath(path, orbit..strokeWidth = 1.2);
    } else {
      for (var i = 0; i < points.length; i++) {
        canvas.drawLine(origin, points[i], orbit);
      }
    }
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      canvas.drawCircle(point, i.isEven ? 4.2 : 3.2, i.isEven ? bright : pale);
      if (stars.isNotEmpty) {
        _drawText(
          canvas,
          stars[i % stars.length],
          point + const Offset(7, -8),
        );
      }
    }
    canvas.drawCircle(origin, 8, Paint()..color = const Color(0xFFE5D6AE));
    canvas.drawCircle(origin, 4.8, Paint()..color = const Color(0xFF416B67));
  }

  List<Offset> _points(Offset center, double radius) {
    final count = switch (visual) {
      ZiweiPatternVisual.twinCore || ZiweiPatternVisual.sunMoon => 2,
      ZiweiPatternVisual.triad => 3,
      _ => math.max(3, math.min(4, stars.length)),
    };
    return [
      for (var i = 0; i < count; i++)
        Offset(
          center.dx + math.cos(-math.pi / 2 + 2 * math.pi * i / count) * radius,
          center.dy + math.sin(-math.pi / 2 + 2 * math.pi * i / count) * radius,
        ),
    ];
  }

  void _drawText(Canvas canvas, String value, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(
          color: Color(0xFFC9D8D3),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) =>
      visual != oldDelegate.visual || stars.join() != oldDelegate.stars.join();
}

class _StageSection extends StatelessWidget {
  const _StageSection({
    required this.data,
    required this.profile,
    required this.targetDate,
    required this.loading,
    required this.onSelectDecadal,
    required this.onSelectYear,
  });

  final ZiweiChartData data;
  final ZiweiProfile profile;
  final DateTime targetDate;
  final bool loading;
  final ValueChanged<ZiweiTimelineItem> onSelectDecadal;
  final ValueChanged<ZiweiTimelineItem> onSelectYear;

  @override
  Widget build(BuildContext context) {
    final decadals = ZiweiTimelineBuilder.decadals(data, profile);
    final decadalIndex = decadals.indexWhere(
      (item) => data.horoscope.decadal.name == '童限'
          ? item.key == 'decadal-child'
          : item.key != 'decadal-child' &&
              item.palaceIndex == data.horoscope.decadal.index,
    );
    final decadal = decadals[decadalIndex < 0 ? 0 : decadalIndex];
    final years = data.horoscope.decadal.name == '童限'
        ? ZiweiTimelineBuilder.childYears(data, profile)
        : ZiweiTimelineBuilder.years(
            data.palaceAt(data.horoscope.decadal.index),
            profile,
          );
    final lunarYear = Lunar.fromDate(targetDate).getYear();
    final yearIndex = years.indexWhere(
      (item) => data.horoscope.age.nominalAge != null
          ? item.age == data.horoscope.age.nominalAge
          : item.lunarYear == lunarYear,
    );
    final year = years[yearIndex < 0 ? 0 : yearIndex];
    final signals = _stageSignals(data);
    return _Section(
      title: '当前人生阶段',
      icon: Icons.route_outlined,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7F3),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _StageSelector(
                    label: '大限',
                    title: decadal.title,
                    subtitle:
                        '${decadal.tertiary} · ${_scopePalaceName(data.horoscope.decadal)}',
                    enabled: !loading,
                    onTap: () => _pickItem(
                      context,
                      title: '选择大限',
                      items: decadals,
                      selected: decadal,
                      onSelected: onSelectDecadal,
                    ),
                    onPrevious: decadalIndex > 0
                        ? () => onSelectDecadal(decadals[decadalIndex - 1])
                        : null,
                    onNext:
                        decadalIndex >= 0 && decadalIndex < decadals.length - 1
                            ? () => onSelectDecadal(decadals[decadalIndex + 1])
                            : null,
                  ),
                ),
                Container(width: 1, height: 68, color: _line),
                Expanded(
                  child: _StageSelector(
                    label: '流年',
                    title: year.title,
                    subtitle: '${year.tertiary} · ${year.subtitle}',
                    enabled: !loading,
                    onTap: () => _pickItem(
                      context,
                      title: '选择流年',
                      items: years,
                      selected: year,
                      onSelected: onSelectYear,
                    ),
                    onPrevious: yearIndex > 0
                        ? () => onSelectYear(years[yearIndex - 1])
                        : null,
                    onNext: yearIndex >= 0 && yearIndex < years.length - 1
                        ? () => onSelectYear(years[yearIndex + 1])
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < signals.length; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(child: _SignalTile(signal: signals[i])),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 28, height: 1, color: _champagne),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9),
                child: Text(
                  '大运定阶段 · 流年看当年落点',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ),
              Container(width: 28, height: 1, color: _champagne),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickItem(
    BuildContext context, {
    required String title,
    required List<ZiweiTimelineItem> items,
    required ZiweiTimelineItem selected,
    required ValueChanged<ZiweiTimelineItem> onSelected,
  }) async {
    final picked = await showModalBottomSheet<ZiweiTimelineItem>(
      context: context,
      backgroundColor: _paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: math.min(430, MediaQuery.sizeOf(context).height * .58),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final active = item.key == selected.key;
                    return ListTile(
                      selected: active,
                      selectedTileColor: _jadeMist,
                      title: Text('${item.title}  ${item.subtitle}'),
                      subtitle: Text(item.tertiary),
                      trailing: active
                          ? const Icon(Icons.check_rounded, color: _jade)
                          : null,
                      onTap: () => Navigator.of(context).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onSelected(picked);
  }
}

class _StageSelector extends StatelessWidget {
  const _StageSelector({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.onPrevious,
    this.onNext,
  });

  final String label;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: Row(
        children: [
          _StageArrow(
              icon: Icons.chevron_left_rounded,
              onTap: enabled ? onPrevious : null),
          Expanded(
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 10, color: _muted)),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: _muted),
                  ),
                ],
              ),
            ),
          ),
          _StageArrow(
              icon: Icons.chevron_right_rounded,
              onTap: enabled ? onNext : null),
        ],
      ),
    );
  }
}

class _StageArrow extends StatelessWidget {
  const _StageArrow({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(icon, size: 21, color: onTap == null ? _line : _jadeDark),
      );
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});

  final _StageSignal signal;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: signal.color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(signal.icon, size: 19, color: signal.color),
          const SizedBox(height: 5),
          Text(signal.label,
              style: const TextStyle(fontSize: 9.5, color: _muted)),
          Text(
            signal.value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 11,
              color: _ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageSignal {
  const _StageSignal(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

List<_StageSignal> _stageSignals(ZiweiChartData data) {
  final decadal = data.horoscope.decadal;
  final yearly = data.horoscope.yearly;
  final decadalPalace = _scopePalaceName(decadal);
  final yearlyPalace = _scopePalaceName(yearly);
  final decadalStars = _scopeStarsAt(decadal);
  final yearlyStars = _scopeStarsAt(yearly);
  final allStars = {...decadalStars, ...yearlyStars};
  final stageSeed = <String>[
    decadal.ganZhi,
    '${decadal.index}',
    yearly.ganZhi,
    '${yearly.index}',
    '${yearly.nominalAge ?? 0}',
    ...yearly.mutagen,
  ].join('|').codeUnits.fold<int>(0, (sum, value) => sum + value);

  String pick(List<String> values, int offset) =>
      values[(stageSeed + offset) % values.length];

  String signal({
    required Set<String> palaces,
    required Set<String> stars,
    required List<String> focused,
    required List<String> supported,
    required List<String> steady,
    required int offset,
  }) {
    if (palaces.contains(yearlyPalace) || stars.any(yearlyStars.contains)) {
      return pick(focused, offset);
    }
    if (palaces.contains(decadalPalace) || stars.any(allStars.contains)) {
      return pick(supported, offset);
    }
    return pick(steady, offset);
  }

  bool yearlyMutagenIn(Set<String> stars, int index) =>
      index < yearly.mutagen.length && stars.contains(yearly.mutagen[index]);

  var relationship = signal(
    palaces: const {'夫妻', '交友', '迁移'},
    stars: const {'贪狼', '太阴', '天同', '红鸾', '天喜'},
    focused: const ['关系有新题', '互动更主动', '关系重确认'],
    supported: const ['关系重整', '边界再调整', '重新看同频'],
    steady: const ['重在沟通', '先听再表达', '稳定互动'],
    offset: 1,
  );
  if (yearlyMutagenIn(const {'贪狼', '太阴', '天同', '廉贞', '天机'}, 0)) {
    relationship = '互动增温';
  }

  var career = signal(
    palaces: const {'官禄', '迁移'},
    stars: const {'紫微', '武曲', '七杀', '破军', '天相'},
    focused: const ['机会外显', '主动推进', '承担新题'],
    supported: const ['方向调整', '能力换挡', '路径重组'],
    steady: const ['稳步积累', '先做完成', '专注主线'],
    offset: 2,
  );
  if (yearlyMutagenIn(const {'紫微', '武曲', '七杀', '破军', '天相', '太阳'}, 1)) {
    career = '主动担责';
  }

  var wealth = signal(
    palaces: const {'财帛', '田宅'},
    stars: const {'武曲', '天府', '太阴', '禄存', '贪狼'},
    focused: const ['资源流动', '收支重排', '机会换位'],
    supported: const ['资源整合', '结构调整', '重视长线'],
    steady: const ['稳中求进', '先守再动', '量入为出'],
    offset: 3,
  );
  if (yearlyMutagenIn(const {'武曲', '天府', '太阴', '禄存', '贪狼'}, 0)) {
    wealth = '资源增量';
  }

  var rhythm = signal(
    palaces: const {'疾厄', '福德'},
    stars: const {'天梁', '天同', '巨门', '破军'},
    focused: const ['宜减负担', '先缓后快', '留出恢复'],
    supported: const ['节奏重排', '作息归位', '调整步频'],
    steady: const ['保持平衡', '规律推进', '不必过满'],
    offset: 4,
  );
  if (yearlyMutagenIn(const {'天机', '太阴', '巨门', '天同', '廉贞'}, 3)) {
    rhythm = '先解卡点';
  }
  return [
    _StageSignal(
      '关系',
      relationship,
      Icons.favorite_border_rounded,
      const Color(0xFFC2787B),
    ),
    _StageSignal(
      '事业',
      career,
      Icons.trending_up_rounded,
      _jade,
    ),
    _StageSignal(
      '财务',
      wealth,
      Icons.toll_rounded,
      const Color(0xFFB78C3E),
    ),
    _StageSignal(
      '节奏',
      rhythm,
      Icons.spa_outlined,
      _plum,
    ),
  ];
}

@visibleForTesting
List<String> ziweiStageSignalValues(ZiweiChartData data) =>
    _stageSignals(data).map((signal) => signal.value).toList(growable: false);

Set<String> _scopeStarsAt(ZiweiScope scope) {
  if (scope.index < 0 || scope.index >= scope.stars.length) return {};
  return scope.stars[scope.index].map((star) => star.name).toSet();
}

class _PalaceMap extends StatelessWidget {
  const _PalaceMap({required this.data});

  final ZiweiChartData data;

  @override
  Widget build(BuildContext context) {
    final soulIndex = data.astrolabe.palaces
        .firstWhere((p) => p.earthlyBranch == data.astrolabe.soulPalaceBranch)
        .index;
    final cautionIndex = _natalCautionPalace(data)?.index;
    const order = [
      '命宫',
      '兄弟',
      '夫妻',
      '子女',
      '财帛',
      '疾厄',
      '迁移',
      '交友',
      '官禄',
      '田宅',
      '福德',
      '父母',
    ];
    final palaces = [
      for (final name in order) _palaceNamed(data, [name])
    ];
    return _Section(
      title: '十二宫人生地图',
      icon: Icons.grid_view_rounded,
      trailing: const _Legend(),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: palaces.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1.02,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemBuilder: (context, index) {
          final palace = palaces[index];
          final active = palace.index == data.horoscope.yearly.index ||
              palace.index == data.horoscope.decadal.index;
          final natal = palace.index == soulIndex;
          final caution = palace.index == cautionIndex;
          final color = active
              ? _jade
              : natal
                  ? _champagne
                  : caution
                      ? _plum
                      : _line;
          final star = data
              .effectiveMajorStarsFor(palace)
              .take(2)
              .map((item) => item.name)
              .join('·');
          return Container(
            decoration: BoxDecoration(
              color: active
                  ? _jadeMist
                  : natal
                      ? const Color(0xFFF6F0E2)
                      : caution
                          ? const Color(0xFFF2EEF3)
                          : const Color(0xFFF8F8F5),
              borderRadius: BorderRadius.circular(11),
              border:
                  Border.all(color: color, width: active || natal ? 1.2 : .8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _modernPalaceName(palace.name),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: active ? _jadeDark : _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  star.isEmpty ? '暂无主星' : star,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: _muted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => const Wrap(
        spacing: 7,
        children: [
          _LegendItem(color: _champagne, text: '本命'),
          _LegendItem(color: _jade, text: '当前'),
          _LegendItem(color: _plum, text: '化忌'),
        ],
      );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(fontSize: 9, color: _muted)),
        ],
      );
}

class _MutagenSection extends StatelessWidget {
  const _MutagenSection({required this.data});

  final ZiweiChartData data;

  @override
  Widget build(BuildContext context) {
    const labels = ['禄', '权', '科', '忌'];
    const colors = [_jade, _champagne, Color(0xFF54778A), _coral];
    final stars = data.horoscope.yearly.mutagen;
    return _Section(
      title: '四化流转',
      icon: Icons.hub_outlined,
      trailing: Text(
        '${data.horoscope.yearly.ganZhi}流年',
        style: const TextStyle(fontSize: 10, color: _muted),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: _MutagenTile(
                label: labels[i],
                star: i < stars.length ? stars[i] : '未标',
                palace:
                    i < stars.length ? _findStarPalace(data, stars[i]) : '—',
                color: colors[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MutagenTile extends StatelessWidget {
  const _MutagenTile(
      {required this.label,
      required this.star,
      required this.palace,
      required this.color});
  final String label;
  final String star;
  final String palace;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 102,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Column(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 7),
            Text(star,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 2),
            Text(palace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      );
}

class _LifeTopics extends StatelessWidget {
  const _LifeTopics({required this.data});
  final ZiweiChartData data;

  @override
  Widget build(BuildContext context) {
    final topics = <(ZiweiReadingTopic, IconData)>[
      (ZiweiReadingTopic.personality, Icons.auto_awesome_outlined),
      (ZiweiReadingTopic.relationship, Icons.favorite_outline_rounded),
      (ZiweiReadingTopic.career, Icons.work_outline_rounded),
      (ZiweiReadingTopic.wealth, Icons.savings_outlined),
      (ZiweiReadingTopic.social, Icons.people_outline_rounded),
      (ZiweiReadingTopic.inner, Icons.spa_outlined),
    ];
    return _Section(
      title: '认识自己',
      icon: Icons.blur_on_rounded,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topics.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final topic = topics[index];
          final lead = ZiweiSingleStarReadings.summaryFor(data, topic.$1);
          return InkWell(
            onTap: () => _showReading(context, topic.$1, topic.$2),
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                        color: _jadeMist, shape: BoxShape.circle),
                    child: Icon(topic.$2, size: 16, color: _jade),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(topic.$1.title,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _ink)),
                        const SizedBox(height: 2),
                        Text(lead,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 8.8, color: _muted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 13, color: _muted),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showReading(
    BuildContext context,
    ZiweiReadingTopic topic,
    IconData icon,
  ) {
    final palace = ZiweiSingleStarReadings.palaceFor(data, topic);
    final palaceName = _modernPalaceName(palace.name);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _paper,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _jade),
                  const SizedBox(width: 8),
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    palaceName.endsWith('宫') ? palaceName : '$palaceName宫',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ZiweiSingleStarReadings.detailFor(data, topic),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.65,
                  color: Color(0xFF55615E),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '内容用于认识自身倾向与改善日常选择，不代表对现实结果的保证。',
                style: TextStyle(fontSize: 10, height: 1.45, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.icon,
      required this.child,
      this.trailing});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7E6E1)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1E2A28), blurRadius: 16, offset: Offset(0, 7)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: _jade),
                const SizedBox(width: 7),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _jadeDark)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 13),
            child,
          ],
        ),
      );
}

String _scopePalaceName(ZiweiScope scope) {
  if (scope.palaceNames.length <= scope.index) return scope.name;
  return _modernPalaceName(scope.palaceNames[scope.index]);
}

String _modernPalaceName(String name) {
  if (name.contains('仆役')) return name.replaceAll('仆役', '交友');
  if (name.contains('事业')) return name.replaceAll('事业', '官禄');
  return name;
}

ZiweiPalace _palaceNamed(ZiweiChartData data, List<String> names) {
  for (final palace in data.astrolabe.palaces) {
    final normalized = _modernPalaceName(palace.name);
    if (names.any((name) => normalized.contains(name))) return palace;
  }
  return data.astrolabe.palaces.firstWhere(
    (p) => p.earthlyBranch == data.astrolabe.soulPalaceBranch,
  );
}

ZiweiPalace? _natalCautionPalace(ZiweiChartData data) {
  for (final palace in data.astrolabe.palaces) {
    final stars = [
      ...palace.majorStars,
      ...palace.minorStars,
      ...palace.adjectiveStars
    ];
    if (stars.any((star) => star.mutagen == '忌')) return palace;
  }
  return null;
}

String _findStarPalace(ZiweiChartData data, String starName) {
  for (final palace in data.astrolabe.palaces) {
    final stars = [
      ...palace.majorStars,
      ...palace.minorStars,
      ...palace.adjectiveStars
    ];
    if (stars.any((star) => star.name == starName)) {
      final name = _modernPalaceName(palace.name);
      return name.endsWith('宫') ? name : '$name宫';
    }
  }
  return '流曜';
}
