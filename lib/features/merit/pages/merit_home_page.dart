import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/utils/nav_utils.dart';
import 'package:xuanyu/core/theme/app_colors.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/shared/widgets/account_session_guard.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/pages/merit_settings_page.dart';
import 'package:xuanyu/features/merit/services/merit_auto_knock.dart';
import 'package:xuanyu/features/merit/services/merit_prayer_feedback_service.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';
import 'package:xuanyu/features/merit/services/muyu_knock_sound.dart';
import 'package:xuanyu/features/merit/models/merit_skins.dart';
import 'package:xuanyu/features/merit/widgets/merit_wooden_fish.dart';
import 'package:xuanyu/features/merit/widgets/muyu_floating_overlay.dart';

/// 敲木鱼 —— 以韵律寄托心念
/// 无等级、无轮回、无 COMBO、无负功德币。
/// 支持手动敲击与自动敲击两种模式。
class MeritHomePage extends StatefulWidget {
  const MeritHomePage({super.key});

  @override
  State<MeritHomePage> createState() => _MeritHomePageState();
}

class _MeritHomePageState extends State<MeritHomePage>
    with AccountSessionGuard<MeritHomePage> {
  final MuyuFloatingController _floatingController =
      MuyuFloatingController.instance;
  MeritSaveData? _data;
  List<String> _prayerFeedbackTexts = meritPrayerFeedbackTexts;
  final GlobalKey<MeritWoodenFishState> _fishKey = GlobalKey();

  bool _autoKnock = false;
  Timer? _autoTimer;
  Timer? _saveDebounce;
  final List<_PrayerFloatEntry> _floatingTexts = <_PrayerFloatEntry>[];
  int _nextFloatingId = 0;
  int _nextPrayerText = 0;

  @override
  void initState() {
    super.initState();
    _floatingController.setPageOpen(true);
    _init();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _saveDebounce?.cancel();
    final data = _data;
    if (data != null) {
      _floatingController.syncData(data);
      unawaited(MeritStorageService.save(data));
    }
    _floatingController.setPageOpen(false);
    super.dispose();
  }

  Future<void> _init() async {
    MeritSaveData data;
    try {
      data = await _floatingController.dataForMainPage();
    } on ApiSessionChangedException {
      return;
    }
    if (!mounted || !accountSession.current) return;
    MeritStorageService.refreshDaily(data);
    data.activeSkin = MeritSkinDef.defaults.first.id;
    data.unlockedSkins
      ..clear()
      ..add(data.activeSkin);
    if (!mounted) return;
    setState(() {
      _data = data;
    });
    unawaited(MuyuKnockSound.ensureReady());
    unawaited(_loadPrayerFeedbackTexts());
  }

  Future<void> _loadPrayerFeedbackTexts() async {
    // 文案远程加载不阻塞木鱼页面，网络异常时用户仍可立即敲击。
    final configuredTexts = await loadMeritPrayerFeedbackTexts();
    if (!mounted) return;
    setState(() {
      _prayerFeedbackTexts = configuredTexts;
      _nextPrayerText = 0;
    });
  }

  void _onTap() {
    if (_data == null || !accountSession.current) return;
    final id = _nextFloatingId++;
    final entry = _PrayerFloatEntry(
      id: id,
      text:
          _prayerFeedbackTexts[_nextPrayerText++ % _prayerFeedbackTexts.length],
      lane: id % 3,
    );
    setState(() {
      _data!.totalTaps += 1;
      _data!.todayTaps += 1;
      _floatingTexts.add(entry);
      if (_floatingTexts.length > 3) {
        _floatingTexts.removeAt(0);
      }
    });
    _saveDebounced();
  }

  void _removeFloatingText(int id) {
    if (!mounted) return;
    setState(() => _floatingTexts.removeWhere((entry) => entry.id == id));
  }

  void _saveDebounced() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_data != null) MeritStorageService.save(_data!);
    });
  }

  void _toggleAutoKnock(bool on) {
    setState(() => _autoKnock = on);
    _autoTimer?.cancel();
    if (on) {
      _startAutoKnock();
    }
  }

  void _startAutoKnock() {
    _performAutoKnock();
    _autoTimer = Timer.periodic(meritAutoKnockIntervalFor(_data!), (_) {
      if (!_autoKnock || !mounted || !accountSession.current) {
        _autoTimer?.cancel();
        return;
      }
      _performAutoKnock();
    });
  }

  void _performAutoKnock() {
    if (!_autoKnock || !mounted) return;
    _fishKey.currentState?.playTap();
    _onTap();
  }

  void _performManualKnock() {
    if (!mounted || _data == null) return;
    _fishKey.currentState?.playTap();
    _onTap();
  }

  void _setAutoSpeed(double speed) {
    if (!accountSession.current) return;
    final data = _data;
    if (data == null) return;
    setState(() => setMeritKnocksPerSecond(data, speed));
    _saveDebounced();
    if (_autoKnock) {
      _autoTimer?.cancel();
      _autoTimer = Timer.periodic(meritAutoKnockIntervalFor(data), (_) {
        if (!_autoKnock || !mounted || !accountSession.current) {
          _autoTimer?.cancel();
          return;
        }
        _performAutoKnock();
      });
    }
  }

  Future<void> _toggleFloatingMode() async {
    if (!accountSession.current) return;
    final data = _data;
    if (data == null) return;
    if (_floatingController.enabled) {
      await _floatingController.disable();
      if (mounted) setState(() {});
      return;
    }
    _toggleAutoKnock(false);
    _floatingController.syncData(data);
    await _floatingController.enable(data: data);
    if (!mounted || !accountSession.current) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('悬浮木鱼已开启，可拖动位置，轻触即可敲击')),
    );
    Navigator.of(context).maybePop();
  }

  Future<void> _save() async {
    if (!accountSession.current) return;
    if (_data != null) {
      _floatingController.syncData(_data!);
      await MeritStorageService.save(_data!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    final data = _data;
    if (data == null) {
      return const Scaffold(
        backgroundColor: MeritColors.bg,
        body: Center(
          child: CircularProgressIndicator(color: MeritColors.gold),
        ),
      );
    }

    return Scaffold(
      backgroundColor: MeritColors.bg,
      appBar: AppBar(
        backgroundColor: MeritColors.bg.withValues(alpha: 0.98),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: MeritColors.textPrimary, size: 18),
          onPressed: NavUtils.goBack,
        ),
        title: const Text(
          '敲木鱼',
          style: TextStyle(
            color: MeritColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: MeritColors.textSecondary),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MeritSettingsPage(
                    data: data,
                    onChanged: _save,
                  ),
                ),
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: MeritColors.bodyGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: '敲击木鱼区域',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _performManualKnock,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 320.w,
                          height: 270.w,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: <Widget>[
                              IgnorePointer(
                                child: MeritWoodenFish(
                                  key: _fishKey,
                                  onTap: _onTap,
                                  size: 210.w,
                                  imageAsset: MeritSkinDef.assetForSave(data),
                                  stickAsset: MeritSkinDef.stickForSave(data),
                                  soundEnabled: data.soundEnabled,
                                  soundVolume: data.soundVolume,
                                  vibrationEnabled: data.vibrationEnabled,
                                  softHaptics: true,
                                ),
                              ),
                              for (final entry in _floatingTexts)
                                Positioned.fill(
                                  key: ValueKey<int>(entry.id),
                                  child: IgnorePointer(
                                    child: Align(
                                      alignment: switch (entry.lane) {
                                        0 => const Alignment(-0.58, -0.78),
                                        1 => const Alignment(0, -0.62),
                                        _ => const Alignment(0.58, -0.76),
                                      },
                                      child: _PrayerFloatingText(
                                        text: entry.text,
                                        lane: entry.lane,
                                        onComplete: () =>
                                            _removeFloatingText(entry.id),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20.h),
                        Text(
                          data.todayTaps > 0
                              ? '今日已敲 ${data.todayTaps} 次'
                              : '轻触木鱼或周围空白，安放心念',
                          style: TextStyle(
                            color: MeritColors.textSecondary,
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 底部控制栏
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 7.w,
                        runSpacing: 8.h,
                        children: [
                          _controlChip(
                            icon: _autoKnock
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            label: _autoKnock ? '停止' : '自动敲击',
                            active: _autoKnock,
                            onTap: () => _toggleAutoKnock(!_autoKnock),
                          ),
                          _controlChip(
                            icon: data.soundEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            label: '音效',
                            active: data.soundEnabled,
                            onTap: () {
                              data.soundEnabled = !data.soundEnabled;
                              _save();
                              setState(() {});
                            },
                          ),
                          _controlChip(
                            icon: Icons.vibration_rounded,
                            label: '震动',
                            active: data.vibrationEnabled,
                            onTap: () {
                              data.vibrationEnabled = !data.vibrationEnabled;
                              _save();
                              setState(() {});
                            },
                          ),
                          _controlChip(
                            icon: Icons.picture_in_picture_alt_rounded,
                            label:
                                _floatingController.enabled ? '关闭悬浮' : '悬浮木鱼',
                            active: _floatingController.enabled,
                            onTap: _toggleFloatingMode,
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Row(
                        children: [
                          Text(
                            '自动速度',
                            style: TextStyle(
                              color: MeritColors.textSecondary,
                              fontSize: 12.sp,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: meritKnocksPerSecond(data).clamp(1.5, 6.0),
                              min: 1.5,
                              max: 6,
                              divisions: 18,
                              activeColor: MeritColors.gold,
                              inactiveColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              onChanged: _setAutoSpeed,
                            ),
                          ),
                          SizedBox(
                            width: 55.w,
                            child: Text(
                              '${meritKnocksPerSecond(data).toStringAsFixed(1)}次/秒',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: MeritColors.gold,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10.h),
                      const CulturalReferenceNotice(
                        padding: EdgeInsets.zero,
                        color: MeritColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: active
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? MeritColors.gold : MeritColors.textSecondary,
            ),
            SizedBox(width: 5.w),
            Text(
              label,
              style: TextStyle(
                color: active ? MeritColors.gold : MeritColors.textSecondary,
                fontSize: 13.sp,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrayerFloatEntry {
  const _PrayerFloatEntry({
    required this.id,
    required this.text,
    required this.lane,
  });

  final int id;
  final String text;
  final int lane;
}

class _PrayerFloatingText extends StatefulWidget {
  const _PrayerFloatingText({
    required this.text,
    required this.lane,
    required this.onComplete,
  });

  final String text;
  final int lane;
  final VoidCallback onComplete;

  @override
  State<_PrayerFloatingText> createState() => _PrayerFloatingTextState();
}

class _PrayerFloatingTextState extends State<_PrayerFloatingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )
      ..forward()
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.lane) {
        0 => AppColors.primary,
        1 => AppColors.accentGold,
        _ => const Color(0xFFE07A91),
      };

  @override
  Widget build(BuildContext context) {
    final fade = TweenSequence<double>(
      <TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 0, end: 1),
          weight: 18,
        ),
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(1),
          weight: 42,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1, end: 0),
          weight: 40,
        ),
      ],
    ).animate(_controller);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: const Offset(0, -0.28),
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.03).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _color.withValues(alpha: 0.2)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _color.withValues(alpha: 0.12),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(
              widget.text,
              style: TextStyle(
                color: _color,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
