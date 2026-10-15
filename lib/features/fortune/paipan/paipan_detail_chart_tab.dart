/// Tab3：专业细盘（四柱表 + 胎命身 + 大运→流年→流月→流日→流时 层级选中）
library;
import 'dart:math' as math;
import 'package:bazi_core/bazi_core.dart' show PillarType;
import 'package:flutter/material.dart';
import 'utils/bazi_result.dart';
import 'utils/solar_terms_table.dart';
import 'share/paipan_shared.dart';

class PaipanDetailChartTab extends StatefulWidget {
  final BaziResult result;
  final bool isFemale;

  const PaipanDetailChartTab({super.key, required this.result, required this.isFemale});

  @override
  State<PaipanDetailChartTab> createState() => _PaipanDetailChartTabState();
}

class _PaipanDetailChartTabState extends State<PaipanDetailChartTab> {
  bool _showTaiMingShen = false;
  /// 选中小运时为 true，表格该列显示小运及计算结果；否则显示大运
  bool _selectedIsXiaoYun = false;
  int _selectedDaYunIndex = 0;
  int? _selectedLiuNianYear;
  int _selectedLiuYueIndex = 0;
  /// 流日未选时为 null；选中后为具体日期
  DateTime? _selectedLiuDay;
  /// 流时未选时为 null；选中后为 0–11
  int? _selectedLiuShiIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSelection());
    SolarTermsTable.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _initSelection() {
    final result = widget.result;
    final birthYear = result.solarDate.year;
    final now = DateTime.now();
    final xuSui = now.year - birthYear + 1;
    final startXuSui = result.daYunStartXuSui;
    final xiaoYunYears = (startXuSui - 1).clamp(0, 99);
    int idx = 0;
    for (int i = 0; i < result.daYun.length; i++) {
      if (xuSui >= startXuSui + i * 10 && xuSui < startXuSui + i * 10 + 10) {
        idx = i;
        break;
      }
    }
    final inXiaoYun = xuSui < startXuSui && xiaoYunYears > 0;
    final xiaoYunYearList = List.generate(xiaoYunYears, (i) => birthYear + i);
    final liuNianList = _liuNianYearsForDaYun(result, idx);
    final selYear = inXiaoYun
        ? (xiaoYunYearList.contains(now.year) ? now.year : (xiaoYunYearList.isNotEmpty ? xiaoYunYearList.first : null))
        : (liuNianList.contains(now.year) ? now.year : (liuNianList.isNotEmpty ? liuNianList.first : null));
    int yueIdx = 0;
    if (selYear != null) {
      final m = now.month;
      final d = now.day;
      if (m < 2 || (m == 2 && d < 4)) {
        yueIdx = 11;
      } else if (m < 3 || (m == 3 && d < 5)) yueIdx = 0;
      else if (m < 4 || (m == 4 && d < 5)) yueIdx = 1;
      else if (m < 5 || (m == 5 && d < 5)) yueIdx = 2;
      else if (m < 6 || (m == 6 && d < 6)) yueIdx = 3;
      else if (m < 7 || (m == 7 && d < 7)) yueIdx = 4;
      else if (m < 8 || (m == 8 && d < 7)) yueIdx = 5;
      else if (m < 9 || (m == 9 && d < 7)) yueIdx = 6;
      else if (m < 10 || (m == 10 && d < 8)) yueIdx = 7;
      else if (m < 11 || (m == 11 && d < 7)) yueIdx = 8;
      else if (m < 12 || (m == 12 && d < 7)) yueIdx = 9;
      else if (d < 22) yueIdx = 10;
      else yueIdx = 11;
    }
    if (!mounted) return;
    setState(() {
      _selectedIsXiaoYun = inXiaoYun;
      _selectedDaYunIndex = idx;
      _selectedLiuNianYear = selYear;
      _selectedLiuYueIndex = yueIdx;
      // 流日、流时初始不选中，表格不显示这两列；用户在下时间轴点选后再显示
      _selectedLiuDay = null;
      _selectedLiuShiIndex = null;
    });
  }

  List<int> _liuNianYearsForDaYun(BaziResult result, int daYunIndex) {
    final birthYear = result.solarDate.year;
    // 大运第 i 步对应年龄区间：起运虚岁 + i*10 ～ 起运虚岁 + i*10 + 9
    // 对应公历年份从「birthYear + 起运虚岁 - 1 + i*10」开始（该年虚岁 = 起运虚岁 + i*10）
    final start = birthYear + (result.daYunStartXuSui - 1) + daYunIndex * 10;
    return List.generate(10, (i) => start + i);
  }

  static const _jieQiNames = ['立春', '惊蛰', '清明', '立夏', '芒种', '小暑', '立秋', '白露', '寒露', '立冬', '小雪', '小寒'];

  (int, int) _jieQiMdForYear(int year, int index) => SolarTermsTable.getMd(year, index);

  DateTime _firstDayOfLiuYue(int year, int yueIndex) {
    final (m, d) = _jieQiMdForYear(year, yueIndex);
    if (m == 1 && yueIndex == 11) return DateTime(year - 1, 12, 7);
    return DateTime(year, m, d);
  }

  /// 流日列表：落在当前流月节令区间内 [本月节当日, 下一节当日)，与流月列对齐，不跨下一节气。
  List<DateTime> _liuRiDaysForYue(int year, int yueIndex) {
    final start = _firstDayOfLiuYue(year, yueIndex);
    final endIdx = (yueIndex + 1) % 12;
    // 下一「节」所在公历年：仅小寒→立春 跨年（endIdx 回到 0 且早于本月序）
    final endYear = endIdx <= yueIndex ? year + 1 : year;
    final (em, ed) = _jieQiMdForYear(endYear, endIdx);
    final end = DateTime(endYear, em, ed);
    final days = <DateTime>[];
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      days.add(d);
      if (days.length >= 35) break;
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final birthYear = result.solarDate.year;
    // 小运年份：1 岁～起运虚岁前一年，共 (daYunStartXuSui - 1) 年
    final xiaoYunYears = (result.daYunStartXuSui - 1).clamp(0, 99);
    final liuNianList = _selectedIsXiaoYun
        ? List.generate(xiaoYunYears, (i) => birthYear + i)
        : _liuNianYearsForDaYun(result, _selectedDaYunIndex);
    final selYear = _selectedLiuNianYear ?? (liuNianList.isNotEmpty ? liuNianList.first : null);
    final liuRiDays = selYear != null ? _liuRiDaysForYue(selYear, _selectedLiuYueIndex) : <DateTime>[];

    return Container(
      color: Colors.white,
      child: ListView(
        key: const ValueKey('paipan-detail-scroll'),
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          _detailTable(result, _showTaiMingShen, selYear, _selectedLiuDay),
          _detailJiaoYunBar(result, selYear),
          if (_showTaiMingShen)
            paipanFlatSection('胎命身', [
              _detailRow('胎元', result.taiYuanNayin.isEmpty ? result.taiYuan : '${result.taiYuan}（${result.taiYuanNayin}）'),
              _detailRow('命宫', result.mingGongNayin.isEmpty ? result.mingGong : '${result.mingGong}（${result.mingGongNayin}）'),
              _detailRow('身宫', result.shenGongNayin.isEmpty ? result.shenGong : '${result.shenGong}（${result.shenGongNayin}）'),
            ])
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return _buildTimelineBlock(
                  result, widget.isFemale, _selectedIsXiaoYun, liuNianList, selYear, liuRiDays, _selectedLiuDay,
                  contentAreaWidth: (w.isFinite && w > 0) ? w - _detailLabelColumnWidth : null,
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          _buildGanZhiLiuYiAndShenShaSections(result, widget.isFemale, _selectedIsXiaoYun, _selectedDaYunIndex, selYear, _selectedLiuYueIndex),
          const SizedBox(height: 24),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: PaipanDisclaimer()),
        ],
      ),
    );
  }

  /// 时间轴表格列数：标签列 + 数据列（取各层最大列数）
  int _timelineDataColumns(BaziResult result, int liuRiCount) {
    final daYunCols = 1 + result.daYun.length;
    return [daYunCols, 7, 12, liuRiCount.clamp(1, 99), 12].reduce(math.max);
  }

  /// 时间轴：普通 Column + Row 行列布局，行=大运、流年、流月、流日、流时，横向滚动；标签列宽与上面表格第一列一致(56)
  static const double _detailLabelColumnWidth = 40;

  /// 每行可见区平均 10 格，超过 10 格可横向滑动
  static const int _timelineParts = 10;

  Widget _buildTimelineBlock(BaziResult result, bool isFemale, bool isXiaoYun, List<int> liuNianList, int? selYear, List<DateTime> liuRiDays, DateTime? selDay, {double? contentAreaWidth}) {
    final td = paipanKShenFullMap[result.dayGan];
    final birthYear = result.solarDate.year;
    const ganList = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    final yearSeq = ganList.indexOf(result.yearGan);
    final shun = (isFemale && (yearSeq % 2 == 1)) || (!isFemale && (yearSeq % 2 == 0));

    const double scrollRowHeight = 92.0;

    /// 标签竖排：一字一行，行高与整行一致避免挤压
    const labelStyle = TextStyle(fontSize: _detailTableFontSize * 1.25, fontWeight: FontWeight.normal, color: Colors.black);
    Widget labelCell(String text, {Color? backgroundColor}) => SizedBox(
      height: scrollRowHeight,
      width: _detailLabelColumnWidth,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: backgroundColor ?? paipanSectionHeaderBg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: text.split('').map((c) => Text(c, style: labelStyle)).toList(),
        ),
      ),
    );

    Widget dataCell(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      alignment: Alignment.center,
      child: child,
    );

    Widget dataCellTall(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      alignment: Alignment.center,
      child: child,
    );

    /// 仅对干支两行加蓝色高亮，不涂满整格
    Widget pillarHighlight(Widget pillar, bool selected) => selected
        ? Container(
            decoration: BoxDecoration(color: paipanTimelineSelectedBg, borderRadius: BorderRadius.circular(6)),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: pillar,
          )
        : pillar;

    Widget emptySlot(Color rowColor) => Container(color: rowColor);

    // 大运一行：每列一格，格内为 年龄 + 年份 + 干支（小运列为 年龄 + 年份 + 小运）
    final n = result.daYunStartXuSui;
    // 小运列：1 岁～起运虚岁前一年，共 (n - 1) 年
    final firstAge = n <= 1 ? '1岁' : '1-${n - 1}岁';
    final firstYear = result.solarDate.year;

    Widget daYunCell(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      alignment: Alignment.center,
      child: child,
    );

    List<Widget> rowDaYunCells = [
      SizedBox(
        height: scrollRowHeight,
        width: _detailLabelColumnWidth,
        child: Container(
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: '大运'.split('').map((c) => Text(c, style: labelStyle)).toList(),
          ),
        ),
      ),
      GestureDetector(
        onTap: () => setState(() {
          _selectedIsXiaoYun = true;
          _selectedDaYunIndex = 0;
          _selectedLiuNianYear = result.solarDate.year;
        }),
        child: daYunCell(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(firstAge, style: const TextStyle(fontSize: 9, color: Colors.black)),
                  Text('$firstYear', style: const TextStyle(fontSize: 9, color: Colors.black)),
                  pillarHighlight(
                    Column(mainAxisSize: MainAxisSize.min, children: '小运'.split('').map((c) => Text(c, style: const TextStyle(fontSize: 14, color: paipanGrey))).toList()),
                    _selectedIsXiaoYun,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
    // 大运固定 10 列（含小运）：1 小运 + 最多 9 大运，后面不再展示
    const maxDaYunCols = 9;
    for (int i = 0; i < result.daYun.length && i < maxDaYunCols; i++) {
      final ageRange = i < result.daYunAgeRanges.length ? result.daYunAgeRanges[i] : '${i + 1}运';
      final yr = _liuNianYearsForDaYun(result, i).isNotEmpty ? _liuNianYearsForDaYun(result, i).first : result.solarDate.year;
      final gz = result.daYun[i];
      final gan = gz.isNotEmpty ? gz[0] : '';
      final zhi = gz.length > 1 ? gz.substring(1) : '';
      final ganShen = td != null && gan.isNotEmpty ? paipanShenFullName(td[gan]) : null;
      final zhiShen = td != null && zhi.isNotEmpty && paipanZhi5ListFirst[zhi] != null ? paipanShenFullName(td[paipanZhi5ListFirst[zhi]!]) : null;
      final selected = !_selectedIsXiaoYun && i == _selectedDaYunIndex;
      rowDaYunCells.add(
        GestureDetector(
          onTap: () => setState(() {
            _selectedIsXiaoYun = false;
            _selectedDaYunIndex = i;
            final years = _liuNianYearsForDaYun(result, i);
            _selectedLiuNianYear = years.isNotEmpty ? years.first : null;
          }),
          child: daYunCell(
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(ageRange, style: const TextStyle(fontSize: 9, color: Colors.black)),
                    Text('$yr', style: const TextStyle(fontSize: 9, color: Colors.black)),
                    pillarHighlight(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text.rich(TextSpan(
                            children: [
                              TextSpan(text: gan, style: TextStyle(fontSize: paipanKTimelinePillarFontSize, color: paipanGanColor(gan))),
                              TextSpan(text: paipanShenShort(ganShen), style: const TextStyle(fontSize: paipanKTimelinePillarShenFontSize, color: Colors.black)),
                            ],
                          )),
                          Text.rich(TextSpan(
                            children: [
                              TextSpan(text: zhi, style: TextStyle(fontSize: paipanKTimelinePillarFontSize, color: paipanZhiColor(zhi))),
                              TextSpan(text: paipanShenShort(zhiShen), style: const TextStyle(fontSize: paipanKTimelinePillarShenFontSize, color: Colors.black)),
                            ],
                          )),
                        ],
                      ),
                      selected,
                    ),
                  ],
                ),
              ),
            ),
        ),
        ),
      );
    }

    // 流年行：按公历年份六十甲子顺排计算流年干支，再按所选大运区间展示
    List<Widget> rowLiuNianCells = [labelCell('流年')];
    for (int j = 0; j < liuNianList.length; j++) {
      final y = liuNianList[j];
      final age = y - birthYear + 1;
      final gzShishen = liuNianGanZhiFromMingPan(birthYear, y, result.yearGan, result.yearZhi, shun);
      final ganShen = td != null ? paipanShenFullName(td[gzShishen[0]]) : null;
      final zhiShen = td != null && gzShishen.length > 1 && paipanZhi5ListFirst[gzShishen.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gzShishen.substring(1)]!]) : null;
      rowLiuNianCells.add(
        GestureDetector(
          onTap: () => setState(() => _selectedLiuNianYear = y),
          child: dataCell(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$age岁', style: const TextStyle(fontSize: 9, color: Colors.black)),
                    Text('$y', style: const TextStyle(fontSize: 9, color: Colors.black)),
                    pillarHighlight(paipanTimelinePillarTextTwoLines(gzShishen, ganShen, zhiShen, fontSize: paipanKTimelinePillarFontSize, shenFontSize: paipanKTimelinePillarShenFontSize), y == (_selectedLiuNianYear ?? selYear)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 流月一行：每格内 节气+日期、干支，行高与大运一致
    List<Widget> rowLiuYueCells = [labelCell('流月', backgroundColor: Colors.white)];
    if (selYear != null) {
      for (int j = 0; j < 12; j++) {
        final (m, d) = _jieQiMdForYear(selYear, j);
        final gz = ganZhiForLiuYue(selYear, j);
        final ganShen = td != null ? paipanShenFullName(td[gz[0]]) : null;
        final zhiShen = td != null && gz.length > 1 && paipanZhi5ListFirst[gz.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gz.substring(1)]!]) : null;
        rowLiuYueCells.add(
          GestureDetector(
            onTap: () => setState(() => _selectedLiuYueIndex = j),
            child: dataCellTall(
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_jieQiNames[j], style: const TextStyle(fontSize: 9, color: Colors.black)),
                      Text('$m.$d', style: const TextStyle(fontSize: 9, color: Colors.black)),
                      pillarHighlight(paipanTimelinePillarTextTwoLines(gz, ganShen, zhiShen, fontSize: paipanKTimelinePillarFontSize, shenFontSize: paipanKTimelinePillarShenFontSize), j == _selectedLiuYueIndex),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // 流日行
    List<Widget> rowLiuRiCells = [labelCell('流日')];
    if (selYear != null && liuRiDays.isNotEmpty) {
      for (final d in liuRiDays) {
        final gz = dayGanZhiFromDate(d);
        final ganShen = td != null ? paipanShenFullName(td[gz[0]]) : null;
        final zhiShen = td != null && gz.length > 1 && paipanZhi5ListFirst[gz.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gz.substring(1)]!]) : null;
        final selected = selDay != null && d.year == selDay.year && d.month == selDay.month && d.day == selDay.day;
        rowLiuRiCells.add(
          GestureDetector(
            onTap: () => setState(() => _selectedLiuDay = d),
            child: dataCell(
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${d.month}.${d.day}', style: const TextStyle(fontSize: 9, color: Colors.black)),
                      pillarHighlight(paipanTimelinePillarTextTwoLines(gz, ganShen, zhiShen, fontSize: paipanKTimelinePillarFontSize, shenFontSize: paipanKTimelinePillarShenFontSize), selected),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // 流时行：行高与大运一致，背景白。
    // 需求：默认隐藏，仅当选中流日后（selDay != null）才显示对应的流时。
    List<Widget> rowLiuShiCells = [];
    if (selDay != null) {
      final dayGan = dayGanZhiFromDate(selDay)[0];
      rowLiuShiCells = [labelCell('流时', backgroundColor: Colors.white)];
      for (int j = 0; j < 12; j++) {
        final gz = ganZhiForLiuShi(dayGan, j);
        final ganShen = td != null ? paipanShenFullName(td[gz[0]]) : null;
        final zhiShen = td != null && gz.length > 1 && paipanZhi5ListFirst[gz.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gz.substring(1)]!]) : null;
        rowLiuShiCells.add(
          GestureDetector(
            onTap: () => setState(() => _selectedLiuShiIndex = j),
            child: dataCellTall(
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${j + 1}时', style: const TextStyle(fontSize: 9, color: Colors.black)),
                      pillarHighlight(
                        paipanTimelinePillarTextTwoLines(
                          gz,
                          ganShen,
                          zhiShen,
                          fontSize: paipanKTimelinePillarFontSize,
                          shenFontSize: paipanKTimelinePillarShenFontSize,
                        ),
                        j == _selectedLiuShiIndex,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    Widget rowBorder() => Container(height: 0.5, color: paipanTableBorderColor);

    /// 每行：左侧标签 + 右侧平均 10 格可见，超过 10 格可横向滑动
    Widget scrollRow(List<Widget> cells, Color rowColor) {
      if (cells.isEmpty) return const SizedBox.shrink();
      List<Widget> content = cells.sublist(1);
      if (content.length > _timelineParts) {
        final cellWidth = (contentAreaWidth ?? 320) / _timelineParts;
        return SizedBox(
          height: scrollRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cells.first,
              Expanded(
                child: Container(
                  color: rowColor,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: content.map((c) => SizedBox(width: cellWidth, child: c)).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      while (content.length < _timelineParts) {
        content.add(emptySlot(rowColor));
      }
      return SizedBox(
        height: scrollRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cells.first,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth = constraints.maxWidth > 0 ? constraints.maxWidth / _timelineParts : 64.0;
                  return Container(
                    color: rowColor,
                    child: Row(
                      children: content.map((c) => SizedBox(width: cellWidth, child: c)).toList(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          scrollRow(rowDaYunCells, Colors.white),
          rowBorder(),
          scrollRow(rowLiuNianCells, paipanSectionHeaderBg),
          rowBorder(),
          scrollRow(rowLiuYueCells, Colors.white),
          rowBorder(),
          scrollRow(rowLiuRiCells, paipanSectionHeaderBg),
          if (rowLiuShiCells.isNotEmpty) ...[
            rowBorder(),
            scrollRow(rowLiuShiCells, Colors.white),
          ],
        ],
      ),
    );
  }

  Widget _buildLiuNianRow(BaziResult result, bool isFemale, List<int> years, int? selYear) {
    if (years.isEmpty) return const Text('—', style: TextStyle(fontSize: 12, color: paipanGrey));
    final birthYear = result.solarDate.year;
    const ganList = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    final shun = (isFemale && (ganList.indexOf(result.yearGan) % 2 == 1)) || (!isFemale && (ganList.indexOf(result.yearGan) % 2 == 0));
    final td = paipanKShenFullMap[result.dayGan];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: years.map((y) {
          final gzMingPan = liuNianGanZhiFromMingPan(birthYear, y, result.yearGan, result.yearZhi, shun);
          final ganShen = td != null ? paipanShenFullName(td[gzMingPan[0]]) : null;
          final zhiShen = td != null && gzMingPan.length > 1 && paipanZhi5ListFirst[gzMingPan.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gzMingPan.substring(1)]!]) : null;
          final age = y - birthYear + 1;
          final selected = y == selYear;
          return GestureDetector(
            onTap: () => setState(() => _selectedLiuNianYear = y),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? paipanTimelineSelectedBg : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$y $age岁', style: const TextStyle(fontSize: 10, color: Colors.black)),
                  paipanTimelinePillarText(gzMingPan, ganShen, zhiShen, fontSize: 11),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLiuYueRow(BaziResult result, int? selYear) {
    if (selYear == null) return const Text('—', style: TextStyle(fontSize: 12, color: paipanGrey));
    final td = paipanKShenFullMap[result.dayGan];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(12, (i) {
          final gz = ganZhiForLiuYue(selYear, i);
          final ganShen = td != null ? paipanShenFullName(td[gz[0]]) : null;
          final zhiShen = td != null && gz.length > 1 && paipanZhi5ListFirst[gz.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gz.substring(1)]!]) : null;
          final (m, d) = _jieQiMdForYear(selYear, i);
          final selected = i == _selectedLiuYueIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedLiuYueIndex = i),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? paipanTimelineSelectedBg : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_jieQiNames[i], style: const TextStyle(fontSize: 9, color: Colors.black)),
                  Text('$m.$d', style: const TextStyle(fontSize: 9, color: Colors.black)),
                  paipanTimelinePillarText(gz, ganShen, zhiShen, fontSize: 10),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLiuRiRow(BaziResult result, int? selYear, List<DateTime> days, DateTime? selDay) {
    if (selYear == null || days.isEmpty) return const Text('—', style: TextStyle(fontSize: 12, color: paipanGrey));
    final td = paipanKShenFullMap[result.dayGan];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: days.map((d) {
          final gz = dayGanZhiFromDate(d);
          final ganShen = td != null ? paipanShenFullName(td[gz[0]]) : null;
          final zhiShen = td != null && gz.length > 1 && paipanZhi5ListFirst[gz.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gz.substring(1)]!]) : null;
          final selected = selDay != null && d.year == selDay.year && d.month == selDay.month && d.day == selDay.day;
          return GestureDetector(
            onTap: () => setState(() => _selectedLiuDay = d),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? paipanTimelineSelectedBg : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${d.month}.${d.day}', style: const TextStyle(fontSize: 9, color: Colors.black)),
                  paipanTimelinePillarText(gz, ganShen, zhiShen, fontSize: 10),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static const _shiNames = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

  Widget _buildLiuShiRow(BaziResult result, DateTime? selDay) {
    // 默认隐藏流时：仅在选中了具体流日后才显示对应流时行
    if (selDay == null) {
      return const SizedBox.shrink();
    }
    final dayGan = dayGanZhiFromDate(selDay)[0];
    final td = paipanKShenFullMap[result.dayGan];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(12, (i) {
          final gz = ganZhiForLiuShi(dayGan, i);
          final ganShen = td != null ? paipanShenFullName(td[gz[0]]) : null;
          final zhiShen = td != null && gz.length > 1 && paipanZhi5ListFirst[gz.substring(1)] != null ? paipanShenFullName(td[paipanZhi5ListFirst[gz.substring(1)]!]) : null;
          final selected = i == _selectedLiuShiIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedLiuShiIndex = i),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? paipanTimelineSelectedBg : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${i + 1}时', style: const TextStyle(fontSize: 9, color: Colors.black)),
                  paipanTimelinePillarText(gz, ganShen, zhiShen, fontSize: 10),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  static const double _detailTableFontSize = 12;
  /// 普通单元格右侧线（当前仅时柱后竖线显示，用 _afterSiZhuBorderSide）
  static const _dCellBorderSide = BorderSide(color: paipanTableBorderColor, width: 0.5);
  /// 四柱与后面大运/小运/胎元之间的竖线（加深）
  static const _afterSiZhuBorderSide = BorderSide(color: paipanTableBorderColor, width: 0.5);
  /// 专业细盘：时柱后竖线；非胎命身时 9 列（大运/流年/流月/流日/流时）
  static const _detailRightBorders4 = [false, false, false, false, true, false, false, false];
  static const _detailRightBorders9 = [false, false, false, false, true, false, false, false, false, false];

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.black, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.black, fontSize: 13))),
        ],
      ),
    );
  }

  /// 专业细盘：干支留意、四柱神煞、大运神煞、流年神煞、流月神煞 五个模块
  Widget _buildGanZhiLiuYiAndShenShaSections(
    BaziResult result,
    bool isFemale,
    bool isXiaoYun,
    int selectedDaYunIndex,
    int? selYear,
    int selectedLiuYueIndex,
  ) {
    final daYunGanZhi = isXiaoYun ? result.xiaoYun : result.daYun[selectedDaYunIndex];
    final birthYear = result.solarDate.year;
    const ganList = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    final yearSeq = ganList.indexOf(result.yearGan);
    final shun = (isFemale && (yearSeq % 2 == 1)) || (!isFemale && (yearSeq % 2 == 0));
    final liuNianGanZhi = selYear != null
        ? (isXiaoYun ? ganZhiForLiuNian(selYear) : liuNianGanZhiFromMingPan(birthYear, selYear, result.yearGan, result.yearZhi, shun))
        : '';
    final liuYueGanZhi = selYear != null ? ganZhiForLiuYue(selYear, selectedLiuYueIndex) : '';

    final fourPillarShenSha = <Widget>[];
    for (int i = 0; i < 4; i++) {
      final gz = '${result.gans[i]}${result.zhis[i]}';
      final ss = result.shenSha[i].isEmpty ? '—' : result.shenSha[i].join(' ');
      fourPillarShenSha.add(_detailRow(gz, ss));
    }

    final yearNayin = result.pillarNayins.isNotEmpty ? result.pillarNayins[0] : '';
    final daYunShenSha = daYunGanZhi.length >= 2
        ? computeShenShaForExtraPillar(
            result,
            daYunGanZhi[0],
            daYunGanZhi.substring(1),
            yearNayin: yearNayin,
            isFemale: isFemale,
            baziCoreExtraPillar: PillarType.decade,
          )
        : <String>[];
    final liuNianShenSha = liuNianGanZhi.length >= 2
        ? computeShenShaForExtraPillar(
            result,
            liuNianGanZhi[0],
            liuNianGanZhi.substring(1),
            yearNayin: yearNayin,
            isFemale: isFemale,
            baziCoreExtraPillar: PillarType.flowYear,
          )
        : <String>[];
    final liuYueShenSha = liuYueGanZhi.length >= 2
        ? computeShenShaForExtraPillar(
            result,
            liuYueGanZhi[0],
            liuYueGanZhi.substring(1),
            yearNayin: yearNayin,
            isFemale: isFemale,
            baziCoreExtraPillar: PillarType.flowMonth,
          )
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        paipanFlatSection('干支留意', paipanBuildGanZhiLiuYiContent(result, isFemale, daYunGanZhi, liuNianGanZhi, liuYueGanZhi)),
        paipanFlatSection('四柱神煞', fourPillarShenSha),
        paipanFlatSection('大运神煞', [
          _detailRow(daYunGanZhi, daYunShenSha.isEmpty ? '—' : daYunShenSha.join(' ')),
        ]),
        paipanFlatSection('流年神煞', [
          _detailRow(liuNianGanZhi.isEmpty ? '—' : liuNianGanZhi, liuNianShenSha.isEmpty ? '—' : liuNianShenSha.join(' ')),
        ]),
        paipanFlatSection('流月神煞', [
          _detailRow(liuYueGanZhi.isEmpty ? '—' : liuYueGanZhi, liuYueShenSha.isEmpty ? '—' : liuYueShenSha.join(' ')),
        ]),
      ],
    );
  }

  Widget _detailTable(BaziResult result, bool showTaiMingShen, int? selYear, DateTime? selDay) {
    if (showTaiMingShen) {
      final colLabels = ['年柱', '月柱', '日柱', '时柱', '胎元', '命宫', '身宫'];
      final mainStars = <String>[...result.detailMainStars.take(4), result.taiYuan, result.mingGong, result.shenGong];
      final gans = <String>[...result.detailGans.take(4), result.taiYuan[0], result.mingGong[0], result.shenGong[0]];
      final zhis = <String>[...result.detailZhis.take(4), result.taiYuan[1], result.mingGong[1], result.shenGong[1]];
      final zhiCang = <List<String>>[...result.detailZhiCangGanWithShen.take(4), ...result.taiMingShenZhiCangGanWithShen];
      final xingYun = <String>[...result.detailXingYun.take(4), ...result.taiMingShenXingYun];
      final ziZuo = <String>[...result.detailZiZuo.take(4), ...result.taiMingShenZiZuo];
      final empties = <String>[...result.detailPillarEmpties.take(4), ...result.taiMingShenEmpties];
      final nayins = <String>[
        ...result.detailPillarNayins.take(4),
        result.taiYuanNayin.isEmpty ? '—' : result.taiYuanNayin,
        result.mingGongNayin.isEmpty ? '—' : result.mingGongNayin,
        result.shenGongNayin.isEmpty ? '—' : result.shenGongNayin,
      ];
      return _detailTableBody(colLabels, mainStars, gans, zhis, zhiCang, xingYun, ziZuo, empties, nayins, _detailRightBorders4);
    }
    final isXiaoYun = _selectedIsXiaoYun;
    final daYunGanZhi = isXiaoYun ? result.xiaoYun : result.daYun[_selectedDaYunIndex];
    final birthYear = result.solarDate.year;
    const ganList = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    final yearSeq = ganList.indexOf(result.yearGan);
    final shun = (widget.isFemale && (yearSeq % 2 == 1)) || (!widget.isFemale && (yearSeq % 2 == 0));
    final liuNianGanZhi = selYear != null
        ? (isXiaoYun ? ganZhiForLiuNian(selYear) : liuNianGanZhiFromMingPan(birthYear, selYear, result.yearGan, result.yearZhi, shun))
        : '';
    final liuYueGanZhi = selYear != null ? ganZhiForLiuYue(selYear, _selectedLiuYueIndex) : '';
    final liuRiGanZhi = selDay != null ? dayGanZhiFromDate(selDay) : '';
    final liuShiGanZhi = _selectedLiuShiIndex != null
        ? ganZhiForLiuShi(liuRiGanZhi.isNotEmpty ? liuRiGanZhi[0] : result.dayGan, _selectedLiuShiIndex!)
        : '';
    final sel = buildDetailTableForSelection(
      result,
      widget.isFemale,
      daYunGanZhi,
      liuNianGanZhi,
      liuYueGanZhi,
      liuRiGanZhi,
      liuShiGanZhi,
    );
    final hasLiuRi = selDay != null;
    final hasLiuShi = _selectedLiuShiIndex != null;
    final nCols = 7 + (hasLiuRi ? 1 : 0) + (hasLiuShi ? 1 : 0);
    final colLabels = [
      '年柱', '月柱', '日柱', '时柱', isXiaoYun ? '小运' : '大运', '流年', '流月',
      if (hasLiuRi) '流日',
      if (hasLiuShi) '流时',
    ];
    final rightBorders = [false, false, false, false, true, false, false, ...List.filled(nCols + 1 - 7, false)];
    return _detailTableBody(
      colLabels,
      sel.mainStars.sublist(0, nCols),
      sel.gans.sublist(0, nCols),
      sel.zhis.sublist(0, nCols),
      sel.zhiCangGanWithShen.sublist(0, nCols),
      sel.xingYun.sublist(0, nCols),
      sel.ziZuo.sublist(0, nCols),
      sel.empties.sublist(0, nCols),
      sel.nayins.sublist(0, nCols),
      rightBorders,
    );
  }

  Widget _detailTableBody(
    List<String> colLabels,
    List<String> mainStars,
    List<String> gans,
    List<String> zhis,
    List<List<String>> zhiCang,
    List<String> xingYun,
    List<String> ziZuo,
    List<String> empties,
    List<String> nayins,
    List<bool> rightBorders,
  ) {
    final nCols = colLabels.length;
    return Table(
      columnWidths: Map<int, TableColumnWidth>.fromIterable(List.generate(nCols + 1, (i) => i), value: (i) => i == 0 ? const FixedColumnWidth(56) : const FlexColumnWidth(1)),
      border: const TableBorder(),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: paipanSectionHeaderBg),
          children: [
            _dCell('日期', isHeader: true, rightBorder: rightBorders[0]),
            ...List.generate(nCols, (i) => _dCell(colLabels[i], isHeader: true, rightBorder: rightBorders[i + 1], rightBorderAfterSiZhu: i == 4)),
          ],
        ),
        _dTableRow('主星', mainStars, rightBorders),
        TableRow(
          decoration: const BoxDecoration(color: paipanSectionHeaderBg),
          children: [
            _dCell('天干', isHeader: true, fontSize: _detailTableFontSize * 1.25, rightBorder: rightBorders[0]),
            ...List.generate(nCols, (i) => _dCell(gans[i], color: paipanGanColor(gans[i]), fontSize: _detailTableFontSize * 2, rightBorder: rightBorders[i + 1], rightBorderAfterSiZhu: i == 4)),
          ],
        ),
        TableRow(
          decoration: const BoxDecoration(color: paipanSectionHeaderBg),
          children: [
            _dCell('地支', isHeader: true, fontSize: _detailTableFontSize * 1.25, rightBorder: rightBorders[0]),
            ...List.generate(nCols, (i) => _dCell(zhis[i], color: paipanZhiColor(zhis[i]), fontSize: _detailTableFontSize * 2, rightBorder: rightBorders[i + 1], rightBorderAfterSiZhu: i == 4)),
          ],
        ),
        TableRow(
          children: [
            _dCell('藏干', isHeader: true, fontSize: _detailTableFontSize * 1.25, rightBorder: rightBorders[0]),
            ...List.generate(nCols, (i) => _dCellWithChild(paipanColoredZhiCangText((zhiCang.length > i ? zhiCang[i] : <String>[]).join('\n'), _detailTableFontSize - 2), rightBorder: rightBorders[i + 1], rightBorderAfterSiZhu: i == 4)),
          ],
        ),
        _dTableRow('星运', xingYun, rightBorders, rowBg: true),
        _dTableRow('自坐', ziZuo, rightBorders),
        _dTableRow('空亡', empties, rightBorders, rowBg: true),
        _dTableRow('纳音', nayins, rightBorders, contentFontSize: _detailTableFontSize - 1),
      ],
    );
  }

  /// 交运一行：左出生/交运各一行且完整显示，中胎命身 Column 上下两行居中，右年龄/司令 Column 居中；年龄随选中的大运/流年变化
  Widget _detailJiaoYunBar(BaziResult result, int? selYear) {
    final leftChildren = <Widget>[];
    const textStyle = TextStyle(fontSize: 11, color: Colors.black87);
    if (result.daYunStart.isNotEmpty) {
      leftChildren.add(Text(result.daYunStart, style: textStyle, softWrap: true, overflow: TextOverflow.visible));
    }
    if (result.jiaoYun.isNotEmpty) {
      leftChildren.add(Text('交运 ${result.jiaoYun}', style: textStyle, softWrap: true, overflow: TextOverflow.visible));
    }
    if (leftChildren.isEmpty) leftChildren.add(const Text('—', style: TextStyle(fontSize: 11, color: paipanGrey)));
    final birthYear = result.solarDate.year;
    final ageStr = selYear != null ? '${selYear - birthYear + 1}岁' : '1岁';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      color: paipanSectionHeaderBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: leftChildren,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Switch(
                  value: _showTaiMingShen,
                  onChanged: (v) => setState(() => _showTaiMingShen = v),
                  activeThumbColor: paipanPurple,
                ),
                Transform.translate(
                  offset: const Offset(0, -10),
                  child: const Text('胎命身', style: TextStyle(fontSize: 13, color: paipanGrey)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(ageStr, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                Text('司令 ${result.siLing.isEmpty ? '—' : result.siLing}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dCell(String text, {bool isHeader = false, Color? color, double? fontSize, bool rightBorder = true, bool rightBorderAfterSiZhu = false}) {
    final side = rightBorderAfterSiZhu ? _afterSiZhuBorderSide : _dCellBorderSide;
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize ?? _detailTableFontSize,
          fontWeight: FontWeight.normal,
          color: color ?? Colors.black,
        ),
      ),
    );
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: rightBorder
          ? Container(decoration: BoxDecoration(border: Border(right: side)), child: content)
          : content,
    );
  }

  Widget _dCellWithChild(Widget child, {bool rightBorder = true, bool rightBorderAfterSiZhu = false}) {
    final side = rightBorderAfterSiZhu ? _afterSiZhuBorderSide : _dCellBorderSide;
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: rightBorder
            ? Container(decoration: BoxDecoration(border: Border(right: side)), child: Center(child: child))
            : Center(child: child),
      ),
    );
  }

  TableRow _dTableRow(String label, List<String> values, List<bool> rightBorders, {bool rowBg = false, double? contentFontSize}) {
    final list = values.toList();
    final nCols = rightBorders.length - 1;
    final fs = contentFontSize ?? _detailTableFontSize;
    return TableRow(
      decoration: rowBg ? const BoxDecoration(color: paipanSectionHeaderBg) : null,
      children: [
        _dCell(label, isHeader: true, fontSize: _detailTableFontSize * 1.25, rightBorder: rightBorders[0], rightBorderAfterSiZhu: false),
        ...List.generate(nCols, (i) => _dCell(list.length > i ? list[i] : '', rightBorder: rightBorders[i + 1], rightBorderAfterSiZhu: i == 4, fontSize: fs)),
      ],
    );
  }

  Widget _liuNianRow(BaziResult result) {
    final birthYear = result.solarDate.year;
    final now = DateTime.now().year;
    final years = List.generate(6, (i) => now + i - 2).where((y) => y >= birthYear).take(6).toList();
    if (years.isEmpty) return const Text('—', style: TextStyle(fontSize: 12, color: paipanGrey));
    const ganList = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    const zhiList = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
    final td = paipanKShenFullMap[result.dayGan];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: years.map((y) {
        final idx = ((y - 4) % 60 + 60) % 60;
        final gan = ganList[idx % 10];
        final zhi = zhiList[idx % 12];
        final ganShen = td != null ? paipanShenFullName(td[gan]) : '';
        final zhiShen = td != null && paipanZhi5ListFirst[zhi] != null ? paipanShenFullName(td[paipanZhi5ListFirst[zhi]!]) : '';
        final age = y - birthYear + 1;
        return SizedBox(
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$y $age岁', style: const TextStyle(fontSize: 10, color: paipanGrey)),
              Text('$gan$ganShen $zhi$zhiShen', style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _liuYueRow(BaziResult result) {
    const terms = ['立春', '惊蛰', '清明', '立夏', '芒种', '小暑', '立秋', '白露', '寒露', '立冬', '小雪', '大雪'];
    const dates = ['2.4', '3.5', '4.5', '5.5', '6.5', '7.7', '8.7', '9.7', '10.8', '11.7', '12.7', '1.5'];
    const ganList = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    const zhiList = ['寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥', '子', '丑'];
    final yinGanIdx = (ganList.indexOf(result.yearGan) * 2 + 2) % 10;
    final td = paipanKShenFullMap[result.dayGan];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(12, (i) {
        final gan = ganList[(yinGanIdx + i) % 10];
        final zhi = zhiList[i];
        final ganShen = td != null ? paipanShenFullName(td[gan]) : '';
        final zhiShen = td != null && paipanZhi5ListFirst[zhi] != null ? paipanShenFullName(td[paipanZhi5ListFirst[zhi]!]) : '';
        return SizedBox(
          width: 68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${terms[i]} ${dates[i]}', style: const TextStyle(fontSize: 9, color: Colors.black)),
              Text('$gan$ganShen $zhi$zhiShen', style: const TextStyle(fontSize: 10)),
            ],
          ),
        );
      }),
    );
  }

}
