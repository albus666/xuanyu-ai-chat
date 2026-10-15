import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/local/archive_account_scope.dart';
import '../../../core/profile/account_birth_profile.dart';
import '../../../core/theme/app_colors.dart';
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
import 'qizheng_archive_store.dart';
import 'qizheng_chart_wheel.dart';
import 'qizheng_models.dart';
import 'qizheng_personal_reading.dart';
import 'qizheng_service.dart';

const _ink = Color(0xFF202B45);
const _jade = AppColors.primary;
const _gold = Color(0xFF7768D8);
const _softBackground = Color(0xFFF5F7FC);

class QizhengEntryPage extends StatefulWidget {
  const QizhengEntryPage({super.key});

  @override
  State<QizhengEntryPage> createState() => _QizhengEntryPageState();
}

class _QizhengEntryPageState extends State<QizhengEntryPage> {
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
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await AccountBirthProfileRepository.load(
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _account = profile;
        _loading = false;
      });
      if (profile.isAstrologyComplete) {
        await _open(QizhengProfile.fromAccount(profile), isSelf: true);
      }
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '本人资料读取失败，请稍后重试';
      });
    }
  }

  Future<void> _complete() async {
    final profile = await AccountBirthProfileRepository.ensureAstrology(
      context,
    );
    if (profile == null || !mounted) return;
    setState(() => _account = profile);
    await _open(QizhengProfile.fromAccount(profile), isSelf: true);
  }

  Future<void> _open(QizhengProfile profile, {required bool isSelf}) async {
    if (_opening || !mounted) return;
    setState(() => _opening = true);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            QizhengChartLauncherPage(profile: profile, isSelf: isSelf),
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
        title: const Text('七政四余'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QizhengArchivePage(),
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
                        width: 82,
                        height: 82,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF174C4A), Color(0xFFB99950)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.brightness_7_outlined,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _error ?? '以七政、四余与二十八宿排出东方星命盘',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error ??
                            ((_account?.isComplete ?? false)
                                ? '出生日期时辰已读取，再确认出生地即可计算命宫与命度。'
                                : '需要精确出生时辰与出生地；资料缺失时不会猜测排盘。'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppButton(
                        label: _error == null ? '完善资料并排盘' : '重新加载',
                        onPressed: _error == null ? _complete : _load,
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const QizhengInputPage(),
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

class QizhengInputPage extends StatefulWidget {
  const QizhengInputPage({super.key, this.professionalOnlyResult = false});

  final bool professionalOnlyResult;

  @override
  State<QizhengInputPage> createState() => _QizhengInputPageState();
}

class _QizhengInputPageState extends State<QizhengInputPage> {
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QizhengChartLauncherPage(
          profile: QizhengProfile(
            name: name,
            birthDateTime: _birth,
            birthPlace: _place!.extPath,
            longitude: _place!.lng!,
            latitude: _place!.lat!,
            isFemale: _isFemale,
          ),
          isSelf: false,
          professionalOnly: widget.professionalOnlyResult,
        ),
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
        title: const Text('为他人排七政盘'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '输入出生信息',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            '七政立命必须精确到分钟并选择出生地，资料缺失时停止计算。',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
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
                    const Icon(Icons.wc_rounded, color: _jade),
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
                  value: _pickedDate ? _formatDateTime(_birth) : '点击选择（精确到分钟）',
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

class QizhengChartLauncherPage extends StatefulWidget {
  const QizhengChartLauncherPage({
    super.key,
    required this.profile,
    required this.isSelf,
    this.professionalOnly = false,
  });

  final QizhengProfile profile;
  final bool isSelf;
  final bool professionalOnly;

  @override
  State<QizhengChartLauncherPage> createState() =>
      _QizhengChartLauncherPageState();
}

class _QizhengChartLauncherPageState extends State<QizhengChartLauncherPage> {
  QizhengChartData? _chart;
  QizhengArchiveRecord? _record;
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
      final chart = await QizhengService.calculate(widget.profile);
      final record = await QizhengArchiveStore.save(
        widget.profile,
        isSelf: widget.isSelf,
        expectedUserId: expectedUserId,
      );
      if (!mounted) return;
      setState(() {
        _chart = chart;
        _record = record;
      });
    } on QizhengServiceException catch (error) {
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
      return QizhengChartPage(
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
        title: const Text('七政四余'),
      ),
      body: _error == null
          ? const _LoadingBody(label: '正在核算七政、四余与二十八宿…')
          : _ErrorBody(message: _error!, onRetry: _calculate),
    );
  }
}

class QizhengChartPage extends StatefulWidget {
  const QizhengChartPage({
    super.key,
    required this.profile,
    required this.chart,
    required this.record,
    required this.isSelf,
    this.professionalOnly = false,
    this.embedded = false,
    this.sharedChartLoader,
  });

  final QizhengProfile profile;
  final QizhengChartData chart;
  final QizhengArchiveRecord record;
  final bool isSelf;
  final bool professionalOnly;
  final bool embedded;
  final Future<QizhengChartData> Function(QizhengChartType, DateTime, QizhengNodeMode, QizhengLifeMode)? sharedChartLoader;

  @override
  State<QizhengChartPage> createState() => _QizhengChartPageState();
}

class _QizhengChartPageState extends State<QizhengChartPage> {
  late final TextEditingController _caseTitle;
  late final TextEditingController _caseReasoning;
  late final TextEditingController _caseCommentary;
  final ScrollController _caseScroll = ScrollController();
  late final Future<int?> _caseOwner;
  bool _savingNote = false;
  late QizhengChartData _activeChart;
  QizhengChartType _selectedType = QizhengChartType.natal;
  QizhengNodeMode _nodeMode = QizhengNodeMode.trueNode;
  QizhengLifeMode _lifeMode = QizhengLifeMode.ascSunLock;
  QizhengTimeStep _timeStep = QizhengTimeStep.day;
  DateTime _target = DateTime.now();
  bool _chartLoading = false;
  bool _showNote = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _activeChart = widget.chart;
    _nodeMode = QizhengNodeMode.fromCode(
      widget.chart.calculation['nodeMode']?.toString(),
    );
    _lifeMode = QizhengLifeMode.fromCode(
      widget.chart.calculation['lifeMode']?.toString(),
    );
    _caseTitle = TextEditingController(
        text: widget.record.caseTitle.isEmpty
            ? '${widget.profile.name} · 档案笔记'
            : widget.record.caseTitle);
    _caseReasoning = TextEditingController(text: widget.record.reasoningNotes);
    _caseCommentary = TextEditingController(text: widget.record.commentary);
    _caseOwner = ArchiveAccountScope.currentUserId();
  }

  @override
  void dispose() {
    _caseTitle.dispose();
    _caseReasoning.dispose();
    _caseCommentary.dispose();
    _caseScroll.dispose();
    super.dispose();
  }

  Future<void> _loadChart(
    QizhengChartType type, {
    DateTime? target,
    QizhengNodeMode? mode,
    QizhengLifeMode? lifeMode,
  }) async {
    if (type == QizhengChartType.natal &&
        (mode ?? _nodeMode) == QizhengNodeMode.trueNode &&
        (lifeMode ?? _lifeMode) == QizhengLifeMode.ascSunLock) {
      _request++;
      setState(() {
        _selectedType = type;
        _nodeMode = mode ?? _nodeMode;
        _lifeMode = lifeMode ?? _lifeMode;
        _activeChart = widget.chart;
        _chartLoading = false;
      });
      return;
    }
    final request = ++_request;
    final targetValue =
        target ?? (type == QizhengChartType.current ? DateTime.now() : _target);
    setState(() {
      _selectedType = type;
      _target = targetValue;
      _nodeMode = mode ?? _nodeMode;
      _lifeMode = lifeMode ?? _lifeMode;
      _chartLoading = true;
    });
    try {
      final chart = widget.sharedChartLoader != null
          ? await widget.sharedChartLoader!(type, targetValue, _nodeMode, _lifeMode)
          : await QizhengService.calculate(widget.profile, chartType: type,
              nodeMode: _nodeMode, lifeMode: _lifeMode, targetDateTime: targetValue);
      if (!mounted || request != _request) return;
      setState(() {
        _activeChart = chart;
        _chartLoading = false;
      });
    } on QizhengServiceException catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _chartLoading = false);
      showAppToast(context, error.message);
    }
  }

  Future<void> _chooseType() async {
    final selected = await showModalBottomSheet<QizhengChartType>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择盘型',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '不同盘型均由七政四余引擎按对应时刻重新计算',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final type in QizhengChartType.values)
                    ChoiceChip(
                      label: Text(type.label),
                      selected: type == _selectedType,
                      selectedColor: const Color(0xFFDDF2EE),
                      side: BorderSide(
                        color: type == _selectedType
                            ? _jade
                            : const Color(0xFFD9E2DF),
                      ),
                      onSelected: (_) => Navigator.pop(context, type),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected != _selectedType) _timeStep = selected.defaultStep;
    await _loadChart(
      selected,
      target: selected == QizhengChartType.current ? DateTime.now() : _target,
    );
  }

  Future<void> _pickTarget() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _target,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
      helpText: '选择推运日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_target),
      helpText: '选择推运时刻',
    );
    if (time == null || !mounted) return;
    await _loadChart(
      _selectedType,
      target: DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<void> _step(int direction) async {
    if (_chartLoading || !_selectedType.supportsTimeNavigation) return;
    await _loadChart(
      _selectedType,
      target: _timeStep.shift(_target, direction),
    );
  }

  Future<void> _settings() async {
    var draftNode = _nodeMode;
    var draftLife = _lifeMode;
    final selected =
        await showModalBottomSheet<
          ({QizhengNodeMode node, QizhengLifeMode life})
        >(
          context: context,
          backgroundColor: Colors.white,
          showDragHandle: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '算法取法',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '流派差异写入盘面算法信息，不会静默混算',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '立命法',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    RadioGroup<QizhengLifeMode>(
                      groupValue: draftLife,
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => draftLife = value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final life in QizhengLifeMode.values)
                            RadioListTile<QizhengLifeMode>(
                              contentPadding: EdgeInsets.zero,
                              value: life,
                              activeColor: _jade,
                              title: Text(life.label),
                              subtitle: Text(life.description),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 24),
                    const Text(
                      '罗计取法',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    RadioGroup<QizhengNodeMode>(
                      groupValue: draftNode,
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => draftNode = value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final node in QizhengNodeMode.values)
                            RadioListTile<QizhengNodeMode>(
                              contentPadding: EdgeInsets.zero,
                              value: node,
                              activeColor: _jade,
                              title: Text(node.label),
                              subtitle: Text(node.description),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, (
                          node: draftNode,
                          life: draftLife,
                        )),
                        style: FilledButton.styleFrom(backgroundColor: _jade),
                        child: const Text('应用并重新排盘'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    if (selected == null || !mounted) return;
    if (selected.node == _nodeMode && selected.life == _lifeMode) return;
    await _loadChart(
      _selectedType,
      target: _target,
      mode: selected.node,
      lifeMode: selected.life,
    );
  }

  Future<void> _selectArchive() async {
    final cases = await loadRoomChartCases();
    final rows = <QizhengArchiveRecord>[
      for (final item in cases)
        if (item.archiveFor(RoomChartKind.qizheng).unavailableReason == null)
          QizhengArchiveRecord.fromJson(
            item.archiveFor(RoomChartKind.qizheng).snapshot,
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
            maxHeight: MediaQuery.sizeOf(context).height * .68,
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
                      builder: (_) => const QizhengInputPage(),
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
                        backgroundColor: const Color(0xFFE4F1EE),
                        foregroundColor: _ink,
                        child: Text(row.isSelf ? '我' : '${index + 1}'),
                      ),
                      title: Text(
                        row.isSelf
                            ? '${row.profile.name}（本人）'
                            : row.profile.name,
                      ),
                      subtitle: Text(_profileCaption(row.profile)),
                      trailing: row.id == widget.record.id
                          ? const Icon(Icons.check_circle, color: _jade)
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (row.id == widget.record.id) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => QizhengChartLauncherPage(
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
                      builder: (_) => const QizhengArchivePage(),
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
      await QizhengArchiveStore.updateCase(
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _softBackground,
        appBar: widget.embedded ? null : AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          titleSpacing: 8,
          title: widget.professionalOnly
              ? Text('${widget.profile.name} · 七政专业盘')
              : InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _selectArchive,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE4F1EE),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.profile.name.characters.first,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            widget.isSelf
                                ? '${widget.profile.name} · 本人'
                                : widget.profile.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
          actions: [
            const AppShareMoreButton(
              toolRoute: '/home_qizheng',
              title: '七政四余专业排盘',
              shareText: '玄遇提供七政四余专业排盘工具，可创建案例并查看专业盘面。',
            ),
            if (!widget.professionalOnly) ...[
              IconButton(
                tooltip: '档案笔记',
                onPressed: () => setState(() => _showNote = !_showNote),
                icon: const Icon(Icons.note_alt_outlined),
              ),
              IconButton(
                tooltip: '算法设置',
                onPressed: _settings,
                icon: const Icon(Icons.tune_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ],
          bottom: widget.professionalOnly
              ? null
              : const PreferredSize(
                  preferredSize: Size.fromHeight(48),
                  child: TabBar(
                    labelColor: _ink,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: _jade,
                    indicatorWeight: 3,
                    tabs: [
                      Tab(text: '个人解读'),
                      Tab(text: '专业命盘'),
                    ],
                  ),
                ),
        ),
        body: Stack(
          children: [
            if (widget.professionalOnly)
              _ProfessionalChart(
                chart: _activeChart,
                selectedType: _selectedType,
                target: _target,
                step: _timeStep,
                loading: _chartLoading,
                onChooseType: _chooseType,
                onParameters: () => _showParameters(context, _activeChart),
                onPickDate: _pickTarget,
                onStepChanged: (value) => setState(() => _timeStep = value),
                onPrevious: () => _step(-1),
                onNext: () => _step(1),
              )
            else
              TabBarView(
                children: [
                  QizhengPersonalReading(chart: _activeChart),
                  _ProfessionalChart(
                    chart: _activeChart,
                    selectedType: _selectedType,
                    target: _target,
                    step: _timeStep,
                    loading: _chartLoading,
                    onChooseType: _chooseType,
                    onParameters: () => _showParameters(context, _activeChart),
                    onPickDate: _pickTarget,
                    onStepChanged: (value) => setState(() => _timeStep = value),
                    onPrevious: () => _step(-1),
                    onNext: () => _step(1),
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

class _ProfessionalChart extends StatelessWidget {
  const _ProfessionalChart({
    required this.chart,
    required this.selectedType,
    required this.target,
    required this.step,
    required this.loading,
    required this.onChooseType,
    required this.onParameters,
    required this.onPickDate,
    required this.onStepChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final QizhengChartData chart;
  final QizhengChartType selectedType;
  final DateTime target;
  final QizhengTimeStep step;
  final bool loading;
  final VoidCallback onChooseType;
  final VoidCallback onParameters;
  final VoidCallback onPickDate;
  final ValueChanged<QizhengTimeStep> onStepChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('qizheng-professional-chart'),
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF172C61),
                          Color(0xFF101F49),
                          Color(0xFF0A1735),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: const Color(0xFF6DE1DA).withValues(alpha: .2),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F243A72),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _StarCardBackdropPainter(),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            _ChartCardHeader(chart: chart),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                                child: Center(
                                  child: RepaintBoundary(
                                    child: QizhengChartWheel(chart: chart),
                                  ),
                                ),
                              ),
                            ),
                            _ChartFacts(chart: chart),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (loading)
                Positioned.fill(
                  child: ColoredBox(
                    color: _softBackground.withValues(alpha: .74),
                    child: const Center(
                      child: CircularProgressIndicator(color: _jade),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE0E9E6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: onChooseType,
                  icon: const Icon(Icons.grid_view_rounded, size: 19),
                  label: Text('${selectedType.label}  ▾'),
                ),
              ),
              Container(width: 1, height: 24, color: const Color(0xFFE3E9E7)),
              Expanded(
                child: TextButton.icon(
                  onPressed: onParameters,
                  icon: const Icon(Icons.table_chart_outlined, size: 20),
                  label: const Text('盘面参数'),
                ),
              ),
            ],
          ),
        ),
        if (selectedType.supportsTimeNavigation)
          _TimelineBar(
            target: target,
            step: step,
            onPickDate: onPickDate,
            onStepChanged: onStepChanged,
            onPrevious: onPrevious,
            onNext: onNext,
          )
        else
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 10,
            ),
            child: const Text(
              '本命盘固定为出生时刻 · 切换流年、流月或流日可调整时间',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
          ),
      ],
    );
  }
}

class _ChartCardHeader extends StatelessWidget {
  const _ChartCardHeader({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    final lifeMethod = chart.calculation['lifeMethod']?.toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 2),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chart.chartTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (lifeMethod != null && lifeMethod.isNotEmpty)
                Text(
                  lifeMethod,
                  style: const TextStyle(
                    color: Color(0xFFA9B7D4),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF58DDD4).withValues(alpha: .11),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF58DDD4).withValues(alpha: .32),
              ),
            ),
            child: const Text(
              'DE440 · 今宿',
              style: TextStyle(
                color: Color(0xFF79E8E0),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarCardBackdropPainter extends CustomPainter {
  const _StarCardBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < 34; index++) {
      final x = ((index * 47) % 101) / 100 * size.width;
      final y = ((index * 83) % 97) / 96 * size.height;
      final bright = index % 8 == 0;
      canvas.drawCircle(
        Offset(x, y),
        bright ? .8 : .4,
        Paint()
          ..color = (bright ? const Color(0xFF58DDD4) : Colors.white)
              .withValues(alpha: bright ? .32 : .15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarCardBackdropPainter oldDelegate) => false;
}

class _ChartFacts extends StatelessWidget {
  const _ChartFacts({required this.chart});

  final QizhengChartData chart;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        children: [
          _fact(
            '命度',
            '${chart.lifeDegree.mansion} ${_formatDegreeMinute(chart.lifeDegree.mansionDegree)}',
          ),
          _divider(),
          _fact(
            '月躔',
            '${chart.birthMansion.name} ${_formatDegreeMinute(chart.birthMansion.degree)}',
          ),
          _divider(),
          _fact('阴阳', chart.dayNight),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFA9B7D4), fontSize: 10.5),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFF3F6FF),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _divider() => Container(
    width: 1,
    height: 28,
    color: Colors.white.withValues(alpha: .1),
  );
}

class _TimelineBar extends StatelessWidget {
  const _TimelineBar({
    required this.target,
    required this.step,
    required this.onPickDate,
    required this.onStepChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime target;
  final QizhengTimeStep step;
  final VoidCallback onPickDate;
  final ValueChanged<QizhengTimeStep> onStepChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              flex: 3,
              child: InkWell(
                onTap: onPickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Text(
                    _formatDateTime(target),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            PopupMenuButton<QizhengTimeStep>(
              initialValue: step,
              onSelected: onStepChanged,
              itemBuilder: (_) => [
                for (final item in QizhengTimeStep.values)
                  PopupMenuItem(value: item, child: Text('间隔${item.label}')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 13,
                ),
                child: Text('间隔${step.label} ▾'),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showParameters(
  BuildContext context,
  QizhengChartData chart,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (context) => DefaultTabController(
      length: 5,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .76,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Row(
                  children: [
                    Text(
                      '盘面参数',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.table_chart_outlined, color: _jade),
                  ],
                ),
              ),
              const TabBar(
                isScrollable: true,
                labelColor: _ink,
                indicatorColor: _jade,
                tabs: [
                  Tab(text: '曜度落宫'),
                  Tab(text: '十二宫'),
                  Tab(text: '二十八宿'),
                  Tab(text: '会照关系'),
                  Tab(text: '算法'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: chart.bodies.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final body = chart.bodies[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: _parseColor(body.colorHex)
                                .withValues(alpha: .12),
                            child: Text(
                              body.shortName,
                              style: TextStyle(
                                color: _parseColor(body.colorHex),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            '${body.name}  ${body.palace} ${body.degreeText}',
                          ),
                          subtitle: Text(
                            '${body.mansion}宿 ${_formatDegree(body.mansionDegree)} · ${body.palaceRole}'
                            '${body.dignities.isEmpty ? '' : ' · ${body.dignities.join('、')}'}',
                          ),
                          trailing: body.retrograde ? const Text('逆') : null,
                        );
                      },
                    ),
                    ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: chart.palaces.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final palace = chart.palaces[index];
                        final names = palace.occupants
                            .map((key) {
                              return chart.bodies
                                  .firstWhere((item) => item.key == key)
                                  .shortName;
                            })
                            .join('、');
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(child: Text(palace.branch)),
                          title: Text('${palace.role} · ${palace.name}'),
                          subtitle: Text(
                            '${palace.element}宫 · ${palace.startLongitude.toInt()}°',
                          ),
                          trailing: SizedBox(
                            width: 76,
                            child: Text(
                              names.isEmpty ? '—' : names,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        );
                      },
                    ),
                    ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: chart.mansions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final mansion = chart.mansions[index];
                        final identity = mansion.determinativeStarId.isEmpty
                            ? mansion.determinativeStar
                            : '${mansion.determinativeStar} · ${mansion.determinativeStarId}';
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFF4EBD2),
                            foregroundColor: _ink,
                            child: Text(mansion.name),
                          ),
                          title: Text('${mansion.name}宿 · ${mansion.ruler}曜'),
                          subtitle: Text('距星 $identity\n${mansion.quadrant}'),
                          isThreeLine: true,
                          trailing: Text(
                            '起 ${_formatDegree(mansion.longitude)}\n宽 ${_formatDegree(mansion.width)}',
                            textAlign: TextAlign.end,
                          ),
                        );
                      },
                    ),
                    ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: chart.relationships.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = chart.relationships[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.hub_outlined, color: _gold),
                          title: Text('${item.body1Name} · ${item.body2Name}'),
                          subtitle: Text(
                            '宫位${item.type} · 夹角 ${_formatDegree(item.separation)}',
                          ),
                        );
                      },
                    ),
                    ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        for (final entry in chart.calculation.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 13),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 112,
                                  child: Text(
                                    _calculationLabel(entry.key),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                Expanded(child: Text(entry.value.toString())),
                              ],
                            ),
                          ),
                        const Divider(height: 28),
                        Text(
                          chart.disclaimer,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.6,
                          ),
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

class QizhengArchivePage extends StatelessWidget {
  const QizhengArchivePage({super.key});
  @override
  Widget build(BuildContext context) => ChartArchivePage(
        kind: RoomChartKind.qizheng,
        createPage: (_) => const QizhengInputPage(),
        openPage: (archive) => QizhengChartLauncherPage(
          profile: QizhengProfile.fromJson(
              Map<String, dynamic>.from(archive.snapshot['profile'] as Map)),
          isSelf: archive.snapshot['isSelf'] == true,
        ),
      );
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
      leading: Icon(icon, color: _jade),
      title: Text(title),
      subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _jade),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('重新排盘')),
          ],
        ),
      ),
    );
  }
}


String _profileCaption(QizhengProfile profile) =>
    '${_formatDateTime(profile.birthDateTime)}  ${profile.birthPlace}';

String _formatDateTime(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _formatDegree(double value) => '${value.toStringAsFixed(2)}°';

String _formatDegreeMinute(double value) {
  final totalMinutes = (value * 60).round();
  return '${totalMinutes ~/ 60}°${(totalMinutes % 60).toString().padLeft(2, '0')}′';
}

Color _parseColor(String hex) {
  final clean = hex.replaceAll('#', '');
  return Color(int.tryParse('FF$clean', radix: 16) ?? 0xFF278F87);
}

String _calculationLabel(String key) =>
    const <String, String>{
      'engine': '计算引擎',
      'engineVersion': '引擎版本',
      'doctrine': '法度版本',
      'ephemeris': '星历',
      'ephemerisSha256': '星历校验',
      'coordinate': '坐标口径',
      'mansionSystem': '宿度制',
      'mansionReference': '距星目录',
      'palaceSystem': '十二宫制',
      'nodeMode': '罗计取法',
      'lifeMode': '立命模式',
      'lifeMethod': '立命法',
      'astronomicalAscendant': '天文上升点',
      'purpleQiPeriodDays': '紫炁周期',
      'effectiveUtcTime': '计算时刻',
      'outputResolution': '输出分辨率',
      'validationReference': '对盘基准',
    }[key] ??
    key;
