import 'package:flutter/material.dart';

import '../../core/local/archive_account_scope.dart';
import '../../core/local/archive_cloud_sync.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/chart_case_notebook.dart';
import '../consultation/room_chart_case_details.dart';
import 'archive_relationship.dart';
import 'paipan/models/region.dart';
import 'shared_chart_archive.dart';

/// Shared management surface for chart archives, including incomplete cases.
class ChartArchivePage extends StatefulWidget {
  const ChartArchivePage(
      {super.key,
      required this.kind,
      required this.openPage,
      required this.createPage});
  final RoomChartKind kind;
  final Widget Function(RoomChartArchive) openPage;
  final WidgetBuilder createPage;
  @override
  State<ChartArchivePage> createState() => _ChartArchivePageState();
}

class _ChartArchivePageState extends State<ChartArchivePage> {
  final _scope = ApiSessionScope();
  final _search = TextEditingController();
  List<RoomChartCase>? _cases;
  String _filter = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final records = await loadRoomChartCases();
      if (!mounted || !_scope.current) return;
      setState(() {
        _cases = records;
        _error = null;
      });
    } catch (_) {
      if (mounted && _scope.current) setState(() => _error = '档案加载失败，请重试');
    }
  }

  bool _hasNotes(RoomChartCase record) =>
      record.snapshots.values.any((snapshot) => [
            'caseTitle',
            'reasoningNotes',
            'commentary',
            'note'
          ].any((key) => snapshot[key]?.toString().trim().isNotEmpty == true));

  Future<void> _open(RoomChartCase record) async {
    if (!_scope.current) return;
    var archive = record.archiveFor(widget.kind);
    if (archive.unavailableReason != null) {
      final details = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => RoomChartCaseDetailsDialog(
              isFemale: record.isFemale,
              place: record.birthPlace.isEmpty
                  ? null
                  : Region.placeholder(
                      name: record.birthPlace,
                      extPath: record.birthPlace,
                      lng: record.longitude,
                      lat: record.latitude)));
      if (details == null || !mounted || !_scope.current) return;
      final userId = await ArchiveAccountScope.currentUserId();
      if (userId == null || !_scope.current) return;
      await RoomChartCaseDetailsStore.save(record.sourceKeys, details,
          expectedUserId: userId);
      final refreshed = await loadRoomChartCases();
      if (!mounted || !_scope.current) return;
      final matches = refreshed.where((item) => item.id == record.id);
      if (matches.isEmpty) return;
      archive = matches.first.archiveFor(widget.kind);
      if (archive.unavailableReason != null) {
        showAppToast(context, archive.unavailableReason!);
        return;
      }
    }
    if (!mounted || !_scope.current) return;
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => widget.openPage(archive)));
    await _load();
  }

  Future<void> _delete(RoomChartCase record) async {
    if (!_scope.current) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('删除档案'),
              content: Text('确定删除「${record.name}」？关联的四种命盘和案例笔记会一并删除。账号出生资料保留。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('删除',
                        style: TextStyle(color: AppColors.error)))
              ],
            ));
    if (confirmed != true || !mounted || !_scope.current) return;
    try {
      await deleteRoomChartCase(record);
      await _load();
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '删除失败，请重试');
    }
  }

  Future<void> _edit(RoomChartCase record) async {
    if (!_scope.current) return;
    final name = TextEditingController(text: record.name);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('编辑档案名称'),
              content: TextField(
                  controller: name,
                  maxLength: 30,
                  decoration: const InputDecoration(labelText: '姓名或称呼')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () {
                      if (name.text.trim().isNotEmpty) Navigator.pop(ctx, true);
                    },
                    child: const Text('保存'))
              ],
            ));
    final value = name.text.trim();
    // The dialog's exit animation may still use its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    if (confirmed != true || !mounted || !_scope.current) return;
    try {
      await updateRoomChartCaseIdentity(record,
          displayName: value, relationship: record.relationship);
      await _load();
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '保存失败，请重试');
    }
  }

  Future<void> _notes(RoomChartCase record) async {
    if (!_scope.current) return;
    final userId = await ArchiveAccountScope.currentUserId();
    if (userId == null || !mounted || !_scope.current) return;
    final data = record.snapshots[widget.kind] ?? record.snapshots.values.first;
    final title =
        TextEditingController(text: data['caseTitle']?.toString() ?? '');
    final reasoning = TextEditingController(
        text: (data['reasoningNotes'] ?? data['note'])?.toString() ?? '');
    final commentary =
        TextEditingController(text: data['commentary']?.toString() ?? '');
    final scroll = ScrollController();
    bool saving = false;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .8,
            child: ChartCaseNotebook(
                scrollController: scroll,
                titleController: title,
                reasoningController: reasoning,
                commentaryController: commentary,
                onClose: () => Navigator.pop(ctx),
                onSave: () async {
                  if (saving || !_scope.current) return;
                  saving = true;
                  try {
                    await updateRoomChartCaseNotes(record,
                        caseTitle: title.text,
                        reasoningNotes: reasoning.text,
                        commentary: commentary.text,
                        expectedUserId: userId);
                    if (ctx.mounted && _scope.current) Navigator.pop(ctx);
                    await _load();
                  } catch (_) {
                    if (ctx.mounted) showAppToast(ctx, '保存失败，请重试');
                  } finally {
                    saving = false;
                  }
                })));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    reasoning.dispose();
    commentary.dispose();
    scroll.dispose();
  }

  Future<void> _create() async {
    if (!_scope.current) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: widget.createPage));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final records = (_cases ?? []).where((record) {
      final matches = switch (_filter) {
        'self' => record.isSelf,
        'relations' => !record.isSelf,
        'notes' => _hasNotes(record),
        _ => true,
      };
      return matches &&
          '${record.name} ${ArchiveRelationship.label(record.relationship)} ${record.subtitle} ${record.birthPlace}'
              .toLowerCase()
              .contains(query);
    }).toList();
    return Scaffold(
        backgroundColor: const Color(0xFFF4FAFA),
        appBar: AppBar(title: Text('${widget.kind.label}命理档案'), actions: [
          TextButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建'))
        ]),
        bottomNavigationBar: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ArchiveSyncNotice(onChanged: _load)),
        body: _error != null
            ? Center(child: TextButton(onPressed: _load, child: Text(_error!)))
            : _cases == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(16), children: [
                    TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                            hintText: '搜索姓名、关系或出生资料',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none))),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final item in const {
                        'all': '全部',
                        'self': '本人',
                        'relations': '亲友',
                        'notes': '有笔记'
                      }.entries)
                        ChoiceChip(
                            label: Text(item.value),
                            selected: _filter == item.key,
                            onSelected: (_) =>
                                setState(() => _filter = item.key))
                    ]),
                    const SizedBox(height: 20),
                    if (records.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('没有符合条件的档案'))),
                    for (final record in records)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              child: InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () => _open(record),
                                  child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                              color: const Color(0xFF9CDDD8))),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              CircleAvatar(
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  child: Icon(
                                                      widget.kind ==
                                                              RoomChartKind
                                                                  .astrology
                                                          ? Icons.auto_awesome
                                                          : Icons.public,
                                                      color: Colors.white)),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(record.name,
                                                        style: const TextStyle(
                                                            fontSize: 18,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    const SizedBox(height: 4),
                                                    Text(record.subtitle)
                                                  ])),
                                              const Icon(Icons.chevron_right)
                                            ]),
                                            const SizedBox(height: 12),
                                            Text(
                                                ArchiveRelationship.label(record
                                                        .isSelf
                                                    ? ArchiveRelationship.self
                                                    : record.relationship),
                                                style: const TextStyle(
                                                    color:
                                                        AppColors.primaryDark)),
                                            if (record
                                                    .archiveFor(widget.kind)
                                                    .unavailableReason !=
                                                null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: Text(
                                                      '资料待补全 · ${record.archiveFor(widget.kind).unavailableReason}')),
                                            const SizedBox(height: 8),
                                            Text(
                                                record.birthPlace.isEmpty
                                                    ? '出生地未填写'
                                                    : record.birthPlace,
                                                style: const TextStyle(
                                                    color: AppColors
                                                        .textSecondary)),
                                            Wrap(
                                                alignment: WrapAlignment.end,
                                                spacing: 4,
                                                children: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          _edit(record),
                                                      child: const Text('编辑')),
                                                  TextButton(
                                                      onPressed: () =>
                                                          _notes(record),
                                                      child: Text(
                                                          _hasNotes(record)
                                                              ? '编辑笔记'
                                                              : '写笔记')),
                                                  IconButton(
                                                      tooltip: '删除档案',
                                                      onPressed: () =>
                                                          _delete(record),
                                                      icon: const Icon(
                                                          Icons
                                                              .delete_outline_rounded,
                                                          color:
                                                              AppColors.error)),
                                                ]),
                                          ]))))),
                  ]));
  }
}
