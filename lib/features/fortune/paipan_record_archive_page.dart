import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/local/paipan_record_store.dart';
import '../../core/local/archive_account_scope.dart';
import '../../core/local/archive_cloud_sync.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'archive_relationship.dart';
import '../consultation/room_chart_case_details.dart';
import 'bazi_input_page.dart';
import 'paipan/models/paipan_record.dart';
import 'paipan/models/region.dart';
import 'paipan/paipan_result_host_page.dart';
import 'shared_chart_archive.dart';

class PaipanRecordArchivePage extends StatefulWidget {
  const PaipanRecordArchivePage({super.key});

  @override
  State<PaipanRecordArchivePage> createState() =>
      _PaipanRecordArchivePageState();
}

class _PaipanRecordArchivePageState extends State<PaipanRecordArchivePage> {
  final _searchController = TextEditingController();
  final _accountScope = ApiSessionScope();
  final Set<DialogRoute<dynamic>> _dialogs = {};
  List<PaipanRecord> _records = const [];
  List<RoomChartCase> _incompleteCases = const [];
  Map<String, RoomChartCase> _caseByRecordId = const {};
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (mounted) {
      if (!_accountScope.current) {
        for (final route in _dialogs.toList()) {
          if (route.isActive) route.navigator?.removeRoute(route);
        }
      }
      setState(() {
        _records = [];
        _incompleteCases = [];
        _caseByRecordId = {};
      });
    }
  }

  Future<T?> _showArchiveDialog<T>({required WidgetBuilder builder}) async {
    if (!_accountScope.current || !mounted) return null;
    final route = DialogRoute<T>(context: context, builder: builder);
    _dialogs.add(route);
    try {
      final result = await Navigator.of(context).push(route);
      // Text fields still use their controllers during the closing animation.
      await route.completed;
      return result;
    } finally {
      _dialogs.remove(route);
    }
  }

  Future<void> _load() async {
    if (!_accountScope.current) return;
    if (mounted) setState(() => _loading = true);
    try {
      final response = await _accountScope.get('/api/auth/me');
      final data = (response.data as Map?)?['data'] as Map?;
      final date = data?['birthDate']?.toString().trim() ?? '';
      final time = data?['birthTime']?.toString().trim() ?? '';
      final gender = (data?['gender'] as num?)?.toInt();
      final nickname = data?['nickname']?.toString().trim() ?? '';
      final parsed = DateTime.tryParse(
        time.isEmpty ? date : '${date}T${time.length == 5 ? '$time:00' : time}',
      );
      if (parsed != null && const [1, 2].contains(gender)) {
        await PaipanRecordStore.claimSelfProfile(
          birthDateTime: parsed,
          isFemale: gender == 2,
          nickname: nickname,
        );
      }
    } catch (_) {
      if (!_accountScope.current) return;
    }
    final cases = await loadRoomChartCases();
    final list = <PaipanRecord>[];
    final incomplete = <RoomChartCase>[];
    final caseByRecordId = <String, RoomChartCase>{};
    for (final item in cases) {
      final archive = item.archiveFor(RoomChartKind.bazi);
      if (archive.unavailableReason != null) {
        incomplete.add(item);
        continue;
      }
      try {
        final record = PaipanRecord.fromJson(archive.snapshot);
        list.add(record);
        caseByRecordId[record.id] = item;
      } catch (_) {
        incomplete.add(item);
      }
    }
    list.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    if (!mounted || !_accountScope.current) return;
    setState(() {
      _records = list;
      _incompleteCases = incomplete;
      _caseByRecordId = caseByRecordId;
      _loading = false;
    });
  }

  List<PaipanRecord> get _visibleRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _records.where((record) {
      final matchesFilter = switch (_filter) {
        'self' => record.isSelf,
        'relations' => !record.isSelf &&
            record.relationship != ArchiveRelationship.caseRecord &&
            !record.isLegacySelf,
        'case' => record.isCase ||
            record.relationship == ArchiveRelationship.caseRecord,
        'legacy' => record.isLegacySelf,
        _ => true,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return record.displayName.toLowerCase().contains(query) ||
          record.summary.toLowerCase().contains(query) ||
          record.relationshipLabel.contains(query) ||
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
    if (!_accountScope.current) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BaziInputPage(forOther: true),
      ),
    );
    await _load();
  }

  void _open(PaipanRecord record) {
    if (!mounted || !_accountScope.current) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaipanResultPage(
          birthDateTime: record.birthDateTime,
          isFemale: record.isFemale,
          birthPlace: record.birthPlace,
          calendarTypeIndex: record.calendarTypeIndex,
          displayName: record.displayName,
          isSelf: record.isSelf,
          relationship: record.relationship,
          skipSaveToArchive: true,
          recordId: record.id,
        ),
      ),
    );
  }

  Future<void> _editIdentity(PaipanRecord record) async {
    if (!_accountScope.current) return;
    if (record.isSelf) {
      showAppToast(context, '本人档案名跟随账号昵称');
      return;
    }
    final controller = TextEditingController(text: record.displayName);
    var relationship =
        record.isLegacySelf ? ArchiveRelationship.other : record.relationship;
    final result = await _showArchiveDialog<(String, String)?>(
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
    if (result == null || !mounted || !_accountScope.current) return;
    final sharedCase = _caseByRecordId[record.id];
    if (sharedCase == null) {
      await PaipanRecordStore.updateIdentity(
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
    await _load();
  }

  Future<void> _delete(PaipanRecord record) async {
    if (!_accountScope.current) return;
    final confirmed = await _showArchiveDialog<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('删除档案'),
        content: Text('确定删除「${record.displayName}」？相关的八字、斗数、星盘和七政档案会一并删除。账号出生资料保留。'),
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
    if (confirmed == true && mounted && _accountScope.current) {
      final sharedCase = _caseByRecordId[record.id];
      if (sharedCase == null) {
        await PaipanRecordStore.delete(record.id);
      } else {
        await deleteRoomChartCase(sharedCase);
      }
      await _load();
    }
  }

  Future<void> _completeCase(RoomChartCase record) async {
    if (!_accountScope.current) return;
    final place = record.birthPlace.isEmpty
        ? null
        : Region.placeholder(
            name: record.birthPlace,
            extPath: record.birthPlace,
            lng: record.longitude,
            lat: record.latitude,
          );
    final details = await _showArchiveDialog<Map<String, dynamic>>(
      builder: (_) =>
          RoomChartCaseDetailsDialog(isFemale: record.isFemale, place: place),
    );
    if (details == null || !mounted || !_accountScope.current) return;
    final userId = await ArchiveAccountScope.currentUserId();
    if (!mounted || !_accountScope.current) return;
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
    if (!mounted || !_accountScope.current) return;
    await _load();
    if (!mounted || !_accountScope.current) return;
    if (refreshed.isNotEmpty) {
      final archive = refreshed.first.archiveFor(RoomChartKind.bazi);
      if (archive.unavailableReason == null) {
        _open(PaipanRecord.fromJson(archive.snapshot));
      }
    }
  }

  Future<void> _deleteIncomplete(RoomChartCase record) async {
    if (!_accountScope.current) return;
    final confirmed = await _showArchiveDialog<bool>(
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
    if (confirmed != true || !mounted || !_accountScope.current) return;
    await deleteRoomChartCase(record);
    await _load();
  }

  Future<void> _editCase(PaipanRecord record) async {
    if (!_accountScope.current) return;
    final title = TextEditingController(text: record.caseTitle);
    final reasoning = TextEditingController(text: record.reasoningNotes);
    final commentary = TextEditingController(text: record.commentary);
    var saving = false;
    String? error;
    await _showArchiveDialog<bool>(
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
                title: const Text('档案笔记'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (error != null)
                          Text(error!,
                              style: const TextStyle(color: AppColors.error)),
                        TextField(
                          controller: title,
                          maxLength: 80,
                          decoration: const InputDecoration(labelText: '笔记标题'),
                        ),
                        TextField(
                          controller: reasoning,
                          minLines: 5,
                          maxLines: 14,
                          decoration: const InputDecoration(
                            labelText: '看盘判断',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: commentary,
                          minLines: 5,
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
                    onPressed: saving
                        ? null
                        : () async {
                            if (!_accountScope.current) {
                              Navigator.pop(ctx);
                              return;
                            }
                            update(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              await PaipanRecordStore.saveCase(
                                recordId: record.id,
                                fallback: record,
                                caseTitle: title.text,
                                reasoningNotes: reasoning.text,
                                commentary: commentary.text,
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                              if (mounted && _accountScope.current) {
                                await _load();
                              }
                            } catch (_) {
                              if (ctx.mounted) {
                                update(() {
                                  saving = false;
                                  error = _accountScope.current
                                      ? '保存失败，输入已保留，原有档案未覆盖'
                                      : apiSessionChangedMessage;
                                });
                              }
                            }
                          },
                    child: Text(saving ? '保存中…' : '保存'),
                  ),
                ],
              )),
    );
    title.dispose();
    reasoning.dispose();
    commentary.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_accountScope.current) {
      return Scaffold(
          appBar: AppBar(title: const Text('八字命理档案')),
          body: const Center(child: Text(apiSessionChangedMessage)));
    }
    final visible = _visibleRecords;
    final incomplete = _visibleIncompleteCases;
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      appBar: AppBar(
        title: const Text('八字命理档案'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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
            colors: [Color(0xFFE8FAFA), Color(0xFFF7FBFC), Color(0xFFF4F7FA)],
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ArchiveSyncNotice(onChanged: _load))),
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
        label: const Text('新建档案'),
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
              hintText: '搜索姓名、关系或四柱',
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
              fillColor: Colors.white.withValues(alpha: .88),
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
        backgroundColor: Colors.white.withValues(alpha: .75),
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

  Widget _buildCard(PaipanRecord record) {
    final name =
        record.displayName.trim().isEmpty ? '未命名' : record.displayName.trim();
    return Material(
      color: record.isSelf ? const Color(0xFFFCFFFF) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(record),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: record.isSelf
                  ? const Color(0xFF84D6D2)
                  : const Color(0xFFE1EBEC),
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
                            : const [Color(0xFFEAE7FA), Color(0xFFD8F1F1)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      record.isFemale ? '坤' : '乾',
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
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleSmall.copyWith(
                                  fontWeight: FontWeight.w800,
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
                              .format(record.birthDateTime),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F8F8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  record.summary.isEmpty ? '四柱信息待补全' : record.summary,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF244849),
                  ),
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
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record.birthPlaceDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
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
        record.archiveFor(RoomChartKind.bazi).unavailableReason ?? '案例资料需要补全';
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
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '点击补全后直接查看八字专业盘',
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
                Icons.folder_copy_outlined,
                size: 50,
                color: Color(0xFF91C9C7),
              ),
              const SizedBox(height: 12),
              Text(
                _records.isEmpty && _incompleteCases.isEmpty
                    ? '还没有八字档案'
                    : '没有匹配的档案',
                style: AppTextStyles.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                _records.isEmpty && _incompleteCases.isEmpty
                    ? '打开八字排盘建立本人档案，或在这里为他人新建档案'
                    : '试试更换筛选或搜索词',
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              ),
              if (_records.isEmpty && _incompleteCases.isEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建档案'),
                ),
              ],
            ],
          ),
        ),
      );
}
