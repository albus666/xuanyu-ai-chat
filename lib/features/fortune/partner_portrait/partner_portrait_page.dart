import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_session_scope.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/widgets/ai_generated_badge.dart';
import '../../../core/widgets/app_share_more_button.dart';
import '../../profile/recharge_page.dart';
import '../ziwei/ziwei_archive_store.dart';
import '../ziwei/ziwei_input_page.dart';
import 'partner_portrait_models.dart';
import 'partner_portrait_service.dart';

class PartnerPortraitPage extends StatefulWidget {
  const PartnerPortraitPage({super.key});

  @override
  State<PartnerPortraitPage> createState() => _PartnerPortraitPageState();
}

class _PartnerPortraitPageState extends State<PartnerPortraitPage> {
  static const _navy = Color(0xFF18325F);
  static const _ink = Color(0xFF20355B);
  static const _muted = Color(0xFF74819A);
  static const _gold = Color(0xFFD4A952);
  static const _surface = Color(0xFFFDFCF9);

  List<ZiweiArchiveRecord> _records = const <ZiweiArchiveRecord>[];
  ZiweiArchiveRecord? _selected;
  PartnerPortraitState? _state;
  bool _loading = true;
  bool _purchasing = false;
  bool _purchaseFlow = false;
  String? _error;
  ApiSessionScope _scope = ApiSessionScope();
  int _profilesGeneration = 0;
  int _previewGeneration = 0;
  final _overlays = <Route<dynamic>>{};

  WidgetBuilder _accountOverlay(WidgetBuilder builder) => (context) {
        final route = ModalRoute.of(context);
        if (route != null) {
          _overlays.add(route);
          route.popped.then((_) => _overlays.remove(route));
        }
        return builder(context);
      };

  Future<T?> _showAccountDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) =>
      showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: _accountOverlay(builder),
      );

  Future<T?> _showAccountSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool useSafeArea = true,
    bool isScrollControlled = false,
    bool showDragHandle = true,
    Color? backgroundColor,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        useSafeArea: useSafeArea,
        isScrollControlled: isScrollControlled,
        showDragHandle: showDragHandle,
        backgroundColor: backgroundColor,
        builder: _accountOverlay(builder),
      );

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_handleAccountChanged);
    _loadProfiles();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_handleAccountChanged);
    super.dispose();
  }

  void _handleAccountChanged() {
    if (!mounted) return;
    final staleOverlays = _overlays.toList();
    _overlays.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in staleOverlays) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
    _scope = ApiSessionScope();
    _profilesGeneration++;
    _previewGeneration++;
    setState(() {
      _records = const <ZiweiArchiveRecord>[];
      _selected = null;
      _state = null;
      _purchasing = false;
      _purchaseFlow = false;
      _error = null;
    });
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final scope = _scope;
    final generation = ++_profilesGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final records = await ZiweiArchiveStore.loadAll();
    records.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    if (!mounted || !scope.current || generation != _profilesGeneration) return;
    final previousId = _selected?.id;
    final selected = records.cast<ZiweiArchiveRecord?>().firstWhere(
          (item) => item?.id == previousId,
          orElse: () => records.isEmpty ? null : records.first,
        );
    setState(() {
      _records = records;
      _selected = selected;
      _state = null;
      _loading = selected != null;
    });
    if (selected != null) await _loadPreview();
  }

  Future<void> _loadPreview() async {
    final scope = _scope;
    final generation = ++_previewGeneration;
    final record = _selected;
    if (record == null) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result =
          await PartnerPortraitService.preview(record.profile, scope: scope);
      if (!mounted ||
          !scope.current ||
          generation != _previewGeneration ||
          record.id != _selected?.id) {
        return;
      }
      setState(() {
        _state = result;
        _loading = false;
      });
    } on ApiSessionChangedException {
      return;
    } on PartnerPortraitException catch (error) {
      if (!mounted ||
          !scope.current ||
          generation != _previewGeneration ||
          record.id != _selected?.id) {
        return;
      }
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _createArchive() async {
    final scope = _scope;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ZiweiInputPage()),
    );
    if (mounted && scope.current) await _loadProfiles();
  }

  Future<void> _chooseArchive() async {
    final scope = _scope;
    if (_records.isEmpty) {
      await _createArchive();
      return;
    }
    final chosen = await _showAccountSheet<ZiweiArchiveRecord>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF9FAFC),
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          const Text(
            '选择命盘',
            style: TextStyle(
              color: _navy,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '选择用于生成伴侣画像的命盘。',
            style: TextStyle(color: _muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          ..._records.map(
            (record) => Card(
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE8EEFF),
                  child: Text(
                    record.profile.name.characters.first,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(record.profile.name),
                subtitle: Text(
                  '${record.relationshipLabel} · ${record.profile.gender} · '
                  '${record.profile.clockBirthDate.year}年${record.profile.clockBirthDate.month}月${record.profile.clockBirthDate.day}日',
                ),
                trailing: record.id == _selected?.id
                    ? const Icon(Icons.check_circle_rounded, color: _gold)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, record),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _createArchive();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建紫微命盘'),
          ),
        ],
      ),
    );
    if (chosen == null ||
        chosen.id == _selected?.id ||
        !mounted ||
        !scope.current) {
      return;
    }
    setState(() {
      _selected = chosen;
      _state = null;
    });
    await _loadPreview();
  }

  Future<List<String>?> _chooseBundleTests() async {
    final tests = _state?.tests ?? const <PartnerPortraitTestItem>[];
    if (tests.length < 3) return null;
    if (tests.length == 3) return tests.map((item) => item.id).toList();
    final selected = <String>{
      ...tests.where((item) => !item.owned).take(3).map((item) => item.id),
    };
    return _showAccountSheet<List<String>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择3项测试',
                style: TextStyle(
                  color: _navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: tests.map((item) {
                    final checked = selected.contains(item.id);
                    return CheckboxListTile(
                      value: checked,
                      activeColor: _navy,
                      title: Text(item.title),
                      subtitle: Text(
                          item.owned ? '已解锁，不会重复收费' : '${_price(item.price)}币'),
                      onChanged: (_) {
                        setSheetState(() {
                          if (checked) {
                            selected.remove(item.id);
                          } else if (selected.length < 3) {
                            selected.add(item.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: selected.length == 3
                    ? () => Navigator.pop(sheetContext, selected.toList())
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _navy,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text('确认选择（${selected.length}/3）'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _purchase({
    required String kind,
    PartnerPortraitTestItem? test,
  }) async {
    final record = _selected;
    final state = _state;
    if (record == null || state == null || _purchaseFlow) return;
    final scope = _scope;
    bool current() => mounted && scope.current && record.id == _selected?.id;
    _purchaseFlow = true;
    try {
      List<String> testIds = const <String>[];
      var amount = kind == 'report' ? state.reportPrice : test?.price ?? 0;
      var title = kind == 'report' ? '完整伴侣画像' : test?.title ?? '单项测试';
      if (kind == 'bundle') {
        final picked = await _chooseBundleTests();
        if (picked == null || !mounted || !current()) return;
        testIds = picked;
        amount = state.bundlePrice;
        title = '完整报告＋任选3项';
      }
      if (!mounted || !current()) return;
      final confirmed = await _showAccountDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text('解锁$title'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本次最高支付 ${_price(amount)} 玄遇币'),
              const SizedBox(height: 8),
              Text(
                '当前余额 ${_price(state.walletBalance)} 玄遇币',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 12),
              const Text(
                '系统会自动扣除已经购买的重复项目。一次解锁后永久保存，重新打开不再收费。',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不解锁'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _navy),
              child: const Text('确认解锁'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !current()) return;
      setState(() => _purchasing = true);
      final result = await PartnerPortraitService.purchase(
        record.profile,
        kind: kind,
        testId: test?.id,
        testIds: testIds,
        requestKey: '${DateTime.now().microsecondsSinceEpoch}-${record.id}',
        scope: scope,
      );
      if (!mounted || !current()) return;
      _previewGeneration++;
      setState(() => _state = result);
      showAppToast(context, '内容已解锁并永久保存');
      if (kind == 'test' && test != null) {
        final latest = result.tests.firstWhere((item) => item.id == test.id);
        if (latest.result != null) _showTestResult(latest);
      }
    } on ApiSessionChangedException {
      return;
    } on PartnerPortraitException catch (error) {
      if (!mounted || !current()) return;
      if (error.reason == 'insufficient_balance') {
        final recharge = await _showAccountDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            title: const Text('玄遇币余额不足'),
            content: Text(
              '当前${_price(error.balance)}币，本次需要${_price(error.requiredAmount)}币。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('去充值'),
              ),
            ],
          ),
        );
        if (recharge == true && mounted && current()) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const RechargePage()),
          );
          if (current()) await _loadPreview();
        }
      } else {
        showAppToast(context, error.message);
      }
    } finally {
      if (mounted && scope.current) {
        setState(() {
          _purchasing = false;
          _purchaseFlow = false;
        });
      }
    }
  }

  void _showChapter(PartnerPortraitChapter chapter) {
    if (!chapter.unlocked) {
      _purchase(kind: 'report');
      return;
    }
    _showAccountSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  chapter.detail,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15.5,
                    height: 1.85,
                  ),
                ),
                if (chapter.relationshipTip.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4FE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '相处提醒｜${chapter.relationshipTip}',
                      style: const TextStyle(color: _ink, height: 1.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTestResult(PartnerPortraitTestItem item) {
    final result = item.result;
    if (result == null) return;
    _showAccountSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .45,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
          children: [
            Text(
              result.headline.isEmpty ? item.title : result.headline,
              style: const TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            if (result.keyPoints.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    result.keyPoints.map((item) => _Pill(text: item)).toList(),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              result.answer,
              style: const TextStyle(
                color: _ink,
                fontSize: 15.5,
                height: 1.85,
              ),
            ),
            if (result.action.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0D9A9)),
                ),
                child: Text(
                  '可以这样做｜${result.action}',
                  style: const TextStyle(color: _ink, height: 1.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 58,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10, top: 5, bottom: 5),
          child: Material(
            color: Colors.white.withValues(alpha: .78),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE3E9F1)),
            ),
            child: IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        title: const Text(
          '伴侣画像',
          style: TextStyle(
            color: _navy,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: const [
          AppShareMoreButton(
            toolRoute: '/partner_portrait',
            title: '伴侣画像',
            shareText: '我在玄遇查看伴侣画像，快来一起发现更适合自己的关系相处方式。',
            iconColor: _navy,
          ),
          SizedBox(width: 6),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCFBF8), Color(0xFFF3F7F9), Color(0xFFF2F4FA)],
            stops: [0, .48, 1],
          ),
        ),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_records.isEmpty && !_loading) return _emptyState();
    if (_loading && _state == null) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }
    if (_error != null && _state == null) return _errorState();
    final state = _state;
    final record = _selected;
    if (state == null || record == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _loadPreview,
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 34),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: AiGeneratedBadge(compact: true),
          ),
          const SizedBox(height: 10),
          _hero(record),
          const SizedBox(height: 12),
          _keywords(state),
          const SizedBox(height: 18),
          _sectionTitle('完整伴侣画像', state.reportOwned ? '已永久解锁' : '共6章'),
          const SizedBox(height: 8),
          _chapterList(state),
          if (!state.reportOwned) ...[
            const SizedBox(height: 12),
            _unlockButton(state),
            const SizedBox(height: 7),
            Text(
              state.purchaseRule,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 22),
          _sectionTitle('单项测试', '想先了解哪一个问题？'),
          const SizedBox(height: 8),
          ...state.tests.map(_testCard),
          if (state.tests.length >= 3) ...[
            const SizedBox(height: 8),
            _bundleCard(state),
          ],
          const SizedBox(height: 18),
          Text(
            state.disclaimer,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 10.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => ListView(
        padding: const EdgeInsets.fromLTRB(22, 50, 22, 30),
        children: [
          const SizedBox(height: 30),
          const Icon(Icons.blur_circular_rounded,
              size: 82, color: Color(0xFF93A9D5)),
          const SizedBox(height: 22),
          const Text(
            '先准备一张自己的紫微命盘',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _navy, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            '选择一张自己的命盘，即可查看专属伴侣画像。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.6),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: _createArchive,
            icon: const Icon(Icons.add_rounded),
            label: const Text('创建紫微命盘'),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: _muted, size: 50),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _loadPreview, child: const Text('重新加载')),
            ],
          ),
        ),
      );

  Widget _hero(ZiweiArchiveRecord record) => Container(
        height: 148,
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFE6EFFD), Color(0xFFF8F0E3)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white, width: 1.4),
          boxShadow: const [
            BoxShadow(
                color: Color(0x18314B7A),
                blurRadius: 28,
                offset: Offset(0, 12)),
          ],
        ),
        child: Stack(
          children: [
            const Positioned.fill(
                child: CustomPaint(painter: _PalaceOrbitPainter())),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '读懂关系中的TA',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 22,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '性格、外貌、内心、事业、财富与身体',
                  style: TextStyle(color: Color(0xFF526B96), fontSize: 12.5),
                ),
                const Spacer(),
                InkWell(
                  onTap: _chooseArchive,
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.blur_circular_rounded,
                            size: 18, color: Color(0xFF7791C5)),
                        const SizedBox(width: 7),
                        Text('当前命盘  ${record.profile.name}',
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 3),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: _muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _keywords(PartnerPortraitState state) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x10213F61), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            const Text('你的伴侣关键词',
                style: TextStyle(
                    color: _navy, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 11),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children:
                  state.keywords.map((item) => _Pill(text: item)).toList(),
            ),
            const SizedBox(height: 10),
            Text(
              state.headline,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: _muted, fontSize: 11.5, height: 1.45),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String title, String trailing) => Row(
        children: [
          const Text('✦', style: TextStyle(color: _gold)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800))),
          Text(trailing, style: const TextStyle(color: _muted, fontSize: 11.5)),
        ],
      );

  Widget _chapterList(PartnerPortraitState state) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .86),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E6EF)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D173C59), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            for (var index = 0; index < state.chapters.length; index++) ...[
              _chapterTile(state.chapters[index], index),
              if (index != state.chapters.length - 1)
                const Divider(height: 1, indent: 62, color: Color(0xFFE8EBF1)),
            ],
          ],
        ),
      );

  Widget _chapterTile(PartnerPortraitChapter chapter, int index) {
    final icons = <IconData>[
      Icons.cloud_outlined,
      Icons.flight_outlined,
      Icons.self_improvement_rounded,
      Icons.work_outline_rounded,
      Icons.savings_outlined,
      Icons.air_rounded,
    ];
    final tones = <Color>[
      const Color(0xFFEAE5FF),
      const Color(0xFFE1ECFF),
      const Color(0xFFDFF5F4),
      const Color(0xFFFFEED2),
      const Color(0xFFDDF4F2),
      const Color(0xFFE7E9FF),
    ];
    return InkWell(
      onTap: () => _showChapter(chapter),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(color: tones[index], shape: BoxShape.circle),
              child: Icon(icons[index], color: _navy, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chapter.title,
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(
                    chapter.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color:
                            chapter.unlocked ? _muted : const Color(0xFF9AA4B7),
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              chapter.unlocked
                  ? Icons.chevron_right_rounded
                  : Icons.lock_outline_rounded,
              color: chapter.unlocked ? _gold : const Color(0xFFC8A960),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _unlockButton(PartnerPortraitState state) => FilledButton(
        onPressed: _purchasing ? null : () => _purchase(kind: 'report'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF667EBE),
          disabledBackgroundColor: const Color(0xFFA6B3D7),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE7C879)),
          ),
        ),
        child: _purchasing
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text('${_price(state.reportPrice)}币  解锁完整报告',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );

  Widget _testCard(PartnerPortraitTestItem item) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .86),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE3E7EF)),
        ),
        child: ListTile(
          onTap: _purchasing
              ? null
              : () => item.owned && item.result != null
                  ? _showTestResult(item)
                  : _purchase(kind: 'test', test: item),
          leading: CircleAvatar(
            backgroundColor: _testTone(item.tone),
            child: Icon(_testIcon(item.focusCode), color: _navy, size: 19),
          ),
          title: Text(item.title,
              style: const TextStyle(
                  color: _ink, fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: item.subtitle.isEmpty
              ? null
              : Text(item.subtitle,
                  style: const TextStyle(color: _muted, fontSize: 11.5)),
          trailing: item.owned
              ? const _OwnedBadge()
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFAEF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8C97F)),
                  ),
                  child: Text('${_price(item.price)}币',
                      style: const TextStyle(
                          color: Color(0xFFB57A20),
                          fontWeight: FontWeight.w700)),
                ),
        ),
      );

  Widget _bundleCard(PartnerPortraitState state) => InkWell(
        onTap: _purchasing ? null : () => _purchase(kind: 'bundle'),
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFFFBF1), Color(0xFFF4E8CD)]),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE1C47F)),
          ),
          child: Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, color: Color(0xFFB67D25)),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('完整报告＋任选3项',
                      style:
                          TextStyle(color: _ink, fontWeight: FontWeight.w800))),
              Text('${_price(state.bundlePrice)}币',
                  style: const TextStyle(
                      color: Color(0xFFB2771C),
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFB2771C)),
            ],
          ),
        ),
      );

  static String _price(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  static Color _testTone(String tone) => switch (tone) {
        'lilac' => const Color(0xFFEAE5FF),
        'apricot' => const Color(0xFFFFEED3),
        'sage' => const Color(0xFFDFF2E9),
        _ => const Color(0xFFE1ECFF),
      };

  static IconData _testIcon(String code) => switch (code) {
        'career' => Icons.work_outline_rounded,
        'wealth' => Icons.savings_outlined,
        'innerWorld' => Icons.chat_bubble_outline_rounded,
        'appearance' => Icons.visibility_outlined,
        'pressure' => Icons.air_rounded,
        _ => Icons.favorite_border_rounded,
      };
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAEF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8CB89)),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF9B6D24),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );
}

class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFFEAF5F1),
            borderRadius: BorderRadius.circular(14)),
        child: const Text('已解锁',
            style: TextStyle(
                color: Color(0xFF397B68),
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

class _PalaceOrbitPainter extends CustomPainter {
  const _PalaceOrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .77, size.height * .47);
    const gold = Color(0xFFD7B15E);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(
        center,
        22.0 * i,
        Paint()
          ..color = const Color(0xFF87A5D7).withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final orbit = math.min(
      math.min(size.width * .22, 82.0),
      size.height * .4,
    );
    final line = Paint()
      ..color = gold.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawCircle(center, orbit, line);
    for (var i = 0; i < 12; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 12;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * orbit;
      canvas.drawLine(center, point,
          Paint()..color = const Color(0xFF9BB2D9).withValues(alpha: .10));
      final highlighted = i == 0;
      canvas.drawCircle(
        point,
        highlighted ? 8 : 4.2,
        Paint()
          ..color = highlighted
              ? const Color(0xFFFFF4CE)
              : Colors.white.withValues(alpha: .85),
      );
      canvas.drawCircle(
        point,
        highlighted ? 8 : 4.2,
        Paint()
          ..color = gold.withValues(alpha: highlighted ? .95 : .62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.drawCircle(
        center, 18, Paint()..color = Colors.white.withValues(alpha: .62));
    final tp = TextPainter(
      text: const TextSpan(
        text: '伴',
        style: TextStyle(
            color: Color(0xFFAD7C28),
            fontSize: 17,
            fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
