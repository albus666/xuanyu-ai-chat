import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/app/common/values/images.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/profile/recharge_page.dart';
import 'package:xuanyu/features/wish/models/wish_feed_state.dart';
import 'package:xuanyu/features/wish/models/wish_entry.dart';
import 'package:xuanyu/features/wish/models/wish_pond_simulation.dart';
import 'package:xuanyu/features/wish/services/wish_feed_service.dart';
import 'package:xuanyu/features/wish/widgets/wish_water_life_layer.dart';

enum _WishPrayerStage { entrance, writing, sending, completed }

class WishPrayerPage extends StatefulWidget {
  const WishPrayerPage({
    super.key,
    this.feedingEnabled = true,
    this.feedService = const WishFeedService(),
  });

  final bool feedingEnabled;
  final WishFeedService feedService;

  @override
  State<WishPrayerPage> createState() => _WishPrayerPageState();
}

class _WishPrayerPageState extends State<WishPrayerPage>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _ambientController;
  late final AnimationController _ritualController;
  bool _feedRequestPending = false;
  Timer? _feedingResetTimer;
  int _feedSequence = 0;

  _WishPrayerStage _stage = _WishPrayerStage.entrance;
  WishFeedState? _feedState;
  bool _feedStatusLoading = false;
  bool _feeding = false;
  String? _feedMessage;
  int _activeFeedQuantity = 1;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 96),
    )..repeat();
    _ritualController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9200),
    );
    if (widget.feedingEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFeedStatus());
    }
  }

  Future<void> _loadFeedStatus({bool showError = false}) async {
    if (!mounted || _feedStatusLoading || !widget.feedingEnabled) return;
    setState(() => _feedStatusLoading = true);
    try {
      final state = await widget.feedService.loadStatus();
      if (mounted) setState(() => _feedState = state);
    } on DioException catch (error) {
      if (showError && mounted) {
        showAppToast(context, _apiMessage(error, '鱼食信息加载失败'));
      }
    } catch (_) {
      if (showError && mounted) showAppToast(context, '鱼食信息加载失败');
    } finally {
      if (mounted) setState(() => _feedStatusLoading = false);
    }
  }

  String _apiMessage(DioException error, String fallback) {
    final raw = error.response?.data;
    if (raw is Map) return raw['message']?.toString() ?? fallback;
    return fallback;
  }

  String? _apiReason(DioException error) {
    return _apiErrorData(error)['reason']?.toString();
  }

  Map<String, dynamic> _apiErrorData(DioException error) {
    final raw = error.response?.data;
    if (raw is! Map) return <String, dynamic>{};
    final data = raw['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> _handleFeedTap() async {
    if (_feedStatusLoading || _feedRequestPending) return;
    _feedRequestPending = true;
    try {
      if (_feedState == null) {
        await _loadFeedStatus(showError: true);
        if (!mounted || _feedState == null) return;
      }
      final availableQuantities = _feedState!.availableFeedQuantities();
      final quantity = await _showFeedQuantitySheet(availableQuantities);
      if (quantity == null || !mounted) return;
      await _performFeed(quantity);
    } finally {
      _feedRequestPending = false;
    }
  }

  Future<void> _performFeed(int quantity) async {
    final wasFeeding = _feeding;
    final previousMessage = _feedMessage;
    setState(() {
      _feeding = true;
      _feedMessage = '正在撒下 $quantity 份鱼食';
    });
    try {
      final data = await widget.feedService.feed(quantity);
      if (!mounted) return;
      setState(() {
        _feedState = _feedState!.mergeBalance(data);
        _activeFeedQuantity = quantity;
        _feedMessage = '鱼儿正在靠近';
        _feedSequence++;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _feeding = wasFeeding;
        _feedMessage = previousMessage;
      });
      if (_apiReason(error) == 'no_food') {
        if (_feedState != null) {
          setState(() =>
              _feedState = _feedState!.mergeBalance(_apiErrorData(error)));
        }
        showAppToast(context, '鱼食不足，请点击下方购买鱼食');
      } else if (_apiReason(error) == 'invalid_quantity') {
        await _loadFeedStatus();
        if (mounted) showAppToast(context, '投喂份数已调整，请重新选择');
      } else {
        showAppToast(context, _apiMessage(error, '投喂失败，请稍后再试'));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _feeding = wasFeeding;
          _feedMessage = previousMessage;
        });
        showAppToast(context, '投喂失败，请稍后再试');
      }
    }
  }

  void _onFeedingStageChanged(WishFeedingStage stage) {
    if (!mounted || !_feeding) return;
    final message = switch (stage) {
      WishFeedingStage.approaching => '鱼儿正在靠近',
      WishFeedingStage.eating => '鱼儿正在吃食',
      WishFeedingStage.dispersing => '鱼儿正在慢慢游开',
      WishFeedingStage.complete => '投喂完成 · 愿温柔常伴你',
    };
    setState(() => _feedMessage = message);
  }

  void _onFeedingComplete() {
    if (!mounted || !_feeding) return;
    final sequence = _feedSequence;
    _feedingResetTimer?.cancel();
    _feedingResetTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || sequence != _feedSequence) return;
      if (_feedRequestPending) {
        _onFeedingComplete();
        return;
      }
      setState(() {
        _feeding = false;
        _feedMessage = null;
        _activeFeedQuantity = 1;
      });
    });
  }

  Future<int?> _showFeedQuantitySheet(List<int> quantities) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          key: const ValueKey<String>('wish-feed-quantity-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFF9FBFA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DDDC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              const Text(
                '这次投喂多少？',
                style: TextStyle(
                  color: Color(0xFF20353A),
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '现有 ${_feedState!.foodBalance} 份鱼食，选择后会一次撒下',
                style: const TextStyle(
                  color: Color(0xFF718084),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: quantities
                    .map(
                      (quantity) => ActionChip(
                        key: ValueKey<String>('wish-feed-quantity-$quantity'),
                        label: Text('$quantity 份'),
                        avatar: const Icon(Icons.grain_rounded, size: 18),
                        backgroundColor: const Color(0xFFE8F7F3),
                        side: const BorderSide(color: Color(0xFFB8DDD5)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        onPressed: () => Navigator.pop(sheetContext, quantity),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFoodPackages() async {
    if (_feedState == null || _feedState!.packages.isEmpty) {
      await _loadFeedStatus(showError: true);
    }
    if (!mounted || _feedState == null || _feedState!.packages.isEmpty) return;
    final selected = await showModalBottomSheet<WishFoodPackage>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _buildFoodPackageSheet(sheetContext),
    );
    if (selected != null && mounted) await _confirmFoodPurchase(selected);
  }

  Future<void> _confirmFoodPurchase(WishFoodPackage package) async {
    if ((_feedState?.walletBalance ?? 0) < package.price) {
      await _offerRecharge();
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认购买鱼食'),
            content: Text(
              '使用余额 ¥${package.price.toStringAsFixed(2)} 购买'
              '${package.quantity}份鱼食？',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认购买'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final data = await widget.feedService.purchase(package.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _feedState = _feedState!.mergeBalance(data));
      showAppToast(context, '${package.quantity}份鱼食已放入水域食袋');
    } on DioException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (_apiReason(error) == 'insufficient_balance') {
        await _offerRecharge();
      } else {
        showAppToast(context, _apiMessage(error, '购买失败，请稍后再试'));
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showAppToast(context, '购买失败，请稍后再试');
    }
  }

  Future<void> _offerRecharge() async {
    final goRecharge = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('余额不足'),
            content: const Text('当前钱包余额不足，是否前往充值？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('稍后再说'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('去充值'),
              ),
            ],
          ),
        ) ??
        false;
    if (!goRecharge || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RechargePage()),
    );
    if (mounted) await _loadFeedStatus(showError: true);
  }

  Future<void> _sendWish() async {
    final content = _textController.text.trim();
    if (content.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先写下你最真切的期盼')),
      );
      return;
    }

    _focusNode.unfocus();
    setState(() => _stage = _WishPrayerStage.sending);
    await _ritualController.forward(from: 0);
    if (!mounted) return;
    setState(() => _stage = _WishPrayerStage.completed);
  }

  void _openGate() {
    if (_feeding) return;
    setState(() => _stage = _WishPrayerStage.writing);
  }

  void _writeAnother() {
    _textController.clear();
    _ritualController.reset();
    setState(() => _stage = _WishPrayerStage.writing);
  }

  void _dismissCompleted() {
    _textController.clear();
    _ritualController.reset();
    setState(() => _stage = _WishPrayerStage.entrance);
  }

  @override
  void dispose() {
    _feedingResetTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _ambientController.dispose();
    _ritualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF172A42),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            ImageAssets.wishPrayerCourtyard,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x33203048),
                  Color(0x00192B42),
                  Color(0x180D6972),
                ],
                stops: <double>[0, 0.47, 1],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge(
              <Listenable>[
                _ambientController,
                _ritualController,
              ],
            ),
            builder: (context, _) {
              return CustomPaint(
                  painter: _WishAtmospherePainter(
                ambientProgress: _ambientController.value,
                ritualProgress: _stage == _WishPrayerStage.writing
                    ? 0
                    : _ritualController.value,
              ));
            },
          ),
          if (widget.feedingEnabled)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 420),
              opacity: _stage == _WishPrayerStage.entrance
                  ? 1
                  : _stage == _WishPrayerStage.sending
                      ? 0.12
                      : 0.32,
              child: WishWaterLifeLayer(
                feedSequence: _feedSequence,
                feedQuantity: _activeFeedQuantity,
                onFeedingStageChanged: _onFeedingStageChanged,
                onFeedingComplete: _onFeedingComplete,
              ),
            ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keyboardVisible = bottomInset > 0;
                final sceneGap = keyboardVisible
                    ? 34.0
                    : _stage == _WishPrayerStage.sending
                        ? (constraints.maxHeight * 0.68).clamp(430.0, 660.0)
                        : (constraints.maxHeight * 0.28).clamp(120.0, 250.0);
                return GestureDetector(
                  onTap: () {
                    if (_stage == _WishPrayerStage.completed) {
                      _dismissCompleted();
                    } else if (_stage == _WishPrayerStage.writing &&
                        !keyboardVisible) {
                      if (_textController.text.trim().isNotEmpty) {
                        showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (ctx) => AlertDialog(
                            title: const Text('关闭祈福'),
                            content: const Text('您已写下心愿内容，确定要关闭吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('继续祈福'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _textController.clear();
                                  setState(
                                      () => _stage = _WishPrayerStage.entrance);
                                },
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      } else {
                        setState(() => _stage = _WishPrayerStage.entrance);
                      }
                    }
                    _focusNode.unfocus();
                  },
                  behavior: HitTestBehavior.translucent,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      bottom: keyboardVisible ? bottomInset + 12 : 18,
                    ),
                    child: Column(
                      children: <Widget>[
                        _buildTopBar(),
                        SizedBox(height: sceneGap),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: switch (_stage) {
                              _WishPrayerStage.entrance =>
                                const SizedBox.shrink(
                                  key: ValueKey<String>('wish-entrance'),
                                ),
                              _WishPrayerStage.writing => _buildWritingCard(),
                              _WishPrayerStage.sending => _buildSendingCard(),
                              _WishPrayerStage.completed =>
                                const SizedBox.shrink(
                                  key: ValueKey<String>(
                                    'wish-completed-placeholder',
                                  ),
                                ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_stage == _WishPrayerStage.completed) _buildCompletedOverlay(),
          if (_stage == _WishPrayerStage.entrance) _buildGateTarget(screenSize),
          if (widget.feedingEnabled && _stage == _WishPrayerStage.entrance)
            _buildFeedControl(),
        ],
      ),
    );
  }

  Widget _buildFeedControl() {
    final foodBalance = _feedState?.foodBalance;
    return Positioned(
      key: const ValueKey<String>('wish-feed-control'),
      right: 12,
      bottom: MediaQuery.paddingOf(context).bottom + 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 50,
          decoration: BoxDecoration(
            color: const Color(0xD9234654),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0x80F4D79D)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x52061720),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                key: const ValueKey<String>('wish-feed-button'),
                onTap: _handleFeedTap,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(25),
                ),
                child: Semantics(
                  label: foodBalance == null ? '投喂' : '鱼食剩余$foodBalance份',
                  child: SizedBox(
                    width: 50,
                    height: 54,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        if (_feedStatusLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Color(0xFFFFE6B1),
                            ),
                          )
                        else
                          const Icon(
                            Icons.set_meal_rounded,
                            size: 21,
                            color: Color(0xFFFFE3A3),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 28, height: 1, color: const Color(0x45FFFFFF)),
              InkWell(
                key: const ValueKey<String>('wish-feed-shop'),
                onTap: _showFoodPackages,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(25),
                ),
                child: const SizedBox(
                  width: 50,
                  height: 38,
                  child: Icon(
                    Icons.add_rounded,
                    color: Color(0xFFFFE3A3),
                    size: 21,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFoodPackageSheet(BuildContext sheetContext) {
    final state = _feedState!;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey<String>('wish-feed-packages'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        decoration: const BoxDecoration(
          color: Color(0xFFF9FBFA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DDDC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 17),
            const Text(
              '水域鱼食',
              style: TextStyle(
                color: Color(0xFF20353A),
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '现有 ${state.foodBalance} 份  ·  玄遇币 ${state.walletBalance.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF718084), fontSize: 13),
            ),
            const SizedBox(height: 18),
            ...state.packages.map(
              (package) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () => Navigator.pop(sheetContext, package),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 14, 13, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE4EBE8)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F7F3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.grain_rounded,
                              color: Color(0xFF3BAA99),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  package.name,
                                  style: const TextStyle(
                                    color: Color(0xFF24373B),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${package.quantity}份 · 可选择多份一起投喂',
                                  style: const TextStyle(
                                    color: Color(0xFF829093),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '¥${package.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFFC78E43),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFABB5B5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGateTarget(Size screenSize) {
    return Positioned(
      key: const ValueKey<String>('wish-gate'),
      left: screenSize.width * 0.20,
      top: screenSize.height * 0.47,
      width: screenSize.width * 0.60,
      height: screenSize.height * 0.20,
      child: Semantics(
        button: true,
        label: _feedMessage ?? '轻触山门，进入祈福',
        child: InkWell(
          onTap: _openGate,
          customBorder: const CircleBorder(),
          splashColor: const Color(0x55E8C983),
          highlightColor: const Color(0x22FFF1C9),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                final pulse = 0.58 +
                    math.sin(_ambientController.value * math.pi * 2) * 0.12;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(24, 43, 57, pulse),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x66F3D79B)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: Text(
                      _feedMessage ?? '轻触山门',
                      key: ValueKey<String>(_feedMessage ?? 'gate'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFEBC0),
                        fontSize: 13,
                        letterSpacing: 1.5,
                        shadows: <Shadow>[
                          Shadow(color: Color(0x99000000), blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: <Widget>[
          Material(
            color: const Color(0x52213B4D),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0x52FFFFFF)),
            ),
            child: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              color: Colors.white,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48, height: 48),
        ],
      ),
    );
  }

  Widget _buildWritingCard() {
    return _FrostedWishCard(
      key: const ValueKey<String>('wish-writing'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            WishPrayerCopy.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            WishPrayerCopy.prompt,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey<String>('wish-input'),
            controller: _textController,
            focusNode: _focusNode,
            maxLength: 120,
            minLines: 3,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              color: Color(0xFF22364B),
              fontSize: 16,
              height: 1.55,
            ),
            decoration: InputDecoration(
              hintText: '我希望……',
              hintStyle: const TextStyle(color: Color(0xFF8B98A5)),
              filled: true,
              fillColor: const Color(0xEFFFFFFF),
              counterStyle: const TextStyle(color: Color(0xBFFFFFFF)),
              contentPadding: const EdgeInsets.fromLTRB(17, 15, 17, 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFE3C689), Color(0xFFB98F50)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x55D8B36A),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: TextButton(
                key: const ValueKey<String>('send-wish'),
                onPressed: _sendWish,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF203247),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  '寄出心愿',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendingCard() {
    return Container(
      key: const ValueKey<String>('wish-sending'),
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0x8A172A3E),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x40FFF2D2)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x4006101B), blurRadius: 18),
        ],
      ),
      child: AnimatedBuilder(
        animation: _ritualController,
        builder: (context, _) {
          final progress = _ritualController.value;
          final message = progress < 0.18
              ? '心愿正在凝成一束微光'
              : progress < 0.82
                  ? '愿光正沿水面缓缓前行'
                  : '愿光正进入天地之门';
          return Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              letterSpacing: 2,
              shadows: <Shadow>[
                Shadow(color: Color(0x99000000), blurRadius: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompletedCard() {
    return GestureDetector(
      onTap: () {},
      child: _FrostedWishCard(
        key: const ValueKey<String>('wish-completed'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0x1AFFF1CB),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x99E8CD91)),
                boxShadow: const [
                  BoxShadow(color: Color(0x33E8CD91), blurRadius: 18),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFFFE4A8),
                size: 23,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              WishPrayerCopy.completion,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w600,
                height: 1.75,
                letterSpacing: 5,
                shadows: <Shadow>[
                  Shadow(color: Color(0x99000000), blurRadius: 14),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 96,
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x00E5CB94),
                    Color(0xCCE5CB94),
                    Color(0x00E5CB94)
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF4DDAA), Color(0xFFD0AC68)],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [
                    BoxShadow(color: Color(0x3DD9B56D), blurRadius: 16),
                  ],
                ),
                child: TextButton(
                  onPressed: _writeAnother,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF203247),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    '再写一个',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, letterSpacing: 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedOverlay() {
    return Positioned.fill(
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey<String>('wish-completed-dismiss'),
                behavior: HitTestBehavior.opaque,
                onTap: _dismissCompleted,
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildCompletedCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrostedWishCard extends StatelessWidget {
  const _FrostedWishCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(30));
    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 370),
        decoration: const BoxDecoration(
          borderRadius: radius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x73030B13),
              blurRadius: 34,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xD12B4658), Color(0xC8193145)],
                ),
                borderRadius: radius,
                border: Border.all(color: const Color(0x66FFF3D5)),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _WishAtmospherePainter extends CustomPainter {
  const _WishAtmospherePainter({
    required this.ambientProgress,
    required this.ritualProgress,
  });

  final double ambientProgress;
  final double ritualProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final cloudPaint = Paint()..color = const Color(0x18FFFFFF);
    final drift = math.sin(ambientProgress * math.pi * 2) * size.width * 0.05;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.16 + drift, size.height * 0.36),
        width: size.width * 0.68,
        height: size.height * 0.08,
      ),
      cloudPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.86 - drift, size.height * 0.43),
        width: size.width * 0.78,
        height: size.height * 0.10,
      ),
      cloudPaint,
    );

    final particlePaint = Paint();
    for (var i = 0; i < 24; i++) {
      final baseX = ((i * 47) % 101) / 100;
      final travel = (ambientProgress + i / 24) % 1;
      final x =
          (baseX + math.sin(travel * math.pi * 2 + i) * 0.025) * size.width;
      final y = (0.22 + travel * 0.68) * size.height;
      final opacity = math.sin(travel * math.pi).clamp(0.0, 1.0);
      particlePaint.color = Color.fromRGBO(255, 236, 188, opacity * 0.52);
      canvas.drawCircle(Offset(x, y), 0.8 + (i % 3) * 0.45, particlePaint);
    }

    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final progress = (ambientProgress + i / 3) % 1;
      ripplePaint.color = Color.fromRGBO(235, 223, 195, (1 - progress) * 0.20);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5, size.height * 0.79),
          width: size.width * (0.08 + progress * 0.54),
          height: size.height * (0.008 + progress * 0.035),
        ),
        ripplePaint,
      );
    }

    if (ritualProgress > 0) {
      const gatherEnd = 0.18;
      const enterStart = 0.82;
      final travelProgress =
          ((ritualProgress - gatherEnd) / (enterStart - gatherEnd))
              .clamp(0.0, 1.0);
      final easedTravel = Curves.easeInOutCubic.transform(travelProgress);
      final center = Offset(
        size.width * 0.5,
        size.height * (0.82 - easedTravel * 0.255),
      );
      final gatherProgress = (ritualProgress / gatherEnd).clamp(0.0, 1.0);
      final enterProgress =
          ((ritualProgress - enterStart) / (1 - enterStart)).clamp(0.0, 1.0);
      final lightOpacity = ritualProgress < enterStart
          ? Curves.easeOut.transform(gatherProgress)
          : 1 - Curves.easeIn.transform(enterProgress);
      final lightRadius = ritualProgress < enterStart
          ? 14 + 22 * Curves.easeOut.transform(gatherProgress)
          : 36 - 30 * Curves.easeIn.transform(enterProgress);
      final glow = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Color.fromRGBO(255, 250, 225, lightOpacity),
            Color.fromRGBO(236, 197, 113, lightOpacity * 0.68),
            const Color(0x00E5C47F),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: lightRadius),
        );
      canvas.drawCircle(center, lightRadius, glow);
      canvas.drawCircle(
        center,
        3.5 * lightOpacity,
        Paint()..color = Color.fromRGBO(255, 248, 214, lightOpacity),
      );

      if (enterProgress > 0) {
        final doorway = Offset(size.width * 0.5, size.height * 0.565);
        final doorwayGlow = Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              Color.fromRGBO(255, 245, 205, 0.82 * enterProgress),
              Color.fromRGBO(232, 190, 104, 0.40 * enterProgress),
              const Color(0x00E8BE68),
            ],
          ).createShader(
            Rect.fromCenter(
              center: doorway,
              width: size.width * 0.20,
              height: size.height * 0.10,
            ),
          );
        canvas.drawOval(
          Rect.fromCenter(
            center: doorway,
            width: size.width * 0.20,
            height: size.height * 0.10,
          ),
          doorwayGlow,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WishAtmospherePainter oldDelegate) {
    return oldDelegate.ambientProgress != ambientProgress ||
        oldDelegate.ritualProgress != ritualProgress;
  }
}
