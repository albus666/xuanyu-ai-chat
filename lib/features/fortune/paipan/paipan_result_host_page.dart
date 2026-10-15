/// 排盘结果父页面：AppBar + 农历/公历头部 + 个人信息/专业细盘（统一 App 主题）
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_share_more_button.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_session_scope.dart';
import '../../../../core/local/paipan_record_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'models/paipan_record.dart';
import '../archive_relationship.dart';
import '../bazi_input_page.dart';
import '../paipan_record_archive_page.dart';
import '../shared_chart_archive.dart';
import 'bazi_calculation_cache.dart';
import 'models/region.dart';
import 'utils/bazi_result.dart';
import 'share/paipan_extra_content_service.dart';
import 'share/paipan_shared.dart';
import 'paipan_personal_info_tab.dart';
import 'paipan_detail_chart_tab.dart';

/// 排盘结果详情页：个人信息与专业细盘。
///
/// 专业细盘组件保持独立，不参与个人信息与档案笔记的计算和存储。
class PaipanResultPage extends StatefulWidget {
  final DateTime birthDateTime;
  final bool isFemale;
  final Region? birthPlace;
  final int calendarTypeIndex;
  final String displayName;
  final bool isSelf;
  final String relationship;

  /// 从命理档案打开时设为 true，不再保存到本地
  final bool skipSaveToArchive;
  final String? recordId;

  const PaipanResultPage({
    super.key,
    required this.birthDateTime,
    required this.isFemale,
    this.birthPlace,
    this.calendarTypeIndex = 0,
    this.displayName = '',
    this.isSelf = false,
    this.relationship = ArchiveRelationship.other,
    this.skipSaveToArchive = false,
    this.recordId,
  });

  @override
  State<PaipanResultPage> createState() => _PaipanResultPageState();
}

class _PaipanResultPageState extends State<PaipanResultPage>
    with SingleTickerProviderStateMixin {
  bool _archiveSaved = false;
  final _accountScope = ApiSessionScope();
  bool _caseSaving = false;
  String? _currentRecordId;
  Future<void>? _archiveSaveFuture;
  late final TabController _tabController;
  late final Future<BaziResult> _resultFuture;
  bool _caseNotebookVisible = false;
  bool _caseNotebookLoading = false;
  PaipanRecord? _caseNotebookRecord;
  BaziResult? _caseNotebookResult;
  TextEditingController? _caseTitleController;
  TextEditingController? _caseReasoningController;
  TextEditingController? _caseCommentaryController;
  final ScrollController _caseScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _currentRecordId = widget.recordId;
    _tabController = TabController(length: 2, initialIndex: 1, vsync: this);
    _resultFuture = BaziCalculationCache.calculate(
      widget.birthDateTime,
      isFemale: widget.isFemale,
    );
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _tabController.dispose();
    _caseTitleController?.dispose();
    _caseReasoningController?.dispose();
    _caseCommentaryController?.dispose();
    _caseScrollController.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (mounted) setState(() {});
  }

  void _saveToArchiveOnce(BaziResult result) {
    if (!_accountScope.current || _archiveSaved || widget.skipSaveToArchive) {
      return;
    }
    _archiveSaved = true;
    _currentRecordId ??= '${DateTime.now().millisecondsSinceEpoch}';
    final record = PaipanRecord(
      id: _currentRecordId!,
      createdAt: DateTime.now(),
      displayName: widget.displayName.trim(),
      isSelf: widget.isSelf,
      relationship: widget.relationship,
      birthDateTime: widget.birthDateTime,
      isFemale: widget.isFemale,
      calendarTypeIndex: widget.calendarTypeIndex,
      birthPlace: widget.birthPlace,
      summary: result.fourPillarsStr,
    );
    _archiveSaveFuture = PaipanRecordStore.save(record).catchError((Object _) {
      if (!mounted || !_accountScope.current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('档案保存失败，原有资料未覆盖，请稍后重试')),
      );
    });
  }

  PaipanRecord _fallbackRecord(BaziResult result) => PaipanRecord(
        id: _currentRecordId ??
            widget.recordId ??
            'case-${DateTime.now().millisecondsSinceEpoch}',
        createdAt: DateTime.now(),
        displayName: widget.displayName.trim(),
        isSelf: widget.isSelf,
        relationship: widget.relationship,
        birthDateTime: widget.birthDateTime,
        isFemale: widget.isFemale,
        calendarTypeIndex: widget.calendarTypeIndex,
        birthPlace: widget.birthPlace,
        summary: result.fourPillarsStr,
      );

  Future<void> _openCaseNotebook(BaziResult result) async {
    if (!_accountScope.current) return;
    _tabController.animateTo(1);
    if (_caseNotebookVisible || _caseNotebookLoading) return;
    final name =
        widget.displayName.trim().isEmpty ? '未命名' : widget.displayName.trim();
    _caseTitleController?.dispose();
    _caseReasoningController?.dispose();
    _caseCommentaryController?.dispose();
    _caseTitleController = TextEditingController(
      text: '$name · 档案笔记',
    );
    _caseReasoningController = TextEditingController();
    _caseCommentaryController = TextEditingController();
    setState(() {
      _caseNotebookLoading = false;
      _caseNotebookRecord = null;
      _caseNotebookResult = result;
      _caseNotebookVisible = true;
    });

    await _archiveSaveFuture;
    if (!_accountScope.current) return;
    final record = await PaipanRecordStore.findForChart(
      recordId: _currentRecordId ?? widget.recordId,
      birthDateTime: widget.birthDateTime,
      isFemale: widget.isFemale,
      summary: result.fourPillarsStr,
    );
    if (!mounted || !_accountScope.current || record == null) return;
    _caseNotebookRecord = record;
    if (_caseTitleController?.text == '$name · 档案笔记' &&
        record.caseTitle.trim().isNotEmpty) {
      _caseTitleController?.text = record.caseTitle;
    }
    if (_caseReasoningController?.text.isEmpty == true) {
      _caseReasoningController?.text = record.reasoningNotes;
    }
    if (_caseCommentaryController?.text.isEmpty == true) {
      _caseCommentaryController?.text = record.commentary;
    }
  }

  Future<void> _saveCaseNotebook() async {
    if (_caseSaving || !_accountScope.current) return;
    final result = _caseNotebookResult;
    final title = _caseTitleController;
    final reasoning = _caseReasoningController;
    final commentary = _caseCommentaryController;
    if (result == null ||
        title == null ||
        reasoning == null ||
        commentary == null) {
      return;
    }
    if (reasoning.text.trim().isEmpty && commentary.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写看盘判断或现实反馈')),
      );
      return;
    }
    _caseSaving = true;
    try {
      final stored = await PaipanRecordStore.saveCase(
        recordId: _currentRecordId ?? widget.recordId,
        fallback: _caseNotebookRecord ?? _fallbackRecord(result),
        caseTitle: title.text,
        reasoningNotes: reasoning.text,
        commentary: commentary.text,
      );
      _currentRecordId = stored.id;
      _caseNotebookRecord = stored;
      if (!mounted || !_accountScope.current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('档案笔记已保存，可继续对照命盘修改')),
      );
    } catch (_) {
      if (mounted && _accountScope.current) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记保存失败，输入已保留，原有档案未覆盖')),
        );
      }
    } finally {
      _caseSaving = false;
    }
  }

  String get _subjectLabel {
    if (widget.isSelf) return '本人';
    final name = widget.displayName.trim();
    return name.isEmpty ? '他人' : name;
  }

  Future<void> _showArchivePicker() async {
    await _archiveSaveFuture;
    final cases = await loadRoomChartCases();
    final records = <PaipanRecord>[
      for (final item in cases)
        if (item.archiveFor(RoomChartKind.bazi).unavailableReason == null)
          PaipanRecord.fromJson(
            item.archiveFor(RoomChartKind.bazi).snapshot,
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
                    final selected = record.id == _currentRecordId ||
                        (widget.isSelf && record.isSelf);
                    final name = record.isSelf
                        ? '我的命盘'
                        : record.displayName.trim().isEmpty
                            ? '未命名档案'
                            : record.displayName.trim();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: .1),
                        foregroundColor: AppColors.primaryDark,
                        child: Text(record.isFemale ? '坤' : '乾'),
                      ),
                      title: Text(name),
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
                        if (selected) return;
                        Navigator.of(context).pushReplacement(
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
                          builder: (_) => const BaziInputPage(forOther: true),
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
                      builder: (_) => const PaipanRecordArchivePage(),
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

  @override
  Widget build(BuildContext context) {
    if (!_accountScope.current) {
      return Scaffold(
          appBar: AppBar(title: const Text('命盘')),
          body: const Center(child: Text(apiSessionChangedMessage)));
    }
    return FutureBuilder<BaziResult>(
      future: _resultFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: paipanLightBg,
            appBar: AppBar(
              title: Text('八字排盘结果', style: AppTextStyles.titleSmall),
              centerTitle: true,
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text('排盘计算异常', style: AppTextStyles.titleSmall),
                    const SizedBox(height: 8),
                    Text(snapshot.error.toString(),
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: paipanLightBg,
            appBar: AppBar(
              title: Text('八字排盘结果', style: AppTextStyles.titleSmall),
              centerTitle: true,
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
            ),
            body: const Center(
              child: CircularProgressIndicator(color: paipanPurple),
            ),
          );
        }
        final result = snapshot.data!;
        // 保存到命理档案（仅首次）
        _saveToArchiveOnce(result);
        // 提前加载「个人信息」Tab 的旺衰/用神规则，切到该 Tab 时多数已就绪。
        final extraFuture = loadPaipanExtraContent(result, widget.isFemale);
        return Scaffold(
          backgroundColor: paipanLightBg,
          appBar: AppBar(
            title: Text('八字排盘结果', style: AppTextStyles.titleSmall),
            centerTitle: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            actions: [
              const AppShareMoreButton(
                toolRoute: '/home_bazi',
                title: '八字专业排盘',
                shareText: '玄遇提供八字专业排盘工具，可创建案例并查看专业盘面。',
              ),
              IconButton(
                key: const ValueKey('paipan-case-notebook-action'),
                tooltip: '档案笔记',
                onPressed: _caseNotebookLoading
                    ? null
                    : () => _caseNotebookVisible
                        ? setState(() => _caseNotebookVisible = false)
                        : _openCaseNotebook(result),
                icon: _caseNotebookLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _caseNotebookVisible
                            ? Icons.note_alt_rounded
                            : Icons.note_alt_outlined,
                      ),
              ),
              TextButton.icon(
                key: const ValueKey('paipan-archive-switch-action'),
                onPressed: _showArchivePicker,
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 54),
                  child: Text(
                    _subjectLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: Container(
                          color: AppColors.surface,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text:
                                          '农历：${result.lunarYearMonthDay} ${result.timeZhi}时 ',
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                    TextSpan(
                                      text: widget.isFemale ? '（坤造）' : '（乾造）',
                                      style: AppTextStyles.bodyMedium
                                          .copyWith(color: paipanPurple),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '公历 ${DateFormat('yyyy-MM-dd HH:mm:ss').format(result.solarDate)}',
                                style: AppTextStyles.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: PaipanSliverTabBarDelegate(
                          TabBar(
                            controller: _tabController,
                            labelColor: paipanPurple,
                            unselectedLabelColor: paipanGrey,
                            indicatorColor: paipanPurple,
                            indicatorWeight: 3,
                            dividerHeight: 0,
                            indicator:
                                const PaipanCenterWidthUnderlineIndicator(
                              borderSide:
                                  BorderSide(color: paipanPurple, width: 3),
                              width: 48,
                            ),
                            labelStyle: AppTextStyles.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600),
                            unselectedLabelStyle: AppTextStyles.bodyMedium,
                            tabs: const [
                              Tab(text: '个人信息'),
                              Tab(text: '专业细盘'),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      PaipanPersonalInfoTab(
                        result: result,
                        extraFuture: extraFuture,
                      ),
                      PaipanDetailChartTab(
                        result: result,
                        isFemale: widget.isFemale,
                      ),
                    ],
                  ),
                ),
              ),
              if (_caseNotebookVisible &&
                  _caseTitleController != null &&
                  _caseReasoningController != null &&
                  _caseCommentaryController != null)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  height: (MediaQuery.sizeOf(context).height * .38)
                      .clamp(250.0, 340.0),
                  child: Material(
                    key: const ValueKey('paipan-case-notebook-overlay'),
                    elevation: 12,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: _CaseNotebookSheet(
                      scrollController: _caseScrollController,
                      titleController: _caseTitleController!,
                      reasoningController: _caseReasoningController!,
                      commentaryController: _caseCommentaryController!,
                      onSave: _saveCaseNotebook,
                      onClose: () =>
                          setState(() => _caseNotebookVisible = false),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CaseNotebookSheet extends StatelessWidget {
  const _CaseNotebookSheet({
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
  Widget build(BuildContext context) {
    return DecoratedBox(
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
                const Icon(
                  Icons.note_alt_outlined,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '档案笔记',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '边看命盘边写，自动归入当前档案',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                TextField(
                  key: const ValueKey('paipan-case-title'),
                  controller: titleController,
                  maxLength: 80,
                  decoration: _decoration('笔记标题', '例如：事业方向验证'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('paipan-case-reasoning'),
                  controller: reasoningController,
                  minLines: 7,
                  maxLines: 18,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: _decoration(
                    '看盘判断',
                    '记录从命盘得出的判断、思路与结论…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('paipan-case-commentary'),
                  controller: commentaryController,
                  minLines: 7,
                  maxLines: 18,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: _decoration(
                    '现实反馈',
                    '记录真实经历、后续变化与验证情况…',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.white,
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCDEDEA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCDEDEA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
      ),
    );
  }
}
