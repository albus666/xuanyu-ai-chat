import 'package:xuanyu/shared/widgets/bottom_footer_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'bagua_compass_tab.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'fengshui_environment_corpus.dart';

/// 八宫方位数据：方位名、八卦名、九宫格位置 (row, col)
/// 已按需求调换：西北↔东南、东北↔西南、东↔西、南↔北
const _baguaDirections = [
  {'dir': '东南', 'gua': '巽', 'r': 0, 'c': 0},
  {'dir': '南', 'gua': '离', 'r': 0, 'c': 1},
  {'dir': '西南', 'gua': '坤', 'r': 0, 'c': 2},
  {'dir': '东', 'gua': '震', 'r': 1, 'c': 0},
  {'dir': '西', 'gua': '兑', 'r': 1, 'c': 2},
  {'dir': '东北', 'gua': '艮', 'r': 2, 'c': 0},
  {'dir': '北', 'gua': '坎', 'r': 2, 'c': 1},
  {'dir': '西北', 'gua': '乾', 'r': 2, 'c': 2},
];

class FengshuiPage extends StatefulWidget {
  const FengshuiPage({super.key});

  @override
  State<FengshuiPage> createState() => _FengshuiPageState();
}

class _FengshuiPageState extends State<FengshuiPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color _themeColor = const Color(0xFF059669);

  // 八宫
  final Map<String, _PalaceResult> _palaceResults = {};
  String? _loadingDirection;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _analyzeItem(String direction, String gua) async {
    final itemName = await showDialog<String>(
      context: context,
      builder: (ctx) => _FengshuiItemQueryDialog(
        dir: direction,
        gua: gua,
        themeColor: _themeColor,
      ),
    );
    if (itemName == null || itemName.isEmpty) return;

    setState(() => _loadingDirection = direction);
    try {
      final palace = await FengshuiEnvironmentCorpus.loadPalaceStructured(gua);
      if (palace == null) {
        if (mounted) showAppToast(context, '当前方位内容暂不可用');
        return;
      }

      final hit =
          FengshuiEnvironmentCorpus.lookupPalaceDescriptionWithSimilarity(
              palace, itemName);
      if (hit != null && mounted) {
        setState(() {
          _loadingDirection = null;
          _palaceResults['$direction-$gua'] = _PalaceResult(
            itemName: hit.matchedKey,
            userQuery:
                itemName.trim() == hit.matchedKey ? null : itemName.trim(),
            status: FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
              itemKey: hit.matchedKey,
              sourceText: hit.description,
            ),
          );
        });
        return;
      }

      if (mounted) {
        showAppToast(
          context,
          '暂未找到「$itemName」的相关内容，请从列表点选或更换关键词',
        );
      }
    } catch (_) {
      if (mounted) showAppToast(context, '查询异常');
    } finally {
      if (mounted) setState(() => _loadingDirection = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text('住宅分析', style: AppTextStyles.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _themeColor,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: _themeColor,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: '方位分析'),
            Tab(text: '电子罗盘'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPalaceTab(),
          const BaguaCompassTab(),
        ],
      ),
    );
  }

  Widget _buildPalaceTab() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _palaceResults.clear();
        });
      },
      color: _themeColor,
      child: BottomFooterScrollView(
        footer: const CulturalReferenceNotice(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0)),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBaguaGrid(),
            if (_palaceResults.isNotEmpty) ...[
              const SizedBox(height: 40),
              Row(
                children: [
                  Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                          color: _themeColor,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  Text('空间状态', style: AppTextStyles.titleSmall),
                ],
              ),
              const SizedBox(height: 16),
              ..._palaceResults.entries
                  .map((e) => _buildResultCard(e.key, e.value)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBaguaGrid() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: 9,
            itemBuilder: (ctx, i) {
              final r = i ~/ 3, c = i % 3;
              if (r == 1 && c == 1) {
                return Container(
                  decoration: BoxDecoration(
                    color: _themeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('中宫',
                            style: AppTextStyles.titleSmall
                                .copyWith(fontSize: 13, color: _themeColor)),
                        const Icon(Icons.control_point_rounded,
                            size: 14, color: Color(0xFF059669)),
                      ],
                    ),
                  ),
                );
              }
              Map<String, dynamic>? item;
              for (final e in _baguaDirections) {
                if (e['r'] == r && e['c'] == c) {
                  item = Map<String, dynamic>.from(e);
                  break;
                }
              }
              if (item == null) return const SizedBox.shrink();
              final dir = item['dir'] as String;
              final gua = item['gua'] as String;
              final key = '$dir-$gua';
              final res = _palaceResults[key];
              final loading = _loadingDirection == dir;
              return _buildPalaceCell(dir, gua, res, loading);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPalaceCell(
      String dir, String gua, _PalaceResult? res, bool loading) {
    Color bg = AppColors.cardBackground;
    Color borderColor = AppColors.divider.withValues(alpha: 0.5);
    if (res != null) {
      if (res.status == FengshuiEnvironmentCorpus.suitableStatus) {
        bg = const Color(0xFFECFDF5);
        borderColor = const Color(0xFF10B981).withValues(alpha: 0.3);
      } else {
        bg = const Color(0xFFFFF8E8);
        borderColor = const Color(0xFFD59A36).withValues(alpha: 0.28);
      }
    }
    return GestureDetector(
      onTap: loading ? null : () => _analyzeItem(dir, gua),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: loading ? _themeColor : borderColor,
              width: loading ? 1.5 : 1),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(gua,
                      style: AppTextStyles.titleSmall.copyWith(
                          fontSize: 16,
                          color: res != null ? null : AppColors.textPrimary)),
                  Text(dir,
                      style: AppTextStyles.bodySmall
                          .copyWith(fontSize: 10, color: AppColors.textHint)),
                ],
              ),
      ),
    );
  }

  Widget _buildResultCard(String key, _PalaceResult res) {
    final parts = key.split('-');
    final dir = parts.isNotEmpty ? parts[0] : '';
    final gua = parts.length > 1 ? parts[1] : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$dir·$gua',
                            style: TextStyle(
                                color: _themeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      res.itemName,
                      style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
                    ),
                    if (res.userQuery != null && res.userQuery!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '您输入的「${res.userQuery}」已匹配为「${res.itemName}」',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatusBadge(res.status),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final suitable = status == FengshuiEnvironmentCorpus.suitableStatus;
    final color = suitable ? const Color(0xFF138A72) : const Color(0xFFB7791F);
    final background =
        suitable ? const Color(0xFFECFDF5) : const Color(0xFFFFF8E8);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            suitable
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            size: 19,
            color: color,
          ),
          const SizedBox(width: 9),
          Text(
            status,
            style: AppTextStyles.titleSmall.copyWith(
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FengshuiItemQueryDialog extends StatefulWidget {
  final String dir;
  final String gua;
  final Color themeColor;

  const _FengshuiItemQueryDialog({
    required this.dir,
    required this.gua,
    required this.themeColor,
  });

  @override
  State<_FengshuiItemQueryDialog> createState() =>
      _FengshuiItemQueryDialogState();
}

class _FengshuiItemQueryDialogState extends State<_FengshuiItemQueryDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<String> _allKeys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final palace =
        await FengshuiEnvironmentCorpus.loadPalaceStructured(widget.gua);
    if (!mounted) return;
    setState(() {
      _allKeys = palace != null
          ? FengshuiEnvironmentCorpus.uniqueSuggestKeys(palace)
          : [];
      _loading = false;
    });
  }

  /// 输入为空时展示一批条目便于点选；有输入时优先前缀、再包含、再编辑距离相近推荐。
  List<String> _suggestions(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      return _allKeys.take(36).toList();
    }
    final byPrefix = _allKeys.where((k) => k.startsWith(q)).toList()..sort();
    if (byPrefix.isNotEmpty) return byPrefix.take(50).toList();
    final bySub = _allKeys.where((k) => k.contains(q)).toList()..sort();
    if (bySub.isNotEmpty) return bySub.take(50).toList();
    return FengshuiEnvironmentCorpus.rankKeysBySimilarity(_allKeys, q,
        limit: 30);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions(_controller.text);
    final qTrim = _controller.text.trim();
    final queryEmpty = qTrim.isEmpty;
    final suggestSimilarOnly = !queryEmpty &&
        suggestions.isNotEmpty &&
        !_allKeys.any((k) => k.startsWith(qTrim)) &&
        !_allKeys.any((k) => k.contains(qTrim));
    final sheetH =
        (MediaQuery.sizeOf(context).height * 0.42).clamp(300.0, 440.0);

    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('${widget.dir}方位（${widget.gua}）',
          style: AppTextStyles.titleMedium),
      content: SizedBox(
        width: double.maxFinite,
        height: sheetH,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('输入物品或环境名称', style: AppTextStyles.bodySmall),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    focusNode: _focus,
                    decoration: InputDecoration(
                      hintText: '如：鱼缸、厨房、镜子',
                      hintStyle: AppTextStyles.hint,
                      filled: true,
                      fillColor: AppColors.cardBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(context),
                  ),
                  if (_allKeys.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '暂时没有可用内容，请稍后重试。',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      queryEmpty
                          ? '常见条目'
                          : (suggestSimilarOnly ? '为你找到以下相近内容' : '相关条目'),
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textHint, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Material(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: AppColors.divider.withValues(alpha: 0.35)),
                          itemBuilder: (ctx, i) {
                            final key = suggestions[i];
                            return InkWell(
                              onTap: () {
                                _controller.text = key;
                                _controller.selection =
                                    TextSelection.collapsed(offset: key.length);
                                setState(() {});
                                _focus.requestFocus();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child:
                                    Text(key, style: AppTextStyles.bodySmall),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ] else if (!queryEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '没有找到相关内容，请更换关键词或浏览常见条目。',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textHint, fontSize: 11),
                    ),
                    const Spacer(),
                  ] else
                    const Spacer(),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: AppColors.textHint)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : () => _submit(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.themeColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('查看状态'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }
}

class _PalaceResult {
  final String itemName;

  /// 与 [itemName] 不同时表示由用户原词模糊匹配到收录名。
  final String? userQuery;
  final String status;

  _PalaceResult({
    required this.itemName,
    this.userQuery,
    required this.status,
  });
}
