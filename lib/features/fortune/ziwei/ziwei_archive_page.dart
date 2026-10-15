import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/local/archive_account_scope.dart';
import '../../../core/local/archive_cloud_sync.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_toast.dart';
import '../archive_relationship.dart';
import '../../consultation/room_chart_case_details.dart';
import '../paipan/models/region.dart';
import '../shared_chart_archive.dart';
import 'ziwei_archive_store.dart';
import 'ziwei_chart_page.dart';
import 'ziwei_input_page.dart';
import 'ziwei_models.dart';
import 'ziwei_service.dart';

class ZiweiArchivePage extends StatefulWidget {
  const ZiweiArchivePage({super.key});

  @override
  State<ZiweiArchivePage> createState() => _ZiweiArchivePageState();
}

class _ZiweiArchivePageState extends State<ZiweiArchivePage> {
  final _searchController = TextEditingController();
  List<ZiweiArchiveRecord> _records = const [];
  List<RoomChartCase> _incompleteCases = const [];
  Map<String, RoomChartCase> _caseByRecordId = const {};
  bool _loading = true;
  String? _openingId;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await apiClient.get('/api/auth/me');
      final data = (response.data as Map?)?['data'] as Map?;
      final date = data?['birthDate']?.toString().trim() ?? '';
      final time = data?['birthTime']?.toString().trim() ?? '';
      final genderValue = (data?['gender'] as num?)?.toInt();
      final nickname = data?['nickname']?.toString().trim() ?? '';
      final parsed = DateTime.tryParse(
        time.isEmpty ? date : '${date}T${time.length == 5 ? '$time:00' : time}',
      );
      if (parsed != null && const [1, 2].contains(genderValue)) {
        await ZiweiArchiveStore.claimSelfProfile(
          birthDateTime: parsed,
          gender: genderValue == 2 ? '女' : '男',
          nickname: nickname,
        );
      }
    } on DioException catch (_) {}
    final cases = await loadRoomChartCases();
    final records = <ZiweiArchiveRecord>[];
    final incomplete = <RoomChartCase>[];
    final caseByRecordId = <String, RoomChartCase>{};
    for (final item in cases) {
      final archive = item.archiveFor(RoomChartKind.ziwei);
      if (archive.unavailableReason != null) {
        incomplete.add(item);
        continue;
      }
      try {
        final record = ZiweiArchiveRecord.fromJson(archive.snapshot);
        records.add(record);
        caseByRecordId[record.id] = item;
      } catch (_) {
        incomplete.add(item);
      }
    }
    records.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    if (!mounted) return;
    setState(() {
      _records = records;
      _incompleteCases = incomplete;
      _caseByRecordId = caseByRecordId;
      _loading = false;
    });
  }

  List<ZiweiArchiveRecord> get _visibleRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _records.where((record) {
      final filterMatched = switch (_filter) {
        'self' => record.isSelf,
        'relations' => !record.isSelf &&
            record.relationship != ArchiveRelationship.caseRecord &&
            !record.isLegacySelf,
        'case' => record.isCase ||
            record.relationship == ArchiveRelationship.caseRecord,
        'legacy' => record.isLegacySelf,
        _ => true,
      };
      if (!filterMatched) return false;
      if (query.isEmpty) return true;
      return record.profile.name.toLowerCase().contains(query) ||
          record.relationshipLabel.contains(query) ||
          record.profile.settings.presetName.toLowerCase().contains(query) ||
          record.caseTitle.toLowerCase().contains(query);
    }).toList();
  }

  List<RoomChartCase> get _visibleIncompleteCases {
    final query = _searchController.text.trim().toLowerCase();
    return _incompleteCases.where((record) {
      final matchesFilter = switch (_filter) {
        'self' => record.isSelf,
        'relations' => !record.isSelf,
        'case' => false,
        'legacy' => record.relationship == ArchiveRelationship.legacy,
        _ => true,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return record.name.toLowerCase().contains(query) ||
          record.subtitle.toLowerCase().contains(query) ||
          ArchiveRelationship.label(record.relationship).contains(query);
    }).toList();
  }

  Future<void> _create() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ZiweiInputPage(forOther: true),
      ),
    );
    await _reload();
  }

  Future<void> _open(ZiweiArchiveRecord record) async {
    if (_openingId != null) return;
    setState(() => _openingId = record.id);
    final now = DateTime.now();
    try {
      final data = await ZiweiService.calculate(
        profile: record.profile,
        targetDate: now,
        targetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ZiweiChartPage(
            profile: record.profile,
            initialData: data,
            initialTargetDate: now,
            initialTargetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
            archiveRecord: record,
          ),
        ),
      );
    } on ZiweiServiceException catch (error) {
      if (mounted) showAppToast(context, error.message);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _editIdentity(ZiweiArchiveRecord record) async {
    if (record.isSelf) {
      showAppToast(context, '本人档案名跟随账号昵称');
      return;
    }
    final controller = TextEditingController(text: record.profile.name);
    var relationship =
        record.isLegacySelf ? ArchiveRelationship.other : record.relationship;
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑档案身份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 20,
                decoration: const InputDecoration(labelText: '姓名或称呼'),
              ),
              DropdownButtonFormField<String>(
                initialValue: relationship,
                decoration: const InputDecoration(labelText: '与我关系'),
                items: ArchiveRelationship.selectableForOthers
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(ArchiveRelationship.label(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => relationship = value ?? relationship),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty ||
                    ArchiveRelationship.isReservedSelfName(name)) {
                  showAppToast(context, '请填写真实可区分的姓名或称呼');
                  return;
                }
                Navigator.pop(dialogContext, (name, relationship));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    final sharedCase = _caseByRecordId[record.id];
    if (sharedCase == null) {
      await ZiweiArchiveStore.updateIdentity(
        record.id,
        displayName: result.$1,
        relationship: result.$2,
      );
    } else {
      await updateRoomChartCaseIdentity(
        sharedCase,
        displayName: result.$1,
        relationship: result.$2,
      );
    }
    await _reload();
  }

  Future<void> _delete(ZiweiArchiveRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除紫微档案'),
        content: Text('确定删除「${record.profile.name}」？相关的八字、斗数、星盘和七政档案会一并删除。账号出生资料保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final sharedCase = _caseByRecordId[record.id];
      if (sharedCase == null) {
        await ZiweiArchiveStore.delete(record.id);
      } else {
        await deleteRoomChartCase(sharedCase);
      }
      await _reload();
    }
  }

  Future<void> _completeCase(RoomChartCase record) async {
    final place = record.birthPlace.isEmpty
        ? null
        : Region.placeholder(
            name: record.birthPlace,
            extPath: record.birthPlace,
            lng: record.longitude,
            lat: record.latitude,
          );
    final details = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          RoomChartCaseDetailsDialog(isFemale: record.isFemale, place: place),
    );
    if (details == null) return;
    final userId = await ArchiveAccountScope.currentUserId();
    if (userId == null) {
      if (mounted) showAppToast(context, '登录状态已失效，请重新登录');
      return;
    }
    await RoomChartCaseDetailsStore.save(
      record.sourceKeys,
      details,
      expectedUserId: userId,
    );
    final refreshed = (await loadRoomChartCases()).where(
      (item) => item.id == record.id,
    );
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    if (refreshed.isNotEmpty) {
      final archive = refreshed.first.archiveFor(RoomChartKind.ziwei);
      if (archive.unavailableReason == null) {
        await _open(ZiweiArchiveRecord.fromJson(archive.snapshot));
      }
    }
  }

  Future<void> _deleteIncomplete(RoomChartCase record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除档案'),
        content: Text('确定删除「${record.name}」？相关的四种命盘档案会一并删除。账号出生资料保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteRoomChartCase(record);
    await _reload();
  }

  Future<void> _editCase(ZiweiArchiveRecord record) async {
    final title = TextEditingController(text: record.caseTitle);
    final reasoning = TextEditingController(text: record.reasoningNotes);
    final commentary = TextEditingController(text: record.commentary);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('档案笔记'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '笔记标题'),
                ),
                TextField(
                  controller: reasoning,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '看盘判断',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commentary,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '现实反馈',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ZiweiArchiveStore.saveCase(
        fallback: record,
        caseTitle: title.text,
        reasoningNotes: reasoning.text,
        commentary: commentary.text,
      );
      await _reload();
    }
    title.dispose();
    reasoning.dispose();
    commentary.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRecords;
    final incomplete = _visibleIncompleteCases;
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('斗数命理档案'),
        actions: [
          TextButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('新建'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9F8FA), Color(0xFFF8F9FD), Color(0xFFF4F7FA)],
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : RefreshIndicator(
                onRefresh: _reload,
                color: AppColors.primary,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: ArchiveSyncNotice(onChanged: _reload)),
                    if (visible.isEmpty && incomplete.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmpty(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 36),
                        sliver: SliverList.separated(
                          itemCount: visible.length + incomplete.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) => index < visible.length
                              ? _buildCard(visible[index])
                              : _buildIncompleteCard(
                                  incomplete[index - visible.length],
                                ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建命盘'),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索姓名或关系',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', '全部'),
                _filterChip('self', '本人'),
                _filterChip('relations', '亲友'),
                _filterChip('case', '有笔记'),
                if (_records.any((r) => r.isLegacySelf))
                  _filterChip('legacy', '待整理'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        label: Text(label),
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: Colors.white.withValues(alpha: .78),
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary : const Color(0xFFDCE9E9),
        ),
      ),
    );
  }

  Widget _buildCard(ZiweiArchiveRecord record) {
    final profile = record.profile;
    final opening = _openingId == record.id;
    return Material(
      color: record.isSelf ? const Color(0xFFFCFFFF) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: opening ? null : () => _open(record),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: record.isSelf
                  ? const Color(0xFF85D6D2)
                  : const Color(0xFFE0E9EC),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF174A4A).withValues(alpha: .05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: record.isSelf
                            ? const [Color(0xFF2DB7B4), Color(0xFF8EDDD8)]
                            : const [Color(0xFFDCECF6), Color(0xFFEAE5FA)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      profile.gender == '女' ? '坤' : '乾',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: record.isSelf
                            ? Colors.white
                            : AppColors.primaryDark,
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
                            Flexible(
                              child: Text(
                                profile.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            _tag(
                              record.relationshipLabel,
                              strong: record.isSelf,
                            ),
                            if (record.isCase) ...[
                              const SizedBox(width: 5),
                              _tag('有笔记'),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('yyyy年MM月dd日 HH:mm')
                              .format(profile.clockBirthDate),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (opening)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                    ),
                ],
              ),
              const SizedBox(height: 13),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FA),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Expanded(child: _info('排盘流派', profile.settings.presetName)),
                    Container(
                      width: 1,
                      height: 30,
                      color: const Color(0xFFDCE7E9),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: _info(
                        '出生时间',
                        profile.calendarTypeIndex == 1
                            ? '农历输入'
                            : profile.calendarTypeIndex == 2
                                ? '四柱反推'
                                : '公历输入',
                      ),
                    ),
                  ],
                ),
              ),
              if (record.isCase &&
                  (record.caseTitle.isNotEmpty ||
                      record.commentary.isNotEmpty)) ...[
                const SizedBox(height: 10),
                Text(
                  record.caseTitle.isEmpty ? '档案笔记' : record.caseTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                if (record.commentary.isNotEmpty)
                  Text(
                    record.commentary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.birthPlace ?? '未填写出生地',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _editIdentity(record),
                    child: Text(record.isSelf ? '账号资料' : '编辑'),
                  ),
                  TextButton(
                    onPressed: () => _editCase(record),
                    child: Text(record.isCase ? '编辑笔记' : '写笔记'),
                  ),
                  IconButton(
                    onPressed: () => _delete(record),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncompleteCard(RoomChartCase record) {
    final reason =
        record.archiveFor(RoomChartKind.ziwei).unavailableReason ?? '案例资料需要补全';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _completeCase(record),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5DC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_search_rounded,
                  color: Color(0xFFB17A17),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '点击补全后直接查看斗数专业盘',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除档案',
                onPressed: () => _deleteIncomplete(record),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textHint),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF315456),
            ),
          ),
        ],
      );

  Widget _tag(String label, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: strong
              ? AppColors.primary.withValues(alpha: .13)
              : const Color(0xFFF0F3F4),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: strong ? AppColors.primaryDark : AppColors.textSecondary,
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.blur_circular_rounded,
                size: 52,
                color: Color(0xFF91C9C7),
              ),
              const SizedBox(height: 12),
              Text(
                _records.isEmpty && _incompleteCases.isEmpty
                    ? '还没有紫微档案'
                    : '没有匹配的档案',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _records.isEmpty && _incompleteCases.isEmpty
                    ? '为他人新建命盘，运限与档案笔记都会归入对应档案'
                    : '试试更换筛选或搜索词',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              if (_records.isEmpty && _incompleteCases.isEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建命盘'),
                ),
              ],
            ],
          ),
        ),
      );
}
