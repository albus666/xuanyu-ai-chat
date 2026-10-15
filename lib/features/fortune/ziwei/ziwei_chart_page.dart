import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';
import 'package:xuanyu/core/theme/app_colors.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/fortune/paipan/utils/true_solar_time.dart';

import '../../../core/widgets/app_share_more_button.dart';
import 'widgets/ziwei_chart_board.dart';
import 'widgets/ziwei_personal_info_tab.dart';
import 'ziwei_models.dart';
import 'ziwei_archive_page.dart';
import 'ziwei_archive_store.dart';
import 'ziwei_input_page.dart';
import 'ziwei_service.dart';
import '../shared_chart_archive.dart';
import 'ziwei_settings_sheet.dart';
import 'ziwei_timeline.dart';

enum _ChartAction { settings, natal, today, date }

class ZiweiChartPage extends StatefulWidget {
  const ZiweiChartPage({
    super.key,
    required this.profile,
    required this.initialData,
    required this.initialTargetDate,
    required this.initialTargetTimeIndex,
    this.archiveRecord,
    this.professionalOnly = false,
    this.embedded = false,
    this.showBirthData = true,
    this.sharedChartLoader,
  });

  final ZiweiProfile profile;
  final ZiweiChartData initialData;
  final DateTime initialTargetDate;
  final int initialTargetTimeIndex;
  final ZiweiArchiveRecord? archiveRecord;
  final bool professionalOnly;
  final bool embedded;
  final bool showBirthData;
  final Future<ZiweiChartData> Function(DateTime, int)? sharedChartLoader;

  @override
  State<ZiweiChartPage> createState() => _ZiweiChartPageState();
}

class _ZiweiChartPageState extends State<ZiweiChartPage> {
  final GlobalKey _chartKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final Map<String, ScrollController> _timelineControllers = {
    for (final title in const ['大限', '流年', '流月', '流日', '流时'])
      title: ScrollController(),
  };
  final Map<String, int> _timelineSelections = {};

  late ZiweiProfile _profile;
  late ZiweiChartData _data;
  late DateTime _targetDate;
  late int _targetTimeIndex;
  ZiweiLayer _activeLayer = ZiweiLayer.natal;
  late int _selectedPalaceIndex;
  bool _loading = false;
  bool _caseNotebookVisible = false;
  ZiweiArchiveRecord? _archiveRecord;
  TextEditingController? _caseTitleController;
  TextEditingController? _caseReasoningController;
  TextEditingController? _caseCommentaryController;
  final ScrollController _caseScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _data = widget.initialData;
    _targetDate = widget.initialTargetDate;
    _targetTimeIndex = widget.initialTargetTimeIndex;
    _selectedPalaceIndex = _natalPalaceIndex;
    _archiveRecord = widget.archiveRecord;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _timelineControllers.values) {
      controller.dispose();
    }
    _caseTitleController?.dispose();
    _caseReasoningController?.dispose();
    _caseCommentaryController?.dispose();
    _caseScrollController.dispose();
    super.dispose();
  }

  void _toggleCaseNotebook() {
    if (_caseNotebookVisible) {
      setState(() => _caseNotebookVisible = false);
      return;
    }
    final record = _archiveRecord;
    if (record == null) {
      showAppToast(context, '当前命盘尚未保存到紫微档案');
      return;
    }
    _caseTitleController ??= TextEditingController(
      text: record.caseTitle.trim().isEmpty
          ? '${_profile.name} · 档案笔记'
          : record.caseTitle,
    );
    _caseReasoningController ??=
        TextEditingController(text: record.reasoningNotes);
    _caseCommentaryController ??=
        TextEditingController(text: record.commentary);
    setState(() => _caseNotebookVisible = true);
  }

  Future<void> _saveCaseNotebook() async {
    final record = _archiveRecord;
    if (record == null ||
        _caseTitleController == null ||
        _caseReasoningController == null ||
        _caseCommentaryController == null) {
      return;
    }
    if (_caseReasoningController!.text.trim().isEmpty &&
        _caseCommentaryController!.text.trim().isEmpty) {
      showAppToast(context, '请先填写看盘判断或现实反馈');
      return;
    }
    final saved = await ZiweiArchiveStore.saveCase(
      fallback: record,
      caseTitle: _caseTitleController!.text,
      reasoningNotes: _caseReasoningController!.text,
      commentary: _caseCommentaryController!.text,
    );
    _archiveRecord = saved;
    if (mounted) showAppToast(context, '档案笔记已保存');
  }

  String get _subjectLabel {
    if (_archiveRecord?.isSelf == true) return '本人';
    final name = _profile.name.trim();
    return name.isEmpty ? '当前档案' : name;
  }

  void _resetCaseNotebook(ZiweiArchiveRecord record) {
    _caseTitleController?.dispose();
    _caseReasoningController?.dispose();
    _caseCommentaryController?.dispose();
    _caseTitleController = null;
    _caseReasoningController = null;
    _caseCommentaryController = null;
    _archiveRecord = record;
    _caseNotebookVisible = false;
  }

  Future<void> _activateArchive(ZiweiArchiveRecord record) async {
    final now = DateTime.now();
    await _load(
      date: now,
      timeIndex: ZiweiProfile.timeIndexFor(now.hour),
      layer: ZiweiLayer.natal,
      profile: record.profile,
    );
    if (!mounted) return;
    setState(() => _resetCaseNotebook(record));
  }

  Future<void> _showArchivePicker() async {
    final cases = await loadRoomChartCases();
    final records = <ZiweiArchiveRecord>[
      for (final item in cases)
        if (item.archiveFor(RoomChartKind.ziwei).unavailableReason == null)
          ZiweiArchiveRecord.fromJson(
            item.archiveFor(RoomChartKind.ziwei).snapshot,
          ),
    ];
    records.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 9),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5DDDF),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  '选择命理档案',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final record = records[index];
                    final selected = record.id == _archiveRecord?.id;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: .1),
                        foregroundColor: AppColors.primaryDark,
                        child: Text(record.profile.gender == '女' ? '坤' : '乾'),
                      ),
                      title: Text(
                          record.isSelf ? '我的命盘' : record.profile.name.trim()),
                      subtitle: Text(record.relationshipLabel),
                      trailing: selected
                          ? const Text(
                              '当前',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (!selected) _activateArchive(record);
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ZiweiInputPage(forOther: true),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('为他人排盘'),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ZiweiArchivePage(),
                    ),
                  );
                },
                child: const Text('管理命理档案'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  ZiweiScope? get _activeScope => _data.horoscope.scopeFor(_activeLayer);

  ZiweiPalace get _selectedPalace => _data.palaceAt(_selectedPalaceIndex);

  int get _natalPalaceIndex => _data.astrolabe.palaces
      .firstWhere(
        (palace) => palace.earthlyBranch == _data.astrolabe.soulPalaceBranch,
      )
      .index;

  ZiweiPalace get _currentDecadalPalace =>
      _data.palaceAt(_data.horoscope.decadal.index);

  Future<void> _load({
    required DateTime date,
    required int timeIndex,
    required ZiweiLayer layer,
    ZiweiProfile? profile,
  }) async {
    if (_loading) return;
    final nextProfile = profile ?? _profile;
    setState(() => _loading = true);
    try {
      final result = widget.sharedChartLoader != null
          ? await widget.sharedChartLoader!(date, timeIndex)
          : await ZiweiService.calculate(profile: nextProfile,
              targetDate: date, targetTimeIndex: timeIndex);
      if (!mounted) return;
      final scope = result.horoscope.scopeFor(layer);
      setState(() {
        _profile = nextProfile;
        _data = result;
        _targetDate = date;
        _targetTimeIndex = timeIndex;
        _activeLayer = layer;
        _selectedPalaceIndex = scope?.index ??
            result.astrolabe.palaces
                .firstWhere(
                  (palace) =>
                      palace.earthlyBranch == result.astrolabe.soulPalaceBranch,
                )
                .index;
      });
    } on ZiweiServiceException catch (error) {
      if (mounted) showAppToast(context, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectLayer(ZiweiLayer layer) {
    final scope = _data.horoscope.scopeFor(layer);
    setState(() {
      _activeLayer = layer;
      _selectedPalaceIndex = scope?.index ?? _natalPalaceIndex;
    });
  }

  void _goNatal() => _selectLayer(ZiweiLayer.natal);

  // Legacy navigation is intentionally kept off the main chart toolbar.
  // ignore: unused_element
  Future<void> _handleChartAction(_ChartAction action) async {
    switch (action) {
      case _ChartAction.settings:
        await _editSettings();
      case _ChartAction.natal:
        _goNatal();
      case _ChartAction.today:
        await _goToday();
      case _ChartAction.date:
        await _pickTargetDate();
    }
  }

  Future<void> _editSettings() async {
    final settings = await ZiweiSettingsSheet.show(context, _profile.settings);
    if (settings == null || !mounted) return;
    final effectiveBirthDate =
        settings.useTrueSolarTime && _profile.longitude != null
            ? TrueSolarTime.toTrueSolar(
                _profile.clockBirthDate,
                _profile.longitude!,
              )
            : _profile.clockBirthDate;
    final profile = ZiweiProfile(
      name: _profile.name,
      gender: _profile.gender,
      clockBirthDate: _profile.clockBirthDate,
      effectiveBirthDate: effectiveBirthDate,
      calendarTypeIndex: _profile.calendarTypeIndex,
      settings: settings,
      birthPlace: _profile.birthPlace,
      longitude: _profile.longitude,
      latitude: _profile.latitude,
    );
    await _load(
      date: _targetDate,
      timeIndex: _targetTimeIndex,
      layer: _activeLayer,
      profile: profile,
    );
  }

  Future<void> _pickTargetDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime(1800),
      lastDate: DateTime(2299, 12, 31),
      helpText: '选择运限日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (date != null) {
      await _load(
        date: date,
        timeIndex: _targetTimeIndex,
        layer: ZiweiLayer.daily,
      );
    }
  }

  Future<void> _goToday() async {
    final now = DateTime.now();
    await _load(
      date: now,
      timeIndex: ZiweiProfile.timeIndexFor(now.hour),
      layer: ZiweiLayer.yearly,
    );
  }

  // ignore: unused_element
  Future<void> _showFullChart() async {
    var fullLayer = _activeLayer;
    var fullSelectedPalaceIndex = _selectedPalaceIndex;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog.fullscreen(
          backgroundColor: const Color(0xFFF5FAFA),
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '全屏命盘 · ${fullLayer == ZiweiLayer.natal ? '本命原局' : fullLayer.label}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Text(
                        '双指缩放 · 点击宫位',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textHint,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: .7,
                    maxScale: 3,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final shortest =
                            constraints.maxWidth < constraints.maxHeight
                                ? constraints.maxWidth
                                : constraints.maxHeight;
                        return Center(
                          child: SizedBox.square(
                            dimension: shortest - 18,
                            child: ZiweiChartBoard(
                              data: _data,
                              profile: _profile,
                              showBirthData: widget.showBirthData,
                              activeLayer: fullLayer,
                              selectedPalaceIndex: fullSelectedPalaceIndex,
                              onPalaceTap: (index) {
                                setDialogState(
                                  () => fullSelectedPalaceIndex = index,
                                );
                                _showPalaceDetails(index);
                              },
                              onLayerChanged: (layer) {
                                final scope = _data.horoscope.scopeFor(layer);
                                final index = scope?.index ?? _natalPalaceIndex;
                                setDialogState(() {
                                  fullLayer = layer;
                                  fullSelectedPalaceIndex = index;
                                });
                                if (mounted) {
                                  setState(() {
                                    _activeLayer = layer;
                                    _selectedPalaceIndex = index;
                                  });
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPalaceDetails(int index) async {
    setState(() => _selectedPalaceIndex = index);
    final scope = _activeScope;
    final activeName = scope != null && scope.palaceNames.length > index
        ? scope.palaceNames[index]
        : '';
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .58,
        minChildSize: .38,
        maxChildSize: .9,
        builder: (context, controller) => DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _sheetHeader(
                title: '${_selectedPalace.name}'
                    '${activeName.isEmpty ? '' : ' · $activeName'}详情',
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
              const Divider(height: 1, color: Color(0xFFEDF1F2)),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                  child: _palaceDetails(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showChartInfo() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DefaultTabController(
        length: 2,
        child: Container(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _sheetHeader(
                title: '命盘资料',
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
              const TabBar(
                labelColor: AppColors.primaryDark,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: '四化流曜'),
                  Tab(text: '排盘信息'),
                ],
              ),
              const Divider(height: 1, color: Color(0xFFEDF1F2)),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      child: _mutagenDetails(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      child: _ruleDetails(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader({required String title, required VoidCallback onClose}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 9, 8, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navigationColor = Color(0xFFF7FCFC);
    return DefaultTabController(
      length: 2,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: navigationColor,
          systemNavigationBarColor: navigationColor,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: navigationColor,
          appBar: widget.embedded ? null : AppBar(
            backgroundColor: navigationColor,
            foregroundColor: const Color(0xFF193E46),
            surfaceTintColor: navigationColor,
            shadowColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: navigationColor,
            ),
            titleSpacing: 4,
            title: const Text(
              '紫微斗数',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF193E46),
              ),
            ),
            actions: [
              const AppShareMoreButton(
                toolRoute: '/home_ziwei',
                title: '紫微斗数专业排盘',
                shareText: '玄遇提供紫微斗数专业排盘工具，可创建案例并查看专业盘面。',
              ),
              if (!widget.professionalOnly) ...[
                IconButton(
                  key: const ValueKey('ziwei-case-notebook-action'),
                  tooltip: '档案笔记',
                  onPressed: _toggleCaseNotebook,
                  icon: Icon(
                    _caseNotebookVisible
                        ? Icons.note_alt_rounded
                        : Icons.note_alt_outlined,
                  ),
                ),
                IconButton(
                  key: const ValueKey('ziwei-settings-action'),
                  tooltip: '设置',
                  onPressed: _loading ? null : _editSettings,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  color: const Color(0xFF169C92),
                  disabledColor: const Color(0xFF9DB8B6),
                ),
                TextButton.icon(
                  key: const ValueKey('ziwei-archive-switch-action'),
                  onPressed: _loading ? null : _showArchivePicker,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 68),
                    child: Text(
                      _subjectLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF169C92),
                    padding: const EdgeInsets.only(left: 5, right: 8),
                  ),
                ),
              ],
            ],
            bottom: widget.professionalOnly
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(45),
                    child: Container(
                      height: 45,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFBFFFE),
                        border: Border(
                          bottom:
                              BorderSide(color: Color(0xFFBFE9E5), width: .7),
                        ),
                      ),
                      child: const TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorWeight: 2.5,
                        indicatorColor: Color(0xFF169C92),
                        labelColor: Color(0xFF193E46),
                        unselectedLabelColor: Color(0xFF718B91),
                        labelStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        tabs: [
                          Tab(text: '个人信息'),
                          Tab(text: '专业命盘'),
                        ],
                      ),
                    ),
                  ),
          ),
          body: Stack(
            children: [
              IgnorePointer(
                ignoring: _loading,
                child: widget.professionalOnly
                    ? _professionalChart()
                    : TabBarView(
                        children: [
                          ZiweiPersonalInfoTab(
                            data: _data,
                            profile: _profile,
                            targetDate: _targetDate,
                            loading: _loading,
                            onSelectDecadal: (item) => _load(
                              date: item.date,
                              timeIndex: item.timeIndex,
                              layer: ZiweiLayer.decadal,
                            ),
                            onSelectYear: (item) => _load(
                              date: item.date,
                              timeIndex: item.timeIndex,
                              layer: ZiweiLayer.yearly,
                            ),
                          ),
                          _professionalChart(),
                        ],
                      ),
              ),
              if (_loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: Color(0xFF169C92),
                    backgroundColor: Color(0xFFDDF8F4),
                  ),
                ),
              if (!widget.professionalOnly &&
                  _caseNotebookVisible &&
                  _caseTitleController != null &&
                  _caseReasoningController != null &&
                  _caseCommentaryController != null)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  height: (MediaQuery.sizeOf(context).height * .42)
                      .clamp(280.0, 390.0),
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: _ZiweiCaseNotebook(
                      scrollController: _caseScrollController,
                      titleController: _caseTitleController!,
                      reasoningController: _caseReasoningController!,
                      commentaryController: _caseCommentaryController!,
                      onSave: _saveCaseNotebook,
                      onClose: _toggleCaseNotebook,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _professionalChart() {
    return SafeArea(
      key: const ValueKey('ziwei-professional-bottom-safe-area'),
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFDDF8F4),
              Color(0xFFF7FCFC),
              Color(0xFFEEEAFE),
            ],
            stops: [0, .48, 1],
          ),
        ),
        child: ListView(
          key: const PageStorageKey('ziwei-professional-chart-scroll'),
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: RepaintBoundary(
                key: _chartKey,
                child: ZiweiChartBoard(
                  data: _data,
                  profile: _profile,
                  showBirthData: widget.showBirthData,
                  activeLayer: _activeLayer,
                  selectedPalaceIndex: _selectedPalaceIndex,
                  onPalaceTap: (index) =>
                      setState(() => _selectedPalaceIndex = index),
                  onLayerChanged: _selectLayer,
                ),
              ),
            ),
            const SizedBox(height: 3),
            _timelinePanel(),
            const CulturalReferenceNotice(),
          ],
        ),
      ),
    );
  }

  Widget _timelinePanel() {
    final lunar = Lunar.fromDate(_targetDate);
    final decadalItems = ZiweiTimelineBuilder.decadals(_data, _profile);
    final yearItems = _data.horoscope.decadal.name == '童限'
        ? ZiweiTimelineBuilder.childYears(_data, _profile)
        : ZiweiTimelineBuilder.years(_currentDecadalPalace, _profile);
    final monthItems = ZiweiTimelineBuilder.months(lunar.getYear(), _profile);
    final dayItems =
        ZiweiTimelineBuilder.days(lunar.getYear(), lunar.getMonth());
    final hourItems = ZiweiTimelineBuilder.hours(_targetDate);
    return Column(
      children: [
        _timelineRow(
          title: '大限',
          items: decadalItems,
          selected: (item) => _data.horoscope.decadal.name == '童限'
              ? item.key == 'decadal-child'
              : item.key != 'decadal-child' &&
                  item.palaceIndex == _data.horoscope.decadal.index,
          onTap: (item) => _load(
            date: item.date,
            timeIndex: item.timeIndex,
            layer: ZiweiLayer.decadal,
          ),
          tint: true,
        ),
        _timelineRow(
          title: '流年',
          items: yearItems,
          selected: (item) => _data.horoscope.age.nominalAge != null
              ? item.age == _data.horoscope.age.nominalAge
              : item.lunarYear == lunar.getYear(),
          onTap: (item) => _load(
            date: item.date,
            timeIndex: item.timeIndex,
            layer: ZiweiLayer.yearly,
          ),
        ),
        _timelineRow(
          title: '流月',
          items: monthItems,
          selected: (item) =>
              item.lunarYear == lunar.getYear() &&
              item.lunarMonth == lunar.getMonth(),
          onTap: (item) => _load(
            date: item.date,
            timeIndex: item.timeIndex,
            layer: ZiweiLayer.monthly,
          ),
          tint: true,
        ),
        _timelineRow(
          title: '流日',
          items: dayItems,
          selected: (item) => _sameDay(item.date, _targetDate),
          onTap: (item) => _load(
            date: item.date,
            timeIndex: item.timeIndex,
            layer: ZiweiLayer.daily,
          ),
        ),
        _timelineRow(
          title: '流时',
          items: hourItems,
          selected: (item) => item.timeIndex == _targetTimeIndex,
          onTap: (item) => _load(
            date: item.date,
            timeIndex: item.timeIndex,
            layer: ZiweiLayer.hourly,
          ),
          tint: true,
          last: true,
        ),
      ],
    );
  }

  Widget _timelineRow({
    required String title,
    required List<ZiweiTimelineItem> items,
    required bool Function(ZiweiTimelineItem) selected,
    required ValueChanged<ZiweiTimelineItem> onTap,
    bool tint = false,
    bool last = false,
  }) {
    final active = title == _activeLayer.label;
    final selectedIndex = items.indexWhere(selected);
    final controller = _timelineControllers[title]!;
    _revealTimelineSelection(
      title: title,
      controller: controller,
      index: selectedIndex,
      itemExtent: title == '大限' ? 59 : 45,
    );
    return Container(
      height: 38,
      margin: EdgeInsets.fromLTRB(4, 1, 4, last ? 8 : 0),
      decoration: BoxDecoration(
        color: tint ? const Color(0xFFF4FFFD) : const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFB4E4DF), width: .6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color:
                      active ? const Color(0xFF169C92) : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 3),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = selected(item);
                return InkWell(
                  onTap: () => onTap(item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: title == '大限' ? 58 : 44,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 1,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFDCF8F4)
                          : Colors.transparent,
                      border: isSelected
                          ? const Border(
                              bottom: BorderSide(
                                color: Color(0xFF169C92),
                                width: 1.2,
                              ),
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8.5,
                            height: 1.02,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFF087F78)
                                : AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 7.5,
                            height: 1.02,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          item.tertiary,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 7.5,
                            height: 1.02,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _revealTimelineSelection({
    required String title,
    required ScrollController controller,
    required int index,
    required double itemExtent,
  }) {
    if (index < 0 || _timelineSelections[title] == index) return;
    final hadSelection = _timelineSelections.containsKey(title);
    _timelineSelections[title] = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final viewport = controller.position.viewportDimension;
      final target = (index * itemExtent - viewport * .36).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      if (hadSelection) {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        controller.jumpTo(target);
      }
    });
  }

  Widget _palaceDetails() {
    final palace = _selectedPalace;
    final effectiveMajorStars = _data.effectiveMajorStarsFor(palace);
    final borrowsMajorStars = _data.borrowsOppositeMajorStars(palace);
    final scope = _activeScope;
    final activePalaceName =
        scope != null && scope.palaceNames.length > palace.index
            ? scope.palaceNames[palace.index]
            : '';
    final flowStars = scope != null && scope.stars.length > palace.index
        ? scope.stars[palace.index]
        : const <ZiweiStar>[];
    final surrounded = ZiweiTimelineBuilder.surroundedIndices(palace.index)
        .map(_data.palaceAt)
        .toList();
    final allStars = [
      ...effectiveMajorStars,
      ...palace.minorStars,
      ...palace.adjectiveStars,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                palace.name,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${palace.heavenlyStem}${palace.earthlyBranch} · ${palace.decadal.startAge}～${palace.decadal.endAge}岁',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _detailLine(
          '当前查看',
          scope == null
              ? '本命原局 · 生年四化'
              : '${_activeLayer.label} · ${scope.ganZhi} · '
                  '${_data.horoscope.solarDate}',
        ),
        if (activePalaceName.isNotEmpty)
          _detailLine('运限宫位', '$activePalaceName（${_activeLayer.label}）'),
        _detailLine(
          '三方四正',
          surrounded.map((item) => item.name).join(' · '),
        ),
        _detailLine(
          '主星',
          effectiveMajorStars.isEmpty
              ? '本宫与对宫暂无十四主星'
              : '${effectiveMajorStars.map((star) => '${star.name}${star.brightness}').join('、')}'
                  '${borrowsMajorStars ? '（借对宫）' : ''}',
        ),
        _detailLine(
          '辅星杂曜',
          allStars.skip(effectiveMajorStars.length).isEmpty
              ? '无'
              : allStars
                  .skip(effectiveMajorStars.length)
                  .map((star) => star.name)
                  .join('、'),
        ),
        _detailLine(
          '本命四化',
          _palaceMutagens(
            allStars,
            (star) => star.mutagen,
            source: '生年',
          ),
        ),
        if (scope != null)
          _detailLine(
            '${_activeLayer.label}四化',
            _palaceMutagens(
              [...allStars, ...flowStars],
              (star) {
                final index = scope.mutagen.indexOf(star.name);
                return index < 0 ? '' : const ['禄', '权', '科', '忌'][index];
              },
              source: _activeLayer.label,
            ),
          ),
        if (scope != null)
          _detailLine(
            '${_activeLayer.label}流曜',
            flowStars.isEmpty
                ? '无'
                : flowStars
                    .map(
                      (star) => '${star.name}${star.brightness}',
                    )
                    .toSet()
                    .join('、'),
          ),
        _detailLine(
          '十二神',
          '${palace.changsheng12} · ${palace.boshi12} · ${palace.suiqian12} · ${palace.jiangqian12}',
        ),
        if (scope != null &&
            (scope.suiqian12.length > palace.index ||
                scope.jiangqian12.length > palace.index))
          _detailLine(
            '${_activeLayer.label}岁曜',
            [
              if (scope.suiqian12.length > palace.index)
                scope.suiqian12[palace.index],
              if (scope.jiangqian12.length > palace.index)
                scope.jiangqian12[palace.index],
            ].where((name) => name.isNotEmpty).join(' · '),
          ),
        _detailLine(
          '流年岁数',
          ZiweiTimelineBuilder.yearlyAgesForPalace(
            currentAge: _data.horoscope.age.nominalAge,
            currentPalaceIndex: _data.horoscope.yearly.index,
            palaceIndex: palace.index,
          ).join('、'),
        ),
        _detailLine(
          '小限岁数',
          palace.ages.isEmpty ? '无' : palace.ages.join('、'),
        ),
      ],
    );
  }

  String _palaceMutagens(
    Iterable<ZiweiStar> stars,
    String Function(ZiweiStar) mutagenOf, {
    required String source,
  }) {
    final values = <String>[];
    for (final star in stars) {
      final mutagen = mutagenOf(star);
      if (mutagen.isNotEmpty) {
        values.add('$mutagen·${star.name}（$source）');
      }
    }
    return values.toSet().isEmpty ? '无' : values.toSet().join('、');
  }

  Widget _mutagenDetails() {
    final natalMutagens = List<String>.filled(4, '');
    for (final palace in _data.astrolabe.palaces) {
      for (final star in [
        ...palace.majorStars,
        ...palace.minorStars,
        ...palace.adjectiveStars,
      ]) {
        final index = const ['禄', '权', '科', '忌'].indexOf(star.mutagen);
        if (index >= 0 && natalMutagens[index].isEmpty) {
          natalMutagens[index] = star.name;
        }
      }
    }
    final scopes = <(String, List<String>)>[
      ('本命', natalMutagens),
      ('大限', _data.horoscope.decadal.mutagen),
      ('小限', _data.horoscope.age.mutagen),
      ('流年', _data.horoscope.yearly.mutagen),
      ('流月', _data.horoscope.monthly.mutagen),
      ('流日', _data.horoscope.daily.mutagen),
      ('流时', _data.horoscope.hourly.mutagen),
    ];
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '“本命”为生年四化；其他各行为对应运限层级四化，盘面角标会标注来源。',
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: AppColors.textHint,
              ),
            ),
          ),
        ),
        for (final item in scopes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    item.$1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var index = 0; index < item.$2.length; index++)
                        if (item.$2[index].isNotEmpty)
                          _mutagenChip(
                            const ['禄', '权', '科', '忌'][index],
                            item.$2[index],
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_activeScope != null) ...[
          const Divider(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_activeLayer.label}流曜：${_activeScope!.stars.expand((group) => group).map((star) => star.name).toSet().join('、')}',
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _mutagenChip(String mutagen, String star) {
    final color = switch (mutagen) {
      '禄' => const Color(0xFF2F8C70),
      '权' => const Color(0xFF8C5AA8),
      '科' => const Color(0xFF477CBE),
      _ => const Color(0xFFC34F4F),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$mutagen · $star',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _ruleDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailLine('方案', _profile.settings.presetName),
        _detailLine('星盘', _profile.settings.astroTypeLabel),
        _detailLine(
          '分界',
          '生年${_profile.settings.yearDivide == 'exact' ? '立春' : '正月初一'} · '
              '运限${_profile.settings.horoscopeDivide == 'exact' ? '立春' : '正月初一'} · '
              '小限${_profile.settings.ageDivide == 'birthday' ? '生日' : '自然年'} · '
              '晚子${_profile.settings.dayDivide == 'forward' ? '次日' : '当日'}',
        ),
        _detailLine(
          '闰月',
          _profile.settings.fixLeap ? '十五日及以前按本月，之后按下月' : '不作月中分界修正',
        ),
        if (widget.showBirthData)
          _detailLine('钟表时间', _formatDateTime(_profile.clockBirthDate)),
        if (widget.showBirthData && _profile.settings.useTrueSolarTime)
          _detailLine('真太阳时', _formatDateTime(_profile.effectiveBirthDate)),
        if (widget.showBirthData && _profile.birthPlace != null)
          _detailLine('出生地', _profile.birthPlace!),
      ],
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDateTime(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

class _ZiweiCaseNotebook extends StatelessWidget {
  const _ZiweiCaseNotebook({
    required this.scrollController,
    required this.titleController,
    required this.reasoningController,
    required this.commentaryController,
    required this.onSave,
    required this.onClose,
  });

  final ScrollController scrollController;
  final TextEditingController titleController;
  final TextEditingController reasoningController;
  final TextEditingController commentaryController;
  final Future<void> Function() onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFBFEFD),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFCDEDEA)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.note_alt_outlined,
                      color: AppColors.primaryDark),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('档案笔记',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                  TextButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                  IconButton(
                    tooltip: '收起',
                    onPressed: onClose,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2F2F0)),
            Expanded(
              child: ListView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                children: [
                  TextField(
                    controller: titleController,
                    maxLength: 80,
                    decoration: _caseDecoration('笔记标题', '例如：关系与事业重点'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasoningController,
                    minLines: 7,
                    maxLines: 18,
                    decoration: _caseDecoration('看盘判断', '记录你的判断依据与重要线索…'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentaryController,
                    minLines: 7,
                    maxLines: 18,
                    decoration: _caseDecoration('现实反馈', '记录已验证的经历与后续变化…'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  InputDecoration _caseDecoration(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
