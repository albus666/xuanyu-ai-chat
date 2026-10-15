import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

class MeritFloatingText extends StatefulWidget {
  const MeritFloatingText({
    super.key,
    required this.text,
    required this.rarity,
    this.onComplete,
  });

  final String text;
  final String rarity;
  final VoidCallback? onComplete;

  @override
  State<MeritFloatingText> createState() => _MeritFloatingTextState();
}

class _MeritFloatingTextState extends State<MeritFloatingText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..forward()
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onComplete?.call();
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.rarity) {
      case 'epic':
        return MeritColors.epic;
      case 'rare':
        return MeritColors.rare;
      default:
        return MeritColors.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1)),
      ),
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.15)).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: MeritColors.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.rarity == 'epic'
                  ? MeritColors.epic
                  : widget.rarity == 'rare'
                      ? MeritColors.rare
                      : MeritColors.card,
            ),
          ),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _color,
              fontSize: 14.sp,
              fontWeight: widget.rarity != 'common' ? FontWeight.w700 : FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class MeritFloatingCoin extends StatefulWidget {
  const MeritFloatingCoin({super.key, required this.amount});

  final int amount;

  @override
  State<MeritFloatingCoin> createState() => _MeritFloatingCoinState();
}

class _MeritFloatingCoinState extends State<MeritFloatingCoin> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(_ctrl),
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.25)).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
        ),
        child: Text(
          '+${widget.amount}',
          style: TextStyle(
            color: MeritColors.gold,
            fontSize: 16.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class MeritComboSettlementToast extends StatefulWidget {
  const MeritComboSettlementToast({
    super.key,
    required this.combo,
    required this.coins,
    required this.onDone,
  });

  final int combo;
  final int coins;
  final VoidCallback onDone;

  @override
  State<MeritComboSettlementToast> createState() => _MeritComboSettlementToastState();
}

class _MeritComboSettlementToastState extends State<MeritComboSettlementToast>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();
    _timer = Timer(const Duration(milliseconds: 1800), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 不挡点击的轻提示
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: FadeTransition(
            opacity: _ctrl,
            child: Container(
              margin: EdgeInsets.only(top: 12.h, left: 24.w, right: 24.w),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: MeritColors.card.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MeritColors.gold.withValues(alpha: 0.5)),
              ),
              child: Text(
                '连击 ${widget.combo} 下 · +${widget.coins} 负功德币',
                textAlign: TextAlign.center,
                style: TextStyle(color: MeritColors.textPrimary, fontSize: 13.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧待领取事件图标
class MeritPendingRewardChip extends StatelessWidget {
  const MeritPendingRewardChip({
    super.key,
    required this.type,
    required this.onTap,
  });

  final MeritEventType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _meta(type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56.w,
          height: 56.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MeritColors.card,
            border: Border.all(color: meta.color, width: 2),
            boxShadow: [
              BoxShadow(color: meta.color.withValues(alpha: 0.35), blurRadius: 10),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(meta.icon, color: meta.color, size: 22),
              Text(meta.label, style: TextStyle(color: meta.color, fontSize: 9.sp, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  static ({IconData icon, String label, Color color}) _meta(MeritEventType type) {
    switch (type) {
      case MeritEventType.fortuneGod:
        return (icon: Icons.redeem, label: '红包', color: const Color(0xFFEF4444));
      case MeritEventType.buddhaPass:
        return (icon: Icons.self_improvement, label: '佛祖', color: MeritColors.gold);
      case MeritEventType.bossCheck:
        return (icon: Icons.warning_amber_rounded, label: '查岗', color: const Color(0xFFF59E0B));
      case MeritEventType.fishMood:
        return (icon: Icons.spa, label: '哄鱼', color: const Color(0xFF34D399));
      case MeritEventType.karmaBacklash:
        return (icon: Icons.bolt, label: '业力', color: MeritColors.epic);
    }
  }
}
