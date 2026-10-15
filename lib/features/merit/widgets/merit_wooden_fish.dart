import 'package:flutter/material.dart';
import 'package:xuanyu/app/common/values/images.dart';
import 'package:xuanyu/features/merit/widgets/muyu_knock_widget.dart';

/// 敲木鱼组件（兼容旧调用；动画见 [MuyuKnockWidget]）。
class MeritWoodenFish extends StatefulWidget {
  const MeritWoodenFish({
    super.key,
    required this.onTap,
    this.size = 180,
    this.imageAsset,
    this.stickAsset,
    this.soundEnabled = true,
    this.soundVolume = 0.52,
    this.vibrationEnabled = true,
    this.softHaptics = true,
  });

  final VoidCallback onTap;
  final double size;
  final String? imageAsset;
  final String? stickAsset;
  final bool soundEnabled;
  final double soundVolume;
  final bool vibrationEnabled;
  final bool softHaptics;

  @override
  State<MeritWoodenFish> createState() => MeritWoodenFishState();
}

class MeritWoodenFishState extends State<MeritWoodenFish> {
  final GlobalKey<MuyuKnockWidgetState> _knockKey =
      GlobalKey<MuyuKnockWidgetState>();

  void playTap() => _knockKey.currentState?.playKnock();

  @override
  Widget build(BuildContext context) {
    return MuyuKnockWidget(
      key: _knockKey,
      onKnock: widget.onTap,
      size: widget.size,
      fishAsset: widget.imageAsset ?? ImageAssets.muyuCloudWave,
      stickAsset: widget.stickAsset ?? ImageAssets.muyuCloudWaveStick,
      soundEnabled: widget.soundEnabled,
      soundVolume: widget.soundVolume,
      vibrationEnabled: widget.vibrationEnabled,
      softHaptics: widget.softHaptics,
    );
  }
}
