import 'package:flutter/material.dart';
import 'package:xuanyu/core/theme/app_colors.dart';

import '../ziwei_four_pillars.dart';
import '../ziwei_models.dart';
import '../ziwei_timeline.dart';

// 晨光白玉色域：保留专业盘的精细层级，同时去除米灰与灰绿雾感。
const _chartSurface = Color(0xFFFFFFFF);
const _chartCenterSurface = Color(0xFFFAFEFD);
const _chartGrid = Color(0xFF91D9D3);
const _chartSelected = Color(0xFFFFF2D6);
const _chartBodyPalace = Color(0xFFF2EEFF);
const _chartInk = Color(0xFF193E46);
const _chartCinnabar = Color(0xFFE65F6A);
const _chartViolet = Color(0xFF7862C7);
const _chartBlue = Color(0xFF3F76D3);
const _chartJade = Color(0xFF169C92);
const _chartGold = Color(0xFFD5A744);

String _layerShort(ZiweiLayer layer) => switch (layer) {
      ZiweiLayer.natal => '本',
      ZiweiLayer.decadal => '大',
      ZiweiLayer.age => '小',
      ZiweiLayer.yearly => '年',
      ZiweiLayer.monthly => '月',
      ZiweiLayer.daily => '日',
      ZiweiLayer.hourly => '时',
    };

const _verticalAuxiliaryNames = <String>{
  '左辅',
  '右弼',
  '文昌',
  '文曲',
  '天魁',
  '天钺',
  '禄存',
  '天马',
  '擎羊',
  '陀罗',
  '火星',
  '铃星',
  '地空',
  '地劫',
};

String _palaceShortName(String name) {
  if (name.contains('命')) return '命';
  if (name.contains('兄弟')) return '兄';
  if (name.contains('夫妻')) return '夫';
  if (name.contains('子女')) return '子';
  if (name.contains('财帛')) return '财';
  if (name.contains('疾厄')) return '疾';
  if (name.contains('迁移')) return '迁';
  if (name.contains('仆役') || name.contains('交友')) return '友';
  if (name.contains('官禄') || name.contains('事业')) return '官';
  if (name.contains('田宅')) return '田';
  if (name.contains('福德')) return '福';
  if (name.contains('父母')) return '父';
  return name.isEmpty ? '' : name.substring(0, 1);
}

Color _layerColor(ZiweiLayer layer) => switch (layer) {
      ZiweiLayer.natal => _chartJade,
      ZiweiLayer.decadal => _chartInk,
      ZiweiLayer.age => _chartViolet,
      ZiweiLayer.yearly => _chartBlue,
      ZiweiLayer.monthly => const Color(0xFF4D8870),
      ZiweiLayer.daily => _chartCinnabar,
      ZiweiLayer.hourly => const Color(0xFF6F6888),
    };

Color _majorStarColor(String name) {
  if (const {'紫微', '天府', '天相'}.contains(name)) return _chartViolet;
  if (const {'太阳', '武曲', '七杀', '廉贞', '破军', '贪狼'}.contains(name)) {
    return _chartCinnabar;
  }
  if (const {'天机', '太阴', '巨门', '天同'}.contains(name)) {
    return _chartBlue;
  }
  return _chartInk;
}

class ZiweiChartBoard extends StatelessWidget {
  const ZiweiChartBoard({
    super.key,
    required this.data,
    required this.profile,
    required this.activeLayer,
    required this.selectedPalaceIndex,
    required this.onPalaceTap,
    this.onLayerChanged,
    this.showSurroundedLines = true,
    this.showBirthData = true,
  });

  final ZiweiChartData data;
  final ZiweiProfile profile;
  final ZiweiLayer activeLayer;
  final int selectedPalaceIndex;
  final ValueChanged<int> onPalaceTap;
  final ValueChanged<ZiweiLayer>? onLayerChanged;
  final bool showSurroundedLines;
  final bool showBirthData;

  static const Map<int, (int, int)> _positions = {
    3: (0, 0),
    4: (0, 1),
    5: (0, 2),
    6: (0, 3),
    2: (1, 0),
    7: (1, 3),
    1: (2, 0),
    8: (2, 3),
    0: (3, 0),
    11: (3, 1),
    10: (3, 2),
    9: (3, 3),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width * 1.34;
        final cellWidth = width / 4;
        final cellHeight = height / 4;
        final scale = width / 390;
        final scopes = _visibleScopes();
        return SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFF7FFFE)],
              ),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _chartGrid, width: .9),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  for (final palace in data.astrolabe.palaces)
                    _positionedPalace(
                      palace: palace,
                      effectiveMajorStars: data.effectiveMajorStarsFor(palace),
                      borrowsMajorStars: data.borrowsOppositeMajorStars(palace),
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                      scale: scale,
                      scopes: scopes,
                      activeLayer: activeLayer,
                      selected: palace.index == selectedPalaceIndex,
                      yearlyAges: ZiweiTimelineBuilder.yearlyAgesForPalace(
                        currentAge: data.horoscope.age.nominalAge,
                        currentPalaceIndex: data.horoscope.yearly.index,
                        palaceIndex: palace.index,
                      ),
                    ),
                  Positioned(
                    left: cellWidth,
                    top: cellHeight,
                    width: cellWidth * 2,
                    height: cellHeight * 2,
                    child: _CenterPanel(
                      showBirthData: showBirthData,
                      data: data,
                      profile: profile,
                      activeLayer: activeLayer,
                      onLayerChanged: onLayerChanged,
                      scale: scale,
                    ),
                  ),
                  if (showSurroundedLines)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: ValueKey(
                            'ziwei-surrounded-lines-'
                            '${activeLayer.name}-$selectedPalaceIndex',
                          ),
                          painter: _SurroundedPalacesPainter(
                            positions: _positions,
                            selectedPalaceIndex: selectedPalaceIndex,
                            cellWidth: cellWidth,
                            cellHeight: cellHeight,
                            color: _layerColor(activeLayer),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<(ZiweiLayer, ZiweiScope)> _visibleScopes() {
    final layers = switch (activeLayer) {
      ZiweiLayer.natal => const <ZiweiLayer>[],
      ZiweiLayer.decadal => const [ZiweiLayer.decadal],
      ZiweiLayer.age => const [ZiweiLayer.age],
      ZiweiLayer.yearly => const [ZiweiLayer.decadal, ZiweiLayer.yearly],
      ZiweiLayer.monthly => const [
          ZiweiLayer.decadal,
          ZiweiLayer.yearly,
          ZiweiLayer.monthly,
        ],
      ZiweiLayer.daily => const [
          ZiweiLayer.decadal,
          ZiweiLayer.yearly,
          ZiweiLayer.monthly,
          ZiweiLayer.daily,
        ],
      ZiweiLayer.hourly => const [
          ZiweiLayer.decadal,
          ZiweiLayer.yearly,
          ZiweiLayer.monthly,
          ZiweiLayer.daily,
          ZiweiLayer.hourly,
        ],
    };
    return [
      for (final layer in layers)
        if (data.horoscope.scopeFor(layer) case final scope?) (layer, scope),
    ];
  }

  Widget _positionedPalace({
    required ZiweiPalace palace,
    required List<ZiweiStar> effectiveMajorStars,
    required bool borrowsMajorStars,
    required double cellWidth,
    required double cellHeight,
    required double scale,
    required List<(ZiweiLayer, ZiweiScope)> scopes,
    required ZiweiLayer activeLayer,
    required bool selected,
    required List<int> yearlyAges,
  }) {
    final position = _positions[palace.index]!;
    return Positioned(
      left: position.$2 * cellWidth,
      top: position.$1 * cellHeight,
      width: cellWidth,
      height: cellHeight,
      child: _PalaceCell(
        palace: palace,
        effectiveMajorStars: effectiveMajorStars,
        borrowsMajorStars: borrowsMajorStars,
        scopes: scopes,
        activeLayer: activeLayer,
        scale: scale,
        selected: selected,
        yearlyAges: yearlyAges,
        professionalMode: profile.settings.professionalMode,
        showHoroscopeStars: profile.settings.showHoroscopeStars,
        onTap: () => onPalaceTap(palace.index),
      ),
    );
  }
}

class _PalaceCell extends StatelessWidget {
  const _PalaceCell({
    required this.palace,
    required this.effectiveMajorStars,
    required this.borrowsMajorStars,
    required this.scopes,
    required this.activeLayer,
    required this.scale,
    required this.selected,
    required this.yearlyAges,
    required this.professionalMode,
    required this.showHoroscopeStars,
    required this.onTap,
  });

  final ZiweiPalace palace;
  final List<ZiweiStar> effectiveMajorStars;
  final bool borrowsMajorStars;
  final List<(ZiweiLayer, ZiweiScope)> scopes;
  final ZiweiLayer activeLayer;
  final double scale;
  final bool selected;
  final List<int> yearlyAges;
  final bool professionalMode;
  final bool showHoroscopeStars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeScope = scopes.isEmpty ? null : scopes.last.$2;
    final flowStars =
        activeScope != null && activeScope.stars.length > palace.index
            ? activeScope.stars[palace.index]
            : const <ZiweiStar>[];
    final verticalAuxiliary = palace.minorStars
        .where((star) => _verticalAuxiliaryNames.contains(star.name));
    final visibleMinor = palace.minorStars
        .where((star) => !_verticalAuxiliaryNames.contains(star.name))
        .take(professionalMode ? 5 : 3);
    final visibleAdjective =
        palace.adjectiveStars.take(professionalMode ? 5 : 3);
    final cellColor = selected
        ? _chartSelected
        : palace.isBodyPalace
            ? _chartBodyPalace
            : _chartSurface;
    return Material(
      color: cellColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(2 * scale),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _chartGold : _chartGrid,
              width: selected ? 1.05 : .52,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  if (palace.isOriginalPalace) _microTag('来因', _chartViolet),
                  if (palace.isBodyPalace) _microTag('身', _chartGold),
                ],
              ),
              SizedBox(height: .5 * scale),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final star in effectiveMajorStars)
                          _starLine(star, major: true),
                        if (borrowsMajorStars)
                          Text(
                            '借对宫',
                            style: TextStyle(
                              fontSize: 6.8 * scale,
                              color: _chartBlue,
                            ),
                          ),
                        if (effectiveMajorStars.isEmpty)
                          Text(
                            '暂无主星',
                            style: TextStyle(
                              fontSize: 8 * scale,
                              color: AppColors.textHint,
                            ),
                          ),
                        for (final star in verticalAuxiliary)
                          _starLine(star, major: false),
                      ],
                    ),
                  ),
                  if (scopes.isNotEmpty) _scopeLabels(),
                ],
              ),
              _minorStars(visibleMinor),
              if (visibleAdjective.isNotEmpty)
                Text(
                  visibleAdjective.map((star) => star.name).join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 6.7 * scale,
                    height: 1.02,
                    color: _chartViolet,
                  ),
                ),
              if (showHoroscopeStars && flowStars.isNotEmpty)
                Text(
                  '${_layerShort(activeLayer)}曜 '
                  '${flowStars.take(3).map((star) => star.name).join(' ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 6.7 * scale,
                    height: 1.02,
                    fontWeight: FontWeight.w600,
                    color: _chartBlue,
                  ),
                ),
              const Spacer(),
              if (yearlyAges.isNotEmpty)
                Text(
                  '流年：${yearlyAges.take(5).join(',')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 6 * scale,
                    height: 1.05,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (palace.ages.isNotEmpty)
                Text(
                  '小限：${palace.ages.take(5).join(',')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 6 * scale,
                    height: 1.05,
                    color: AppColors.textSecondary,
                  ),
                ),
              SizedBox(height: 1 * scale),
              _palaceFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeLabels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final entry in scopes)
          if (entry.$2.palaceNames.length > palace.index)
            Text(
              '${_layerShort(entry.$1)}'
              '${_palaceShortName(entry.$2.palaceNames[palace.index])}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 7.2 * scale,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: _layerColor(entry.$1),
              ),
            ),
      ],
    );
  }

  Widget _palaceFooter() {
    return SizedBox(
      height: 22 * scale,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 21 * scale,
            child: Text(
              '${palace.boshi12}\n${palace.jiangqian12}\n${palace.suiqian12}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 5.7 * scale,
                height: 1.02,
                fontWeight: FontWeight.w600,
                color: _chartJade,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '大限 ${palace.decadal.startAge}～${palace.decadal.endAge}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 6.3 * scale,
                    height: 1,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${palace.name}${palace.isBodyPalace ? '·身' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10 * scale,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: _chartCinnabar,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 17 * scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  palace.changsheng12,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 6.1 * scale,
                    height: 1,
                    color: const Color(0xFF557078),
                  ),
                ),
                Text(
                  '${palace.heavenlyStem}${palace.earthlyBranch}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7.5 * scale,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _microTag(String text, Color color) {
    return Container(
      margin: EdgeInsets.only(left: 2 * scale),
      padding: EdgeInsets.symmetric(horizontal: 2.5 * scale, vertical: .5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 5.8 * scale,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _starLine(ZiweiStar star, {required bool major}) {
    final activeScope = scopes.isEmpty ? null : scopes.last.$2;
    final dynamicMutagen = activeScope?.mutagen.indexOf(star.name) ?? -1;
    final dynamicMutagenName =
        dynamicMutagen >= 0 ? const ['禄', '权', '科', '忌'][dynamicMutagen] : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            star.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: (major ? 10 : 8.2) * scale,
              height: 1,
              fontWeight: major ? FontWeight.w800 : FontWeight.w500,
              color: major ? _majorStarColor(star.name) : _chartInk,
            ),
          ),
        ),
        if (star.brightness.isNotEmpty)
          Text(
            star.brightness,
            style: TextStyle(
              fontSize: 6.1 * scale,
              color: AppColors.textHint,
            ),
          ),
        if (star.mutagen.isNotEmpty) _mutagen(star.mutagen, source: '本'),
        if (dynamicMutagenName.isNotEmpty)
          _mutagen(dynamicMutagenName, source: _layerShort(activeLayer)),
      ],
    );
  }

  Widget _minorStars(Iterable<ZiweiStar> stars) {
    return Text.rich(
      TextSpan(
        children: [
          for (final star in stars) ...[
            TextSpan(
              text: '${star.name}${star.brightness}',
              style: TextStyle(
                color: star.type == 'tough' ? _chartCinnabar : _chartInk,
              ),
            ),
            if (star.mutagen.isNotEmpty)
              TextSpan(
                text: '本${star.mutagen}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _mutagenColor(star.mutagen),
                ),
              ),
            if ((scopes.isEmpty
                    ? -1
                    : scopes.last.$2.mutagen.indexOf(star.name)) >=
                0)
              TextSpan(
                text: '${_layerShort(activeLayer)}'
                    '${const [
                  '禄',
                  '权',
                  '科',
                  '忌'
                ][scopes.last.$2.mutagen.indexOf(star.name)]}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _mutagenColor(
                    const [
                      '禄',
                      '权',
                      '科',
                      '忌'
                    ][scopes.last.$2.mutagen.indexOf(star.name)],
                  ),
                ),
              ),
            const TextSpan(text: ' '),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 7 * scale, height: 1.02),
    );
  }

  Widget _mutagen(String text, {required String source}) {
    final color = _mutagenColor(text);
    return Container(
      margin: EdgeInsets.only(left: 1.5 * scale),
      padding: EdgeInsets.symmetric(horizontal: 1.8 * scale),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$source$text',
        style: TextStyle(
          fontSize: 5.2 * scale,
          height: 1.25,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _mutagenColor(String text) => switch (text) {
        '禄' => _chartJade,
        '权' => _chartViolet,
        '科' => _chartBlue,
        '忌' => _chartCinnabar,
        _ => AppColors.textHint,
      };
}

class _SurroundedPalacesPainter extends CustomPainter {
  const _SurroundedPalacesPainter({
    required this.positions,
    required this.selectedPalaceIndex,
    required this.cellWidth,
    required this.cellHeight,
    required this.color,
  });

  final Map<int, (int, int)> positions;
  final int selectedPalaceIndex;
  final double cellWidth;
  final double cellHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Offset center(int index) {
      final position = positions[index]!;
      return Offset(
        (position.$2 + .5) * cellWidth,
        (position.$1 + .5) * cellHeight,
      );
    }

    final opposite = (selectedPalaceIndex + 6) % 12;
    final trineA = (selectedPalaceIndex + 4) % 12;
    final trineB = (selectedPalaceIndex + 8) % 12;
    final paint = Paint()
      ..color = _chartBlue.withValues(alpha: .43)
      ..strokeWidth = 1.05
      ..style = PaintingStyle.stroke;
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: .86)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(center(selectedPalaceIndex).dx, center(selectedPalaceIndex).dy)
      ..lineTo(center(trineA).dx, center(trineA).dy)
      ..lineTo(center(trineB).dx, center(trineB).dy)
      ..close();
    final oppositePath = Path()
      ..moveTo(center(selectedPalaceIndex).dx, center(selectedPalaceIndex).dy)
      ..lineTo(center(opposite).dx, center(opposite).dy);
    canvas
      ..drawPath(path, halo)
      ..drawPath(oppositePath, halo)
      ..drawPath(path, paint)
      ..drawPath(oppositePath, paint);

    final nodePaint = Paint()..color = _chartBlue.withValues(alpha: .72);
    for (final index in {selectedPalaceIndex, opposite, trineA, trineB}) {
      canvas.drawCircle(center(index), 2.2, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SurroundedPalacesPainter oldDelegate) =>
      selectedPalaceIndex != oldDelegate.selectedPalaceIndex ||
      cellWidth != oldDelegate.cellWidth ||
      cellHeight != oldDelegate.cellHeight ||
      color != oldDelegate.color;
}

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({
    required this.data,
    this.showBirthData = true,
    required this.profile,
    required this.activeLayer,
    required this.onLayerChanged,
    required this.scale,
  });

  final ZiweiChartData data;
  final bool showBirthData;
  final ZiweiProfile profile;
  final ZiweiLayer activeLayer;
  final ValueChanged<ZiweiLayer>? onLayerChanged;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final astro = data.astrolabe;
    final scope = data.horoscope.scopeFor(activeLayer);
    return Container(
      padding: EdgeInsets.fromLTRB(
        7 * scale,
        6 * scale,
        7 * scale,
        5 * scale,
      ),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment.topRight,
          radius: 1.15,
          colors: [Color(0xFFF2EEFF), _chartCenterSurface, Color(0xFFF0FFFC)],
          stops: [0, .48, 1],
        ),
        border: Border.all(color: _chartGrid, width: .48),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.center,
            child: Text(
              '${_yinYangGender(astro.chineseDate)} · '
              '${astro.fiveElementsClass}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5 * scale,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: 4 * scale),
          if (showBirthData) _line('公历', '${astro.solarDate} ${astro.time}'),
          if (showBirthData) _line('农历', astro.lunarDate),
          if (showBirthData) _line('节气四柱', ZiweiFourPillars.solarTerm(profile)),
          if (showBirthData)
            _line(
              '斗数四柱',
              '${astro.chineseDate}（${ZiweiFourPillars.chartBoundaryLabel(profile)}）',
            ),
          _line('命身', '命主${astro.soul} · 身主${astro.body}'),
          _line(
            '宫位',
            '命宫${astro.soulPalaceBranch} · 身宫${astro.bodyPalaceBranch}',
          ),
          const Spacer(),
          _mutagenLegend(scope),
          SizedBox(height: 5 * scale),
          _layerBar(),
        ],
      ),
    );
  }

  String _yinYangGender(String chineseDate) {
    final yearStem = chineseDate.trim().isEmpty ? '' : chineseDate.trim()[0];
    final yinYang = '甲丙戊庚壬'.contains(yearStem) ? '阳' : '阴';
    return '$yinYang${profile.gender}';
  }

  Widget _mutagenLegend(ZiweiScope? scope) {
    const entries = [
      ('禄', _chartJade),
      ('权', _chartViolet),
      ('科', _chartBlue),
      ('忌', _chartCinnabar),
    ];
    return Row(
      children: [
        Text(
          scope == null
              ? '本=生年四化 '
              : '本=生年 · ${_layerShort(activeLayer)}=${activeLayer.label} ',
          style: TextStyle(
            fontSize: 7.1 * scale,
            color: AppColors.textHint,
          ),
        ),
        for (final entry in entries)
          Padding(
            padding: EdgeInsets.only(right: 4 * scale),
            child: Text(
              entry.$1,
              style: TextStyle(
                fontSize: 7.3 * scale,
                fontWeight: FontWeight.w800,
                color: entry.$2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _layerBar() {
    const layers = ZiweiLayer.values;
    return SizedBox(
      height: 25 * scale,
      child: Row(
        children: [
          for (final layer in layers) Expanded(child: _layerButton(layer)),
        ],
      ),
    );
  }

  Widget _layerButton(ZiweiLayer layer) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onLayerChanged == null ? null : () => onLayerChanged!(layer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: EdgeInsets.all(.7 * scale),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activeLayer == layer
              ? layer == ZiweiLayer.natal
                  ? const Color(0xFFFFF2D6)
                  : const Color(0xFFDCF8F4)
              : Colors.white.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(3 * scale),
          border: activeLayer == layer
              ? Border.all(
                  color: layer == ZiweiLayer.natal ? _chartGold : _chartJade,
                  width: .7,
                )
              : null,
        ),
        child: Text(
          layer == ZiweiLayer.natal ? '本命' : layer.label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 7.8 * scale,
            fontWeight:
                activeLayer == layer ? FontWeight.w800 : FontWeight.w500,
            color: activeLayer == layer
                ? layer == ZiweiLayer.natal
                    ? const Color(0xFF9A6D16)
                    : _chartInk
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2 * scale),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(color: AppColors.textHint),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 8.2 * scale, height: 1.15),
      ),
    );
  }
}
