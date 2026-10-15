import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/core/local/account_preference_scope.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/app/common/values/images.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_prayer_feedback_service.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';
import 'package:xuanyu/features/merit/services/muyu_knock_sound.dart';
import 'package:xuanyu/features/merit/widgets/muyu_knock_widget.dart';

/// 应用内全局木鱼状态。悬浮木鱼与木鱼主页共用同一份存档，避免计数互相覆盖。
class MuyuFloatingController extends ChangeNotifier {
  MuyuFloatingController._() {
    apiSessionChanges.addListener(_accountChanged);
  }

  static final MuyuFloatingController instance = MuyuFloatingController._();
  static const _enabledKey = 'muyu_floating_enabled_v1';

  Future<void>? _initializing;
  MeritSaveData? _data;
  Timer? _saveDebounce;
  Timer? _feedbackClear;
  List<String> _feedbackTexts = meritPrayerFeedbackTexts;
  int _feedbackIndex = 0;
  int _feedbackSerial = 0;
  String _lastFeedback = '';
  bool _enabled = false;
  bool _pageOpen = false;

  bool get enabled => _enabled;
  bool get visible => _enabled && !_pageOpen && _data != null;
  MeritSaveData? get data => _data;
  String get lastFeedback => _lastFeedback;
  int get feedbackSerial => _feedbackSerial;

  Future<void> initialize() => _initializing ??= _initialize();

  void _accountChanged() {
    _saveDebounce?.cancel();
    _feedbackClear?.cancel();
    _data = null;
    _initializing = null;
    _enabled = false;
    _pageOpen = false;
    _lastFeedback = '';
    notifyListeners();
  }

  Future<void> _initialize() async {
    try {
      final session = ApiSessionScope();
      final scope = await AccountPreferenceScope.capture(session: session);
      final data = await MeritStorageService.load();
      if (!session.current || data.accountScope?.current != true) return;
      _enabled = scope.prefs.getBool(scope.key(_enabledKey)) ?? false;
      _data = data;
      MeritStorageService.refreshDaily(_data!);
      _normalizeSkin(_data!);
      unawaited(MuyuKnockSound.ensureReady());
      notifyListeners();
      unawaited(_refreshFeedbackTexts());
    } on ApiSessionChangedException {
      // 新会话会重新初始化；旧读取不能污染全局状态或产生未处理异常。
    }
  }

  Future<void> _refreshFeedbackTexts() async {
    _feedbackTexts = await loadMeritPrayerFeedbackTexts();
  }

  Future<MeritSaveData> dataForMainPage() async {
    final session = ApiSessionScope();
    await initialize();
    session.ensureCurrent();
    _saveDebounce?.cancel();
    final current = _data ?? await MeritStorageService.load();
    session.ensureCurrent();
    MeritStorageService.refreshDaily(current);
    _normalizeSkin(current);
    _data = current;
    return current;
  }

  void setPageOpen(bool open) {
    if (_pageOpen == open) return;
    _pageOpen = open;
    notifyListeners();
  }

  Future<void> enable({MeritSaveData? data}) async {
    try {
      final session = ApiSessionScope();
      await initialize();
      if (!session.current) return;
      if (data != null) {
        await MeritStorageService.save(data);
        if (!session.current || data.accountScope?.current != true) return;
        _normalizeSkin(data);
        _data = data;
      }
      _enabled = true;
      final scope = await AccountPreferenceScope.capture(session: session);
      await scope.prefs.setBool(scope.key(_enabledKey), true);
      if (!scope.current) return;
      notifyListeners();
    } on ApiSessionChangedException {
      // 旧悬浮开启流程作废。
    }
  }

  Future<void> disable() async {
    try {
      final session = ApiSessionScope();
      _enabled = false;
      _saveDebounce?.cancel();
      _feedbackClear?.cancel();
      _lastFeedback = '';
      notifyListeners();
      if (_data != null) await MeritStorageService.save(_data!);
      if (!session.current) return;
      final scope = await AccountPreferenceScope.capture(session: session);
      await scope.prefs.setBool(scope.key(_enabledKey), false);
    } on ApiSessionChangedException {
      // 不操作新账号的悬浮偏好。
    }
  }

  void knock() {
    final current = _data;
    if (current == null || current.accountScope?.current != true) return;
    MeritStorageService.refreshDaily(current);
    current.totalTaps += 1;
    current.todayTaps += 1;
    _lastFeedback = _feedbackTexts[_feedbackIndex++ % _feedbackTexts.length];
    _feedbackSerial += 1;
    final feedbackSerial = _feedbackSerial;
    _feedbackClear?.cancel();
    _feedbackClear = Timer(const Duration(milliseconds: 1300), () {
      if (_feedbackSerial != feedbackSerial) return;
      _lastFeedback = '';
      notifyListeners();
    });
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 260), () {
      final latest = _data;
      if (latest != null) unawaited(MeritStorageService.save(latest));
    });
    notifyListeners();
  }

  void syncData(MeritSaveData data) {
    if (data.accountScope?.current != true) return;
    _normalizeSkin(data);
    _data = data;
    notifyListeners();
  }

  static void _normalizeSkin(MeritSaveData data) {
    data.activeSkin = 'rebirth_1';
    data.unlockedSkins
      ..clear()
      ..add('rebirth_1');
  }
}

/// 放在 MaterialApp.builder 最外层，让悬浮木鱼在首页、详情页和播间都可见。
class MuyuFloatingOverlayHost extends StatefulWidget {
  const MuyuFloatingOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  State<MuyuFloatingOverlayHost> createState() =>
      _MuyuFloatingOverlayHostState();
}

class _MuyuFloatingOverlayHostState extends State<MuyuFloatingOverlayHost> {
  final _controller = MuyuFloatingController.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            if (_controller.visible)
              Positioned.fill(
                child: _DraggableFloatingMuyu(controller: _controller),
              ),
          ],
        );
      },
    );
  }
}

/// 拖动状态与全局页面隔离，只更新木鱼的位置，避免拖动时重建底层页面。
class _DraggableFloatingMuyu extends StatefulWidget {
  const _DraggableFloatingMuyu({required this.controller});

  final MuyuFloatingController controller;

  @override
  State<_DraggableFloatingMuyu> createState() => _DraggableFloatingMuyuState();
}

class _DraggableFloatingMuyuState extends State<_DraggableFloatingMuyu>
    with SingleTickerProviderStateMixin {
  static const _miniWidth = 112.0;
  static const _miniHeight = 126.0;
  static const _closeHeight = 104.0;

  final ValueNotifier<Offset?> _position = ValueNotifier<Offset?>(null);
  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  bool _dragging = false;
  bool _overCloseTarget = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _snapAnimation;
        if (animation != null) _position.value = animation.value;
      });
  }

  @override
  void dispose() {
    _snapController.dispose();
    _position.dispose();
    super.dispose();
  }

  Offset _clamp(
    Offset value,
    BoxConstraints constraints,
    double bottomSafe,
  ) {
    final maxX =
        (constraints.maxWidth - _miniWidth - 8).clamp(8.0, double.infinity);
    final maxY = (constraints.maxHeight - _miniHeight - bottomSafe - 8)
        .clamp(48.0, double.infinity);
    return Offset(
      value.dx.clamp(8.0, maxX),
      value.dy.clamp(48.0, maxY),
    );
  }

  void _snapToSide(
    Offset from,
    BoxConstraints constraints,
    double bottomSafe,
  ) {
    final right = constraints.maxWidth - _miniWidth - 10;
    final target = _clamp(
      Offset(
        from.dx + _miniWidth / 2 < constraints.maxWidth / 2 ? 10 : right,
        from.dy,
      ),
      constraints,
      bottomSafe,
    );
    _snapAnimation = Tween<Offset>(begin: from, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomSafe = MediaQuery.paddingOf(context).bottom;
        final initial = _clamp(
          Offset(
            constraints.maxWidth - _miniWidth - 16,
            constraints.maxHeight * .55,
          ),
          constraints,
          bottomSafe,
        );
        return Stack(
          children: [
            if (_dragging)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _closeHeight + bottomSafe,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    key: const ValueKey('muyu-close-target'),
                    duration: const Duration(milliseconds: 90),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _overCloseTarget
                            ? const [Color(0xFFF05D55), Color(0xFFD93C3C)]
                            : const [Color(0xFFE96B64), Color(0xFFD94B47)],
                      ),
                    ),
                    padding: EdgeInsets.only(bottom: bottomSafe),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _overCloseTarget
                              ? Icons.delete_forever_outlined
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _overCloseTarget ? '松手关闭悬浮木鱼' : '拖到这里关闭悬浮木鱼',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ValueListenableBuilder<Offset?>(
              valueListenable: _position,
              child: RepaintBoundary(
                child: _FloatingMuyu(controller: widget.controller),
              ),
              builder: (context, rawPosition, child) {
                final position = _clamp(
                  rawPosition ?? initial,
                  constraints,
                  bottomSafe,
                );
                return Positioned(
                  left: position.dx,
                  top: position.dy,
                  width: _miniWidth,
                  height: _miniHeight,
                  child: GestureDetector(
                    key: const ValueKey('floating-muyu-drag-handle'),
                    behavior: HitTestBehavior.translucent,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (_) {
                      _snapController.stop();
                      _position.value = position;
                      setState(() {
                        _dragging = true;
                        _overCloseTarget = false;
                      });
                    },
                    onPanUpdate: (details) {
                      final base = _position.value ?? position;
                      final next = _clamp(
                        base + details.delta,
                        constraints,
                        bottomSafe,
                      );
                      _position.value = next;
                      final overTarget = next.dy + _miniHeight >=
                          constraints.maxHeight - bottomSafe - _closeHeight;
                      if (overTarget != _overCloseTarget) {
                        setState(() => _overCloseTarget = overTarget);
                      }
                    },
                    onPanCancel: () {
                      final current = _position.value ?? position;
                      setState(() {
                        _dragging = false;
                        _overCloseTarget = false;
                      });
                      _snapToSide(current, constraints, bottomSafe);
                    },
                    onPanEnd: (_) {
                      final current = _position.value ?? position;
                      final shouldClose = _overCloseTarget;
                      setState(() {
                        _dragging = false;
                        _overCloseTarget = false;
                      });
                      if (shouldClose) {
                        unawaited(widget.controller.disable());
                      } else {
                        _snapToSide(current, constraints, bottomSafe);
                      }
                    },
                    child: child,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _FloatingMuyu extends StatelessWidget {
  const _FloatingMuyu({required this.controller});

  final MuyuFloatingController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.data!;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 112,
        height: 126,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: controller.lastFeedback.isEmpty
                    ? const SizedBox(height: 28)
                    : Container(
                        key: ValueKey(controller.feedbackSerial),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x180F5960),
                              blurRadius: 9,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          controller.lastFeedback,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF39747A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 98,
              child: Semantics(
                key: const ValueKey('floating-muyu-visual'),
                label: '悬浮木鱼，轻触敲击，拖动调整位置',
                button: true,
                child: Center(
                  child: MuyuKnockWidget(
                    size: 70,
                    fishAsset: ImageAssets.muyuCloudWave,
                    stickAsset: ImageAssets.muyuCloudWaveStick,
                    soundEnabled: data.soundEnabled,
                    soundVolume: data.soundVolume,
                    vibrationEnabled: data.vibrationEnabled,
                    softHaptics: true,
                    onKnock: controller.knock,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
