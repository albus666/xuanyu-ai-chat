import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import '../../../../core/theme/app_colors.dart';
import '../utils/date_util.dart';

// 使用 App 国风主题色
const _purple = AppColors.primary;
const _purplePill = AppColors.primaryLight;
const _grey = AppColors.textHint;
const _greyText = AppColors.textSecondary;
const _wheelBg = AppColors.cardBackground;

/// 点击出生日期后弹出的底部选择界面：公历 / 农历 / 四柱（自定义中文滚轮）
class BirthDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final int initialTabIndex;
  final void Function(DateTime) onConfirm;

  const BirthDatePickerSheet({
    super.key,
    required this.initialDate,
    this.initialTabIndex = 0,
    required this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    required DateTime initialDate,
    int initialTabIndex = 0,
    required void Function(DateTime) onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BirthDatePickerSheet(
        initialDate: initialDate,
        initialTabIndex: initialTabIndex,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<BirthDatePickerSheet> createState() => _BirthDatePickerSheetState();
}
class _BirthDatePickerSheetState extends State<BirthDatePickerSheet> with TickerProviderStateMixin {
  late int _tabIndex;
  late int _tabPrevIndex;
  late int _displayedTabIndex;
  late DateTime _selectedDate;
  late AnimationController _transitionController;
  late Animation<double> _transitionAnimation;

  final GlobalKey _contentKey = GlobalKey();
  final GlobalKey _preMeasureKey = GlobalKey();
  /// 每个 tab 上次测量到的内容区高度，用于过渡动画的 fromH/toH，避免跳变
  List<double?> _lastHeightForTab = [null, null, null];
  /// 跨弹窗复用：重新打开时用上次测量值，避免「重新点开又跳动」
  static List<double?> _cachedHeightForTab = [null, null, null];
  /// 首次切到某 tab 时先离屏测量再动画，避免第一次点击跳动
  int? _pendingTabIndex;

  /// 四柱：8 个字符 [年干, 年支, 月干, 月支, 日干, 日支, 时干, 时支]，空串表示未选
  late List<String> _fourPillars;
  /// 当前在选哪一柱（0=年 1=月 2=日 3=时），用于点击天干/地支时填入
  int _editingPillarIndex = 0;
  /// 四柱反推无结果时的提示（如历法不符）
  String? _fourPillarsErrorMessage;
  List<DateTime> _fourPillarMatches = const [];

  static const _duration = Duration(milliseconds: 500);
  static const _tabCurve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    final i = widget.initialTabIndex.clamp(0, 2);
    _tabIndex = i;
    _tabPrevIndex = i;
    _displayedTabIndex = i;
    _selectedDate = widget.initialDate;
    _fourPillars = List<String>.filled(8, '');
    if (i == 2) _fillFourPillarsFromDate(widget.initialDate);
    _lastHeightForTab = List<double?>.from(_cachedHeightForTab);
    _transitionController = AnimationController(duration: _duration, vsync: this);
    _transitionAnimation = CurvedAnimation(parent: _transitionController, curve: Curves.easeInOut);
  }

  void _fillFourPillarsFromDate(DateTime dt) {
    final cols = DateUtil.getEightCharColumns(dt);
    for (int i = 0; i < 4; i++) {
      final parts = cols[i].split('\n');
      _fourPillars[i * 2] = parts.isNotEmpty ? parts[0] : '';
      _fourPillars[i * 2 + 1] = parts.length > 1 ? parts[1] : '';
    }
  }

  void _clearFourPillars() {
    setState(() {
      _fourPillars = List<String>.filled(8, '');
      _fourPillarsErrorMessage = null;
      _fourPillarMatches = const [];
    });
  }

  void _onFourPillarsGanTap(String c) {
    setState(() {
      _fourPillars[_editingPillarIndex * 2] = c;
      _tryApplyFourPillars();
    });
  }

  void _onFourPillarsZhiTap(String c) {
    final gan = _fourPillars[_editingPillarIndex * 2];
    if (gan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择该柱的天干'), duration: Duration(seconds: 2)),
      );
      return;
    }
    if (!DateUtil.isValidGanZhi(gan, c)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$gan$c」不是有效的干支组合（60甲子），请重新选择'), duration: const Duration(seconds: 2)),
      );
      return;
    }
    setState(() {
      _fourPillarsErrorMessage = null;
      _fourPillars[_editingPillarIndex * 2 + 1] = c;
      _tryApplyFourPillars();
    });
  }

  /// 四柱选满时反推公历并更新 _selectedDate，取与当前 _selectedDate 最接近的匹配（避免取到 60 年前的同一八字）
  void _tryApplyFourPillars() {
    _fourPillarsErrorMessage = null;
    _fourPillarMatches = const [];
    if (_fourPillars.every((s) => s.isNotEmpty)) {
      final yearGanZhi = '${_fourPillars[0]}${_fourPillars[1]}';
      final monthGanZhi = '${_fourPillars[2]}${_fourPillars[3]}';
      final dayGanZhi = '${_fourPillars[4]}${_fourPillars[5]}';
      final timeGanZhi = '${_fourPillars[6]}${_fourPillars[7]}';
      final matches = DateUtil.datesFromBaZi(yearGanZhi, monthGanZhi, dayGanZhi, timeGanZhi);
      if (matches.isNotEmpty) {
        _fourPillarMatches = matches.reversed.toList();
        _selectedDate = DateUtil.dateFromBaZi(yearGanZhi, monthGanZhi, dayGanZhi, timeGanZhi, near: _selectedDate)!;
      } else {
        _fourPillarsErrorMessage = '未找到匹配日期，请检查四柱与历法对应关系（如月柱与年柱）';
      }
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    widget.onConfirm(_selectedDate);
    Navigator.of(context).pop();
  }

  void _onToday() {
    setState(() => _selectedDate = DateTime.now());
  }

  double _contentHeightForTab(int index) {
    final h = MediaQuery.of(context).size.height;
    if (index == 0 || index == 1) return 16 + 18 + 4 + 44 * 5;
    // 四柱内容较多（竖排四柱+按钮+公历农历+天干地支两排），过渡时预留足够高度避免裁切
    return (h * 0.8).clamp(480, h * 0.85);
  }

  void _measureContentHeight() {
    if (!mounted) return;
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    if (_lastHeightForTab[_displayedTabIndex] != height) {
      setState(() {
        _lastHeightForTab = List<double?>.from(_lastHeightForTab)
          ..[_displayedTabIndex] = height;
        _cachedHeightForTab = List<double?>.from(_lastHeightForTab);
      });
    }
  }

  void _measurePendingTabThenAnimate() {
    if (!mounted || _pendingTabIndex == null) return;
    final box = _preMeasureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      setState(() => _pendingTabIndex = null);
      return;
    }
    final height = box.size.height;
    final targetIndex = _pendingTabIndex!;
    setState(() {
      _lastHeightForTab = List<double?>.from(_lastHeightForTab)..[targetIndex] = height;
      _cachedHeightForTab = List<double?>.from(_lastHeightForTab);
      _tabPrevIndex = _tabIndex;
      _tabIndex = targetIndex;
      _pendingTabIndex = null;
    });
    Future.delayed(_duration, () {
      if (!mounted) return;
      setState(() => _tabPrevIndex = _tabIndex);
    });
    _transitionController.reset();
    _transitionController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _displayedTabIndex = targetIndex;
        if (targetIndex == 2 && _fourPillars.every((s) => s.isEmpty)) _fillFourPillarsFromDate(_selectedDate);
      });
    });
  }

  /// 过渡时高度下限，避免内容被压出 2px 溢出
  static const _minContentHeight = 260.0;

  void _onTabTapped(int index) {
    if (index == _tabIndex) return;
    if (_tabIndex != _displayedTabIndex) return;
    // 目标 tab 从未测过高度时先离屏测量再动画，避免第一次点击跳动
    final hasHeight = _lastHeightForTab[index] != null || _cachedHeightForTab[index] != null;
    if (!hasHeight) {
      setState(() => _pendingTabIndex = index);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measurePendingTabThenAnimate());
      return;
    }
    setState(() {
      _tabPrevIndex = _tabIndex;
      _tabIndex = index;
    });
    Future.delayed(_duration, () {
      if (!mounted) return;
      setState(() => _tabPrevIndex = _tabIndex);
    });
    _transitionController.reset();
    _transitionController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _displayedTabIndex = index;
        if (index == 2 && _fourPillars.every((s) => s.isEmpty)) _fillFourPillarsFromDate(_selectedDate);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTransitioning = _tabIndex != _displayedTabIndex;
    final fromH = _lastHeightForTab[_displayedTabIndex] ?? _contentHeightForTab(_displayedTabIndex);
    final toH = _lastHeightForTab[_tabIndex] ?? _contentHeightForTab(_tabIndex);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            AnimatedBuilder(
              animation: _transitionAnimation,
              builder: (context, _) {
                if (!isTransitioning) {
                  final content = _buildContentForKey(_displayedTabIndex);
                  WidgetsBinding.instance.addPostFrameCallback((_) => _measureContentHeight());
                  return RepaintBoundary(key: _contentKey, child: content);
                }
                final t = _transitionAnimation.value;
                final rawH = fromH + t * (toH - fromH);
                final h = rawH.clamp(_minContentHeight, double.infinity);
                return SizedBox(
                  height: h,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: 1 - t,
                            child: _buildContentForKey(_displayedTabIndex),
                          ),
                        ),
                        Positioned.fill(
                          child: Opacity(
                            opacity: t,
                            child: _buildContentForKey(_tabIndex),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_pendingTabIndex != null)
              SizedBox(
                height: 0,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: RepaintBoundary(
                    key: _preMeasureKey,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width,
                      child: _buildContentForKey(_pendingTabIndex!),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentForKey(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return KeyedSubtree(key: const ValueKey<int>(0), child: _buildGregorianContent());
      case 1:
        return KeyedSubtree(key: const ValueKey<int>(1), child: _buildLunarContent());
      case 2:
        return KeyedSubtree(key: const ValueKey<int>(2), child: _buildFourPillarsContent());
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: _buildAnimatedTabBar(),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _onToday,
                  icon: const Icon(Icons.today_outlined, color: _purple, size: 22),
                  tooltip: '今',
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _onConfirm,
                  style: TextButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('确认'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedTabBar() {
    const innerPadding = 2.0;
    const options = ['公历', '农历', '四柱'];
    return Container(
      height: 40,
      padding: const EdgeInsets.all(innerPadding),
      decoration: BoxDecoration(
        border: Border.all(color: _purple, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final innerW = constraints.maxWidth - innerPadding * 2;
          final itemWidth = innerW / options.length;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: _tabPrevIndex.toDouble(), end: _tabIndex.toDouble()),
            duration: _duration,
            curve: _tabCurve,
            builder: (context, value, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: innerPadding + value * itemWidth,
                    top: innerPadding,
                    bottom: innerPadding,
                    width: itemWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _purplePill,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(options.length, (i) {
                      final selectedAmount = (1 - (value - i).abs()).clamp(0.0, 1.0);
                      return _tabChip(options[i], i, selectedAmount);
                    }),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _tabChip(String label, int index, double selectedAmount) {
    final selected = _tabIndex == index;
    final textColor = Color.lerp(_greyText, AppColors.textPrimary, selectedAmount)!;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: textColor),
          ),
        ),
      ),
    );
  }

  /// 公历：自定义五列滚轮，全部中文（年/月/日/时/分）
  Widget _buildGregorianContent() {
    const yearStart = 1800;
    const yearEnd = 2100;
    final years = List.generate(yearEnd - yearStart + 1, (i) => '${yearStart + i}');
    final months = List.generate(12, (i) => '${i + 1}');
    final days = List.generate(31, (i) => '${i + 1}');
    final hours = List.generate(24, (i) => '$i');
    final minutes = List.generate(60, (i) => '$i');

    int yearIdx = _selectedDate.year - yearStart;
    yearIdx = yearIdx.clamp(0, years.length - 1);
    int monthIdx = (_selectedDate.month - 1).clamp(0, 11);
    int dayIdx = (_selectedDate.day - 1).clamp(0, 30);
    int hourIdx = _selectedDate.hour.clamp(0, 23);
    int minuteIdx = _selectedDate.minute.clamp(0, 59);

    return _buildWheelRow(
      labels: const ['年', '月', '日', '时', '分'],
      itemHeights: const [44, 44, 44, 44, 44],
      children: [
        _wheelColumn(years, yearIdx, (i) => _setGregorian(year: yearStart + i)),
        _wheelColumn(months, monthIdx, (i) => _setGregorian(month: i + 1)),
        _wheelColumn(days, dayIdx, (i) => _setGregorian(day: i + 1)),
        _wheelColumn(hours, hourIdx, (i) => _setGregorian(hour: i)),
        _wheelColumn(minutes, minuteIdx, (i) => _setGregorian(minute: i)),
      ],
    );
  }

  void _setGregorian({int? year, int? month, int? day, int? hour, int? minute}) {
    final y = year ?? _selectedDate.year;
    final m = month ?? _selectedDate.month;
    final d = day ?? _selectedDate.day;
    final h = hour ?? _selectedDate.hour;
    final min = minute ?? _selectedDate.minute;
    final maxDay = DateTime(y, m + 1, 0).day;
    final safeDay = d.clamp(1, maxDay);
    setState(() => _selectedDate = DateTime(y, m, safeDay, h, min));
  }

  /// 农历：五列滚轮，月含闰月选项（与 myresource/bazi_gui 一致，负月表示闰月）
  Widget _buildLunarContent() {
    try {
      final lunar = Lunar.fromDate(_selectedDate);
      final ly = lunar.getYear();
      final lm = lunar.getMonth();
      final ld = lunar.getDay();
      const yearStart = 1800;
      const yearEnd = 2100;
      final years = List.generate(yearEnd - yearStart + 1, (i) => '${yearStart + i}');
      final leapMonth = DateUtil.getLeapMonthForYear(ly);
      final monthLabels = <String>[];
      final monthValues = <int>[];
      for (int m = 1; m <= 12; m++) {
        monthLabels.add(DateUtil.lunarMonthLabel(m));
        monthValues.add(m);
        if (leapMonth == m) {
          monthLabels.add('闰${DateUtil.lunarMonthLabel(m).replaceFirst('月', '')}月');
          monthValues.add(-m);
        }
      }
      final days = List.generate(30, (i) => DateUtil.lunarDayLabel(i + 1));
      final hours = List.generate(24, (i) => '$i');
      final minutes = List.generate(60, (i) => '$i');

      int yearIdx = (ly - yearStart).clamp(0, years.length - 1);
      int monthIdx = 0;
      for (int i = 0; i < monthValues.length; i++) {
        if (monthValues[i] == lm) { monthIdx = i; break; }
      }
      monthIdx = monthIdx.clamp(0, monthLabels.length - 1);
      int dayIdx = (ld - 1).clamp(0, 29);
      int hourIdx = _selectedDate.hour.clamp(0, 23);
      int minuteIdx = _selectedDate.minute.clamp(0, 59);

      return _buildWheelRow(
        labels: const ['年', '月', '日', '时', '分'],
        itemHeights: const [44, 44, 44, 44, 44],
        children: [
          _wheelColumn(years, yearIdx, (i) => _setLunarFromIndices(year: yearStart + i)),
          _wheelColumn(monthLabels, monthIdx, (i) => _setLunarFromIndices(month: monthValues[i])),
          _wheelColumn(days, dayIdx, (i) => _setLunarFromIndices(day: i + 1)),
          _wheelColumn(hours, hourIdx, (i) => _setGregorian(hour: i)),
          _wheelColumn(minutes, minuteIdx, (i) => _setGregorian(minute: i)),
        ],
      );
    } catch (_) {
      return _buildGregorianContent();
    }
  }

  /// 农历滚轮改变时：农历年月日转公历（lunar 包：负月表示闰月，与 myresource/bazi.py -r 一致）
  void _setLunarFromIndices({int? year, int? month, int? day}) {
    try {
      final lunar = Lunar.fromDate(_selectedDate);
      final ly = year ?? lunar.getYear();
      var lm = month ?? lunar.getMonth();
      final requestedDay = day ?? lunar.getDay();
      final adjustments = <String>[];

      var lunarMonth = LunarMonth.fromYm(ly, lm);
      if (lunarMonth == null && lm < 0) {
        lm = lm.abs();
        lunarMonth = LunarMonth.fromYm(ly, lm);
        adjustments.add('所选年份没有该闰月，已调整为普通月');
      }
      if (lunarMonth == null) {
        throw StateError('invalid lunar month');
      }

      final safeDay = requestedDay.clamp(1, lunarMonth.getDayCount());
      if (safeDay != requestedDay) {
        adjustments.add('该农历月只有${lunarMonth.getDayCount()}天，已自动调整');
      }
      final lunarDate = Lunar.fromYmdHms(ly, lm, safeDay, 12, 0, 0);
      final solar = lunarDate.getSolar();
      setState(() => _selectedDate = DateTime(
        solar.getYear(),
        solar.getMonth(),
        solar.getDay(),
        _selectedDate.hour,
        _selectedDate.minute,
      ));
      if (adjustments.isNotEmpty) {
        _showDateAdjustment(adjustments.join('；'));
      }
    } catch (_) {
      _showDateAdjustment('该农历日期无法转换，已保留原日期');
    }
  }

  void _showDateAdjustment(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget _buildWheelRow({required List<String> labels, required List<double> itemHeights, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(labels[i], style: const TextStyle(fontSize: 14, color: Colors.black)),
                  const SizedBox(height: 4),
                  SizedBox(height: itemHeights[i] * 5, child: children[i]),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _wheelColumn(List<String> items, int selectedIndex, void Function(int) onSelected) {
    final controller = FixedExtentScrollController(initialItem: selectedIndex.clamp(0, items.length - 1));
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 44,
      diameterRatio: 1.2,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (i) => onSelected(i),
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: items.length,
        builder: (context, index) {
          final isSelected = index == selectedIndex;
          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? _wheelBg : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                items[index],
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.black : _grey,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFourPillarsContent() {
    const labels = ['年柱', '月柱', '日柱', '时柱'];
    const tiangan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    const dizhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
    final allFilled = _fourPillars.every((s) => s.isNotEmpty);

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
          Row(
            children: List.generate(4, (i) {
              final gan = _fourPillars[i * 2];
              final zhi = _fourPillars[i * 2 + 1];
              final isEditing = _editingPillarIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _editingPillarIndex = i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labels[i], style: const TextStyle(fontSize: 13, color: _grey)),
                      const SizedBox(height: 8),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          border: isEditing ? Border.all(color: _purple, width: 2) : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(gan.isEmpty ? '－' : gan, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          border: isEditing ? Border.all(color: _purple, width: 2) : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(zhi.isEmpty ? '－' : zhi, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: _clearFourPillars,
                child: const Text('清除', style: TextStyle(color: _purple, fontSize: 14)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() => _fillFourPillarsFromDate(_selectedDate));
                  _tryApplyFourPillars();
                },
                child: const Text('从当前日期填充', style: TextStyle(color: _purple, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('公历：${DateUtil.formatGregorian(_selectedDate)}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text('农历：${DateUtil.formatLunar(_selectedDate)}', style: const TextStyle(fontSize: 13)),
                if (!allFilled) ...[
                  const SizedBox(height: 4),
                  const Text('选满四柱后将自动更新为对应日期', style: TextStyle(fontSize: 11, color: _grey)),
                ],
                if (_fourPillarsErrorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(_fourPillarsErrorMessage!, style: const TextStyle(fontSize: 11, color: Colors.red)),
                ],
                if (_fourPillarMatches.length > 1) ...[
                  const SizedBox(height: 6),
                  const Text('同一四柱可能相隔六十年，请确认出生年份（近年优先）', style: TextStyle(fontSize: 11, color: _greyText)),
                  const SizedBox(height: 6),
                  SizedBox(height: 34, child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fourPillarMatches.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final match = _fourPillarMatches[index];
                      return ChoiceChip(
                        selected: match == _selectedDate,
                        showCheckmark: false,
                        label: Text('${match.year}-${match.month.toString().padLeft(2, '0')}-${match.day.toString().padLeft(2, '0')}'),
                        selectedColor: _purple,
                        backgroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _selectedDate = match),
                      );
                    },
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('点击上方柱位后，先选天干再选地支（须为60甲子合法组合）', style: TextStyle(fontSize: 12, color: _grey)),
          const SizedBox(height: 6),
          const Text('天干', style: TextStyle(fontSize: 12, color: _grey)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tiangan.map((c) => _pillarKey(c, isGan: true)).toList(),
          ),
          const SizedBox(height: 8),
          const Text('地支', style: TextStyle(fontSize: 12, color: _grey)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: dizhi.map((c) => _pillarKey(c, isGan: false)).toList(),
          ),
        ],
    );
  }

  Widget _pillarKey(String char, {required bool isGan}) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => isGan ? _onFourPillarsGanTap(char) : _onFourPillarsZhiTap(char),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(char, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}
