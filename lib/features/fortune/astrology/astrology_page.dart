import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/local/archive_account_scope.dart';
import '../../../core/profile/account_birth_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/widgets/app_share_more_button.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/cultural_reference_notice.dart';
import '../../../shared/widgets/chart_case_notebook.dart';
import '../paipan/models/region.dart';
import '../paipan/utils/region_loader.dart';
import '../paipan/widgets/birth_date_picker_sheet.dart';
import '../paipan/widgets/birth_place_picker_sheet.dart';
import '../shared_chart_archive.dart';
import '../chart_archive_page.dart';
import 'astrology_archive_store.dart';
import 'astrology_chart_wheel.dart';
import 'astrology_models.dart';
import 'astrology_personal_reading.dart';
import 'astrology_service.dart';

const _navy = Color(0xFF263C65);
const _violet = Color(0xFF6972B9);
const _softBackground = Color(0xFFF5F7FC);

class AstrologyEntryPage extends StatefulWidget {
  const AstrologyEntryPage({super.key});

  @override
  State<AstrologyEntryPage> createState() => _AstrologyEntryPageState();
}

class _AstrologyEntryPageState extends State<AstrologyEntryPage> {
  bool _loading = true;
  bool _opening = false;
  AccountBirthProfile? _account;
  String? _error;

  @override
  void initState() {
    super.initState();
    RegionLoader.preload();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await AccountBirthProfileRepository.load(
        forceRefresh: true,
      );
      if (!mounted) return;
      _account = profile;
      setState(() => _loading = false);
      if (profile.isAstrologyComplete) {
        await _open(AstrologyProfile.fromAccount(profile), isSelf: true);
      }
    } on DioException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '本人资料读取失败，请稍后重试';
        });
      }
    }
  }

  Future<void> _complete() async {
    final profile = await AccountBirthProfileRepository.ensureAstrology(
      context,
    );
    if (profile == null || !mounted) return;
    setState(() => _account = profile);
    await _open(AstrologyProfile.fromAccount(profile), isSelf: true);
  }

  Future<void> _open(AstrologyProfile profile, {required bool isSelf}) async {
    if (_opening || !mounted) return;
    setState(() => _opening = true);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            AstrologyChartLauncherPage(profile: profile, isSelf: isSelf),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBackground,
      appBar: AppBar(
        backgroundColor: _softBackground,
        elevation: 0,
        title: const Text('星座星盘'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AstrologyArchivePage(),
              ),
            ),
            child: const Text('命理档案'),
          ),
        ],
      ),
      body: _loading || _opening
          ? const _LoadingBody(label: '正在读取本人资料…')
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_navy, _violet],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.blur_circular_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _error ?? '还差一项资料即可生成准确星盘',
                        style: AppTextStyles.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error ??
                            ((_account?.isComplete ?? false)
                                ? '出生日期时辰已经自动读取，只需补充出生地；用于计算上升和宫位。'
                                : '填写一次出生日期时辰与出生地，以后进入会直接使用本人资料。'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppButton(
                        label: _error == null ? '完善资料并生成' : '重新加载',
                        onPressed: _error == null ? _complete : _load,
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AstrologyInputPage(),
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('为他人排盘'),
                      ),
                      const CulturalReferenceNotice(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class AstrologyChartLauncherPage extends StatefulWidget {
  const AstrologyChartLauncherPage({
    super.key,
    required this.profile,
    required this.isSelf,
    this.professionalOnly = false,
  });

  final AstrologyProfile profile;
  final bool isSelf;
  final bool professionalOnly;

  @override
  State<AstrologyChartLauncherPage> createState() =>
      _AstrologyChartLauncherPageState();
}

class _AstrologyChartLauncherPageState
    extends State<AstrologyChartLauncherPage> {
  AstrologyChartData? _chart;
  AstrologyArchiveRecord? _record;
  String? _error;
  late final Future<int?> _archiveUserId;

  @override
  void initState() {
    super.initState();
    _archiveUserId = ArchiveAccountScope.currentUserId();
    _calculate();
  }

  Future<void> _calculate() async {
    if (mounted) setState(() => _error = null);
    try {
      final expectedUserId = await _archiveUserId;
      if (expectedUserId == null) {
        throw StateError('登录状态已失效，请重新登录');
      }
      final chart = await AstrologyService.calculate(widget.profile);
      final record = await AstrologyArchiveStore.save(
        widget.profile,
        isSelf: widget.isSelf,
        expectedUserId: expectedUserId,
      );
      if (mounted) {
        setState(() {
          _chart = chart;
          _record = record;
        });
      }
    } on AstrologyServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final chart = _chart;
    final record = _record;
    if (chart != null && record != null) {
      return AstrologyChartPage(
        profile: widget.profile,
        chart: chart,
        record: record,
        isSelf: widget.isSelf,
        professionalOnly: widget.professionalOnly,
      );
    }
    return Scaffold(
      backgroundColor: _softBackground,
      appBar: AppBar(
        backgroundColor: _softBackground,
        elevation: 0,
        title: const Text('星座星盘'),
      ),
      body: _error == null
          ? const _LoadingBody(label: '正在核算行星、宫位与相位…')
          : _ErrorBody(message: _error!, onRetry: _calculate),
    );
  }
}

class AstrologyInputPage extends StatefulWidget {
  const AstrologyInputPage({super.key, this.professionalOnlyResult = false});

  final bool professionalOnlyResult;

  @override
  State<AstrologyInputPage> createState() => _AstrologyInputPageState();
}

class _AstrologyInputPageState extends State<AstrologyInputPage> {
  final _name = TextEditingController();
  DateTime _birth = DateTime(2000, 1, 1, 12);
  Region? _place;
  bool? _isFemale;
  bool _pickedDate = false;

  @override
  void initState() {
    super.initState();
    RegionLoader.preload();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    await BirthDatePickerSheet.show(
      context,
      initialDate: _birth,
      onConfirm: (value) {
        if (value.isAfter(DateTime.now())) {
          showAppToast(context, '出生时间不能晚于当前时间');
          return;
        }
        setState(() {
          _birth = value;
          _pickedDate = true;
        });
      },
    );
  }

  Future<void> _pickPlace() async {
    await BirthPlacePickerSheet.show(
      context,
      title: '出生地',
      initialRegion: _place,
      onConfirm: (value) => setState(() => _place = value),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAppToast(context, '请填写对方的姓名或称呼');
      return;
    }
    if (!_pickedDate) {
      showAppToast(context, '请选择准确的出生日期时辰');
      return;
    }
    if (_isFemale == null) {
      showAppToast(context, '请选择性别，四种命盘将共用这份资料');
      return;
    }
    if (_place?.lng == null || _place?.lat == null) {
      showAppToast(context, '请选择出生地');
      return;
    }
    final profile = AstrologyProfile(
      name: name,
      birthDateTime: _birth,
      birthPlace: _place!.extPath,
      longitude: _place!.lng!,
      latitude: _place!.lat!,
      isFemale: _isFemale,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AstrologyChartLauncherPage(
          profile: profile,
          isSelf: false,
          professionalOnly: widget.professionalOnlyResult,
        ),
      ),
    );
  }

  String get _dateText =>
      '${_birth.year}-${_birth.month.toString().padLeft(2, '0')}-${_birth.day.toString().padLeft(2, '0')}  '
      '${_birth.hour.toString().padLeft(2, '0')}:${_birth.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBackground,
      appBar: AppBar(
        backgroundColor: _softBackground,
        elevation: 0,
        title: const Text('为他人排星盘'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AstrologyArchivePage(),
              ),
            ),
            child: const Text('命理档案'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '输入出生信息',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '必须精确到分钟并选择出生地，系统不会猜测缺失数据。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '档案名',
                    hintText: '姓名或称呼',
                    counterText: '',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.wc_rounded, color: _violet),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('性别')),
                    ChoiceChip(
                      label: const Text('男'),
                      selected: _isFemale == false,
                      onSelected: (_) => setState(() => _isFemale = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('女'),
                      selected: _isFemale == true,
                      onSelected: (_) => setState(() => _isFemale = true),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _InputTile(
                  icon: Icons.schedule_rounded,
                  title: '出生日期时辰',
                  value: _pickedDate ? _dateText : '点击选择（精确到分钟）',
                  onTap: _pickDate,
                ),
                const Divider(height: 1),
                _InputTile(
                  icon: Icons.location_on_outlined,
                  title: '出生地',
                  value: _place == null
                      ? '点击选择省 / 市 / 区县'
                      : _place!.extPath.replaceAll(' ', ' / '),
                  onTap: _pickPlace,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppButton(label: '开始排盘', onPressed: _submit),
          const CulturalReferenceNotice(),
        ],
      ),
    );
  }
}

class AstrologyChartPage extends StatefulWidget {
  const AstrologyChartPage({
    super.key,
    required this.profile,
    required this.chart,
    required this.record,
    required this.isSelf,
    this.professionalOnly = false,
    this.embedded = false,
    this.sharedChartLoader,
  });

  final AstrologyProfile profile;
  final AstrologyChartData chart;
  final AstrologyArchiveRecord record;
  final bool isSelf;
  final bool professionalOnly;
  final bool embedded;
  final Future<AstrologyChartData> Function(AstrologyChartType, DateTime, Region?)? sharedChartLoader;

  @override
  State<AstrologyChartPage> createState() => _AstrologyChartPageState();
}

class _AstrologyChartPageState extends State<AstrologyChartPage> {
  late final TextEditingController _caseTitle;
  late final TextEditingController _caseReasoning;
  late final TextEditingController _caseCommentary;
  final ScrollController _caseScroll = ScrollController();
  late final Future<int?> _caseOwner;
  bool _savingNote = false;
  late AstrologyChartData _activeChart;
  AstrologyChartType _selectedChartType = AstrologyChartType.natal;
  DateTime _targetDateTime = DateTime.now();
  AstrologyTimeStep _timeStep = AstrologyTimeStep.day;
  Region? _eventPlace;
  bool _chartLoading = false;
  int _chartRequest = 0;
  bool _showNote = false;

  @override
  void initState() {
    super.initState();
    _caseTitle = TextEditingController(
        text: widget.record.caseTitle.isEmpty
            ? '${widget.profile.name} · 档案笔记'
            : widget.record.caseTitle);
    _caseReasoning = TextEditingController(text: widget.record.reasoningNotes);
    _caseCommentary = TextEditingController(text: widget.record.commentary);
    _caseOwner = ArchiveAccountScope.currentUserId();
    _activeChart = widget.chart;
  }

  @override
  void dispose() {
    _caseTitle.dispose();
    _caseReasoning.dispose();
    _caseCommentary.dispose();
    _caseScroll.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_savingNote) return;
    if (_caseReasoning.text.trim().isEmpty &&
        _caseCommentary.text.trim().isEmpty) {
      showAppToast(context, '请先填写看盘判断或现实反馈');
      return;
    }
    _savingNote = true;
    try {
      final owner = await _caseOwner;
      if (owner == null) throw StateError('请登录后保存笔记');
      await AstrologyArchiveStore.updateCase(
        widget.record.id,
        caseTitle: _caseTitle.text,
        reasoningNotes: _caseReasoning.text,
        commentary: _caseCommentary.text,
        expectedUserId: owner,
      );
      if (mounted) showAppToast(context, '档案笔记已保存');
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，输入已保留，请确认账号和档案后重试');
    } finally {
      _savingNote = false;
    }
  }

  Future<void> _selectChartType(AstrologyChartType type) async {
    if (type == AstrologyChartType.natal) {
      _chartRequest++;
      setState(() {
        _selectedChartType = type;
        _activeChart = widget.chart;
        _chartLoading = false;
      });
      return;
    }

    if (type != _selectedChartType) {
      _timeStep = type.defaultTimeStep;
    }
    Region? place = _eventPlace;
    if (type.usesEventPlace) {
      Region? selected;
      await BirthPlacePickerSheet.show(
        context,
        title: type.placePickerTitle,
        initialRegion: place ?? (widget.sharedChartLoader != null && widget.profile.birthPlace.isEmpty ? null : widget.profile.region),
        onConfirm: (value) => selected = value,
      );
      if (!mounted || selected == null) return;
      place = selected;
      _eventPlace = selected;
    }
    final target = type == AstrologyChartType.current
        ? DateTime.now()
        : _targetDateTime;
    await _loadChart(type, target: target, place: place);
  }

  Future<void> _loadChart(
    AstrologyChartType type, {
    required DateTime target,
    Region? place,
  }) async {
    final request = ++_chartRequest;
    setState(() {
      _selectedChartType = type;
      _targetDateTime = target;
      _chartLoading = true;
    });
    try {
      final chart = widget.sharedChartLoader != null
          ? await widget.sharedChartLoader!(type, target, place)
          : await AstrologyService.calculate(widget.profile, chartType: type,
              targetDateTime: target, eventPlace: place);
      if (!mounted || request != _chartRequest) return;
      setState(() {
        _activeChart = chart;
        _chartLoading = false;
      });
    } on AstrologyServiceException catch (error) {
      if (!mounted || request != _chartRequest) return;
      setState(() => _chartLoading = false);
      showAppToast(context, error.message);
    }
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDateTime,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
      helpText: '选择推运日期',
    );
    if (picked == null || !mounted) return;
    final target = DateTime(
      picked.year,
      picked.month,
      picked.day,
      _targetDateTime.hour,
      _targetDateTime.minute,
    );
    await _loadChart(_selectedChartType, target: target, place: _eventPlace);
  }

  Future<void> _stepTargetDate(int direction) async {
    if (_chartLoading || !_selectedChartType.supportsTimeNavigation) return;
    await _loadChart(
      _selectedChartType,
      target: _timeStep.shift(_targetDateTime, direction),
      place: _eventPlace,
    );
  }

  void _changeTimeStep(AstrologyTimeStep value) {
    setState(() => _timeStep = value);
  }

  Future<void> _openSettings() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '宫制设置',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('切换后会使用同一出生资料重新计算'),
            ),
            RadioGroup<String>(
              groupValue: widget.profile.houseSystem,
              onChanged: (value) => Navigator.pop(context, value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in const [
                    ('P', '普拉西德宫制', '现代西洋占星常用'),
                    ('W', '整宫制', '每个星座对应一个完整宫位'),
                    ('E', '等宫制', '以上升点起每宫等分30°'),
                  ])
                    RadioListTile<String>(
                      value: item.$1,
                      title: Text(item.$2),
                      subtitle: Text(item.$3),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == null ||
        selected == widget.profile.houseSystem ||
        !mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AstrologyChartLauncherPage(
          profile: widget.profile.copyWith(houseSystem: selected),
          isSelf: widget.isSelf,
        ),
      ),
    );
  }

  Future<void> _selectArchive() async {
    final cases = await loadRoomChartCases();
    final rows = <AstrologyArchiveRecord>[
      for (final item in cases)
        if (item.archiveFor(RoomChartKind.astrology).unavailableReason == null)
          AstrologyArchiveRecord.fromJson(
            item.archiveFor(RoomChartKind.astrology).snapshot,
          ),
    ];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_add_alt_1_outlined),
                ),
                title: const Text('为他人排盘'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AstrologyInputPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEEF0FB),
                        child: Text(row.isSelf ? '我' : '${index + 1}'),
                      ),
                      title: Text(
                        row.isSelf
                            ? '${row.profile.name}（本人）'
                            : row.profile.name,
                      ),
                      subtitle: Text(_profileCaption(row.profile)),
                      trailing: row.id == widget.record.id
                          ? const Icon(Icons.check_circle, color: _violet)
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (row.id == widget.record.id) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => AstrologyChartLauncherPage(
                              profile: row.profile,
                              isSelf: row.isSelf,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              ListTile(
                title: const Text('管理全部命理档案'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AstrologyArchivePage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _softBackground,
        appBar: widget.embedded ? null : AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: widget.professionalOnly,
          toolbarHeight: 68,
          titleSpacing: 14,
          title: widget.professionalOnly
              ? Text('${widget.profile.name} · 星盘专业盘')
              : _ArchiveSelectorButton(
                  profile: widget.profile,
                  isSelf: widget.isSelf,
                  onTap: _selectArchive,
                ),
          actions: [
            const AppShareMoreButton(
              toolRoute: '/home_astrology',
              title: '星盘专业排盘',
              shareText: '玄遇提供星盘专业排盘工具，可创建案例并查看专业盘面。',
            ),
            if (!widget.professionalOnly) ...[
              IconButton(
                tooltip: '档案笔记',
                onPressed: () => setState(() => _showNote = !_showNote),
                icon: const Icon(Icons.note_alt_outlined),
              ),
              IconButton(
                tooltip: '宫制设置',
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ],
          bottom: widget.professionalOnly
              ? null
              : const PreferredSize(
                  preferredSize: Size.fromHeight(48),
                  child: TabBar(
                    labelColor: _navy,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: _violet,
                    indicatorWeight: 3,
                    tabs: [
                      Tab(text: '个人解读'),
                      Tab(text: '专业星盘'),
                    ],
                  ),
                ),
        ),
        body: Stack(
          children: [
            if (widget.professionalOnly)
              _ProfessionalChart(
                chart: _activeChart,
                selectedType: _selectedChartType,
                houseSystem: widget.profile.houseSystem,
                targetDateTime: _targetDateTime,
                timeStep: _timeStep,
                eventPlace: _eventPlace,
                loading: _chartLoading,
                onTypeSelected: _selectChartType,
                onTargetDateTap: _pickTargetDate,
                onTimeStepChanged: _changeTimeStep,
                onStepPrevious: () => _stepTargetDate(-1),
                onStepNext: () => _stepTargetDate(1),
              )
            else
              TabBarView(
                children: [
                  AstrologyPersonalReading(chart: widget.chart),
                  _ProfessionalChart(
                    chart: _activeChart,
                    selectedType: _selectedChartType,
                    houseSystem: widget.profile.houseSystem,
                    targetDateTime: _targetDateTime,
                    timeStep: _timeStep,
                    eventPlace: _eventPlace,
                    loading: _chartLoading,
                    onTypeSelected: _selectChartType,
                    onTargetDateTap: _pickTargetDate,
                    onTimeStepChanged: _changeTimeStep,
                    onStepPrevious: () => _stepTargetDate(-1),
                    onStepNext: () => _stepTargetDate(1),
                  ),
                ],
              ),
            if (!widget.professionalOnly && _showNote)
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
                  child: ChartCaseNotebook(
                    scrollController: _caseScroll,
                    titleController: _caseTitle,
                    reasoningController: _caseReasoning,
                    commentaryController: _caseCommentary,
                    onSave: _saveNote,
                    onClose: () => setState(() => _showNote = false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AstrologyArchivePage extends StatelessWidget {
  const AstrologyArchivePage({super.key});
  @override
  Widget build(BuildContext context) => ChartArchivePage(
        kind: RoomChartKind.astrology,
        createPage: (_) => const AstrologyInputPage(),
        openPage: (archive) => AstrologyChartLauncherPage(
          profile: AstrologyProfile.fromJson(
              Map<String, dynamic>.from(archive.snapshot['profile'] as Map)),
          isSelf: archive.snapshot['isSelf'] == true,
        ),
      );
}

class _ArchiveSelectorButton extends StatelessWidget {
  const _ArchiveSelectorButton({
    required this.profile,
    required this.isSelf,
    required this.onTap,
  });
  final AstrologyProfile profile;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim();
    final displayName = name.isEmpty ? '我的星盘' : name;
    final initial = String.fromCharCode(displayName.runes.first);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE6F2F1),
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF294849),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              isSelf ? '$displayName · 本人' : displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF171A20),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF171A20),
            size: 24,
          ),
        ],
      ),
    );
  }
}

class _ProfessionalChart extends StatelessWidget {
  const _ProfessionalChart({
    required this.chart,
    required this.selectedType,
    required this.houseSystem,
    required this.targetDateTime,
    required this.timeStep,
    required this.eventPlace,
    required this.loading,
    required this.onTypeSelected,
    required this.onTargetDateTap,
    required this.onTimeStepChanged,
    required this.onStepPrevious,
    required this.onStepNext,
  });

  final AstrologyChartData chart;
  final AstrologyChartType selectedType;
  final String houseSystem;
  final DateTime targetDateTime;
  final AstrologyTimeStep timeStep;
  final Region? eventPlace;
  final bool loading;
  final ValueChanged<AstrologyChartType> onTypeSelected;
  final VoidCallback onTargetDateTap;
  final ValueChanged<AstrologyTimeStep> onTimeStepChanged;
  final VoidCallback onStepPrevious;
  final VoidCallback onStepNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
      children: [
        if (loading) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 6),
        ],
        _ChartActionBar(
          chart: chart,
          selectedType: selectedType,
          eventPlace: eventPlace,
          loading: loading,
          onSelected: onTypeSelected,
        ),
        const SizedBox(height: 8),
        _ChartBasisBar(houseSystem: houseSystem),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              key: const ValueKey('astrology-chart-stage'),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDDE2EA)),
              ),
              child: AstrologyChartWheel(chart: chart),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const _ChartAspectLegend(),
        if (chart.firdaria.isNotEmpty) ...[
          const SizedBox(height: 8),
          _FirdariaCurrentCard(periods: chart.firdaria),
        ],
        if (selectedType.supportsTimeNavigation) ...[
          const SizedBox(height: 8),
          _ChartTimelineBar(
            targetDateTime: chart.targetDateTime ?? targetDateTime,
            step: timeStep,
            loading: loading,
            onDateTap: onTargetDateTap,
            onStepChanged: onTimeStepChanged,
            onPrevious: onStepPrevious,
            onNext: onStepNext,
          ),
        ],
        const SizedBox(height: 10),
        _ChartSummaryCard(chart: chart, selectedType: selectedType),
        const SizedBox(height: 16),
        Text(
          chart.disclaimer,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ChartBasisBar extends StatelessWidget {
  const _ChartBasisBar({required this.houseSystem});

  final String houseSystem;

  String get _houseSystemLabel => switch (houseSystem) {
    'W' => '整宫制',
    'E' => '等宫制',
    _ => '普拉西德宫制',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          const _ChartBasisTag('热带黄道'),
          const _ChartBasisTag('地心视黄经'),
          _ChartBasisTag(_houseSystemLabel),
        ],
      ),
    );
  }
}

class _ChartBasisTag extends StatelessWidget {
  const _ChartBasisTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5F7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5C697C),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChartAspectLegend extends StatelessWidget {
  const _ChartAspectLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ChartAspectLegendItem('合相', Color(0xFF16AAA7)),
          _ChartAspectLegendItem('对冲', Color(0xFFD86870)),
          _ChartAspectLegendItem('刑相', Color(0xFFD86870)),
          _ChartAspectLegendItem('拱相', Color(0xFF467CC7)),
          _ChartAspectLegendItem('六合', Color(0xFF467CC7)),
        ],
      ),
    );
  }
}

class _ChartAspectLegendItem extends StatelessWidget {
  const _ChartAspectLegendItem(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 1.5, color: color),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: _navy, fontSize: 9.5)),
      ],
    );
  }
}

class _FirdariaCurrentCard extends StatelessWidget {
  const _FirdariaCurrentCard({required this.periods});

  final List<AstrologyTimePeriod> periods;

  @override
  Widget build(BuildContext context) {
    final active = periods.where((item) => item.active).toList();
    return Container(
      key: const ValueKey('astrology-firdaria-current'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDEBEA)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF209E99),
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                '当前法达',
                style: TextStyle(
                  color: _navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前日期暂无对应周期',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            for (final item in active) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: item.level == 1
                          ? const Color(0xFF209E99)
                          : const Color(0xFF7566B8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item.level == 1
                          ? '${item.planetName}主限'
                          : '${item.planetName}副限',
                      style: TextStyle(
                        color: item.level == 1
                            ? const Color(0xFF167F7B)
                            : const Color(0xFF6556A8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_dateOnly(item.startDate)}—${_dateOnly(item.endDate)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _ChartTimelineBar extends StatelessWidget {
  const _ChartTimelineBar({
    required this.targetDateTime,
    required this.step,
    required this.loading,
    required this.onDateTap,
    required this.onStepChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime targetDateTime;
  final AstrologyTimeStep step;
  final bool loading;
  final VoidCallback onDateTap;
  final ValueChanged<AstrologyTimeStep> onStepChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    const divider = SizedBox(
      height: 30,
      child: VerticalDivider(width: 1, color: Color(0xFFE4E9EF)),
    );
    return Material(
      key: const ValueKey('astrology-timeline-bar'),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFFDDE7E8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('astrology-time-previous'),
              tooltip: '上一时段',
              onPressed: loading ? null : onPrevious,
              color: const Color(0xFF238F8B),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            divider,
            Expanded(
              flex: 5,
              child: InkWell(
                onTap: loading ? null : onDateTap,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _dateTimeText(targetDateTime),
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            divider,
            Expanded(
              flex: 4,
              child: PopupMenuButton<AstrologyTimeStep>(
                enabled: !loading,
                initialValue: step,
                onSelected: onStepChanged,
                itemBuilder: (context) => [
                  for (final value in AstrologyTimeStep.values)
                    PopupMenuItem(
                      value: value,
                      child: Text('间隔${value.label}'),
                    ),
                ],
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '间隔${step.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 19,
                        color: Color(0xFF238F8B),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            divider,
            IconButton(
              key: const ValueKey('astrology-time-next'),
              tooltip: '下一时段',
              onPressed: loading ? null : onNext,
              color: const Color(0xFF238F8B),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartSummaryCard extends StatelessWidget {
  const _ChartSummaryCard({required this.chart, required this.selectedType});

  final AstrologyChartData chart;
  final AstrologyChartType selectedType;

  @override
  Widget build(BuildContext context) {
    final sun = chart.position('Sun');
    final moon = chart.position('Moon');
    final ascendant = chart.ascendant;
    final midheaven = chart.midheaven;
    final overview = chart.summary.trim().isEmpty
        ? '太阳${sun.sign} · 月亮${moon.sign} · 上升${ascendant.sign}'
        : chart.summary.trim();
    final items = <({String label, String value, Color color})>[
      (
        label: '太阳',
        value: '${sun.sign}${sun.degreeText}',
        color: const Color(0xFFC45E68),
      ),
      (
        label: '月亮',
        value: '${moon.sign}${moon.degreeText}',
        color: const Color(0xFF6474C5),
      ),
      (
        label: '上升',
        value: '${ascendant.sign}${ascendant.degreeText}',
        color: const Color(0xFF2AAFA8),
      ),
      (
        label: '天顶',
        value: '${midheaven.sign}${midheaven.degreeText}',
        color: const Color(0xFF8C68BA),
      ),
    ];

    return Container(
      key: const ValueKey('astrology-chart-summary'),
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBF2)),
      ),
      child: Column(
        children: [
          Text(
            '${selectedType.label}概览',
            style: const TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(child: _ChartSummaryItem(item: items[index])),
                if (index != items.length - 1)
                  Container(
                    width: 1,
                    height: 46,
                    color: const Color(0xFFE7EBF2),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartSummaryItem extends StatelessWidget {
  const _ChartSummaryItem({required this.item});

  final ({String label, String value, Color color}) item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          item.label,
          style: TextStyle(
            color: item.color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ChartActionBar extends StatelessWidget {
  const _ChartActionBar({
    required this.chart,
    required this.selectedType,
    required this.eventPlace,
    required this.loading,
    required this.onSelected,
  });

  final AstrologyChartData chart;
  final AstrologyChartType selectedType;
  final Region? eventPlace;
  final bool loading;
  final ValueChanged<AstrologyChartType> onSelected;

  Future<void> _showTypePicker(BuildContext context) async {
    final picked = await showModalBottomSheet<AstrologyChartType>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择盘型',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: AstrologyChartType.values
                    .map(
                      (type) => ChoiceChip(
                        label: Text(type.label),
                        selected: selectedType == type,
                        onSelected: (_) => Navigator.pop(sheetContext, type),
                        showCheckmark: false,
                        side: BorderSide(
                          color: selectedType == type
                              ? const Color(0xFF48B8CA)
                              : const Color(0xFFD7DCE5),
                        ),
                        selectedColor: const Color(0xFFE4F9FC),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: selectedType == type
                              ? const Color(0xFF36A9BC)
                              : AppColors.textSecondary,
                          fontWeight: selectedType == type
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onSelected(picked);
  }

  Future<void> _showParameters(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: DefaultTabController(
            length: chart.firdaria.isEmpty ? 3 : 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded, color: _violet),
                      SizedBox(width: 10),
                      Text(
                        '星盘参数',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  isScrollable: chart.firdaria.isNotEmpty,
                  tabAlignment: chart.firdaria.isNotEmpty
                      ? TabAlignment.start
                      : TabAlignment.fill,
                  labelColor: _navy,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: _violet,
                  tabs: [
                    const Tab(text: '行星落宫'),
                    const Tab(text: '宫位'),
                    const Tab(text: '相位'),
                    if (chart.firdaria.isNotEmpty) const Tab(text: '法达周期'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (chart.hasComparison)
                            _ParameterSectionHeader(
                              label: '${chart.activeLabel}星体',
                              color: const Color(0xFF42B8C5),
                            ),
                          for (final item in chart.planets)
                            _DataRow(
                              leading: _planetCompactLabel(item),
                              title: item.name,
                              value:
                                  '${item.sign}${item.degreeText}${item.house == null ? '' : ' · 第${item.house}宫'}${item.retrograde ? ' 逆行' : ''}',
                            ),
                          if (chart.hasComparison)
                            _ParameterSectionHeader(
                              label: '${chart.comparisonLabel}星体',
                              color: const Color(0xFF8D76CA),
                            ),
                          for (final item in chart.comparisonPlanets)
                            _DataRow(
                              leading: _planetCompactLabel(item),
                              title: item.name,
                              value:
                                  '${item.sign}${item.degreeText} · 第${item.house}宫${item.retrograde ? ' 逆行' : ''}',
                            ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          _DataRow(
                            leading: '升',
                            title: '上升点',
                            value:
                                '${chart.ascendant.sign}${chart.ascendant.degreeText}',
                          ),
                          _DataRow(
                            leading: '顶',
                            title: '天顶',
                            value:
                                '${chart.midheaven.sign}${chart.midheaven.degreeText}',
                          ),
                          for (final item in chart.houses)
                            _DataRow(
                              leading: '${item.house ?? ''}',
                              title: item.name.isEmpty
                                  ? '第${item.house ?? ''}宫宫头'
                                  : item.name,
                              value: '${item.sign}${item.degreeText}',
                            ),
                        ],
                      ),
                      chart.aspects.isEmpty && chart.crossAspects.isEmpty
                          ? const Center(child: Text('暂无主要相位'))
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                if (chart.crossAspects.isNotEmpty)
                                  _ParameterSectionHeader(
                                    label:
                                        '${chart.comparisonLabel} × ${chart.activeLabel} 跨盘相位',
                                    color: const Color(0xFF8D76CA),
                                  ),
                                for (final item in chart.crossAspects)
                                  _DataRow(
                                    leading: _aspectCompactLabel(item),
                                    title:
                                        '本命${item.body1Name} ${item.typeName} ${chart.activeLabel}${item.body2Name}',
                                    value:
                                        '${item.orb.toStringAsFixed(2)}° · ${_aspectMotionLabel(item)}',
                                  ),
                                if (chart.aspects.isNotEmpty)
                                  _ParameterSectionHeader(
                                    label: chart.hasComparison
                                        ? '${chart.activeLabel}盘内相位'
                                        : '盘内相位',
                                    color: const Color(0xFF42B8C5),
                                  ),
                                for (final item in chart.aspects)
                                  _DataRow(
                                    leading: _aspectCompactLabel(item),
                                    title:
                                        '${item.body1Name} ${item.typeName} ${item.body2Name}',
                                    value:
                                        '${item.orb.toStringAsFixed(2)}° · ${_aspectMotionLabel(item)}',
                                  ),
                              ],
                            ),
                      if (chart.firdaria.isNotEmpty)
                        ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            for (final item in chart.firdaria)
                              _DataRow(
                                leading: item.level == 1 ? '主' : '副',
                                title: item.level == 1
                                    ? '${item.planetName}主限'
                                    : '${item.majorPlanetName} · ${item.planetName}副限',
                                value:
                                    '${_dateOnly(item.startDate)}—${_dateOnly(item.endDate)}',
                                highlighted: item.active,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: loading ? null : () => _showTypePicker(context),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              label: Text(
                selectedType.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (selectedType.usesEventPlace)
            Expanded(
              child: TextButton.icon(
                onPressed: loading ? null : () => onSelected(selectedType),
                icon: const Icon(Icons.place_outlined, size: 17),
                label: Text(
                  eventPlace?.name ??
                      (chart.targetPlace.trim().isEmpty
                          ? '选择地点'
                          : chart.targetPlace.split(RegExp(r'\s+')).last),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          TextButton.icon(
            key: const ValueKey('astrology-parameter-button'),
            onPressed: () => _showParameters(context),
            icon: const Icon(Icons.grid_view_rounded),
            label: const Text('参数'),
          ),
        ],
      ),
    );
  }
}

String _dateOnly(DateTime? value) {
  if (value == null) return '--';
  return '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
}

String _dateTimeText(DateTime value) =>
    '${_dateOnly(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _planetCompactLabel(AstrologyPosition planet) {
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
      (planet.name.isEmpty ? '星' : planet.name.substring(0, 1));
}

String _aspectCompactLabel(AstrologyAspect aspect) => switch (aspect.type) {
  'Conjunction' => '合',
  'Opposition' => '冲',
  'Square' => '刑',
  'Trine' => '拱',
  'Sextile' => '六合',
  _ => aspect.typeName.isEmpty ? '相' : aspect.typeName.substring(0, 1),
};

String _aspectMotionLabel(AstrologyAspect aspect) => switch (aspect.applying) {
  true => '入相',
  false => '出相',
  null => '动态未判定',
};


class _ParameterSectionHeader extends StatelessWidget {
  const _ParameterSectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: const Color(0xFFF7F9FC),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.leading,
    required this.title,
    required this.value,
    this.highlighted = false,
  });
  final String leading;
  final String title;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFEAF8F5) : null,
        border: const Border(top: BorderSide(color: Color(0xFFF0F2F7))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              leading,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _violet,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputTile extends StatelessWidget {
  const _InputTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(icon, color: _violet),
      title: Text(title),
      subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: _violet),
        const SizedBox(height: 18),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ),
  );
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42, color: _violet),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton(onPressed: onRetry, child: const Text('重新计算')),
        ],
      ),
    ),
  );
}

String _profileCaption(AstrologyProfile profile) =>
    '${profile.birthDateTime.year}-${profile.birthDateTime.month.toString().padLeft(2, '0')}-${profile.birthDateTime.day.toString().padLeft(2, '0')} '
    '${profile.birthDateTime.hour.toString().padLeft(2, '0')}:${profile.birthDateTime.minute.toString().padLeft(2, '0')} · '
    '${profile.birthPlace.replaceAll(' ', ' / ')}';
