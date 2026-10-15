import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xuanyu/app/common/values/images.dart';
import 'package:xuanyu/features/merit/services/muyu_knock_sound.dart';

/// 通用木鱼敲击：木鱼本体 + 木锤分离素材。
///
/// 音效/震动挂在同一套 [_strike] 动画上：控制器进度越过击中点时触发一次。
class MuyuKnockWidget extends StatefulWidget {
  const MuyuKnockWidget({
    super.key,
    required this.onKnock,
    this.fishAsset,
    this.stickAsset,
    this.size = 180,
    this.soundEnabled = true,
    this.soundVolume = 0.52,
    this.vibrationEnabled = true,
    this.softHaptics = true,
  });

  final VoidCallback onKnock;
  final String? fishAsset;
  final String? stickAsset;
  final double size;
  final bool soundEnabled;
  final double soundVolume;
  final bool vibrationEnabled;
  final bool softHaptics;

  @override
  State<MuyuKnockWidget> createState() => MuyuKnockWidgetState();
}

class MuyuKnockWidgetState extends State<MuyuKnockWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _strike;
  late final Animation<double> _angle;
  late final Animation<Offset> _offset;
  late final Animation<double> _fishPulse;

  DateTime? _lastTapAt;
  double _prevStrike = 0;
  bool _hitFxFired = false;

  /// 与下落 TweenSequence 权重 40% 对齐 = 锤头触鱼瞬间
  static const _hitAt = 0.40;

  static const _readyAngle = 28 * math.pi / 180;
  static const _hitAngle = 6 * math.pi / 180;
  static const _readyOffset = Offset(0, 0);
  static const _hitOffset = Offset(-14, 16);

  static const _defaultStrikeMs = 150;
  static const _minStrikeMs = 55;
  static const _maxStrikeMs = 150;

  @override
  void initState() {
    super.initState();
    _strike = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _defaultStrikeMs),
    )..addListener(_onStrikeFrame);

    _angle = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: _readyAngle, end: _hitAngle)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _hitAngle, end: _readyAngle)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
    ]).animate(_strike);

    _offset = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: _readyOffset, end: _hitOffset)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _hitOffset, end: _readyOffset)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
    ]).animate(_strike);

    _fishPulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.90), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.90, end: 1.0), weight: 60),
    ]).animate(_strike);

    _strike.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 停在终点即可，下次 forward(from:0) 会复位；避免强制写 0 干扰击中检测
        _hitFxFired = false;
        _prevStrike = 1;
      }
    });

    unawaited(MuyuKnockSound.ensureReady());
  }

  /// 动画每一帧：进度跨过击中点，或木鱼缩到最扁时触发。
  void _onStrikeFrame() {
    final v = _strike.value;
    final crossed = _prevStrike < _hitAt && v >= _hitAt;
    final crushed = _fishPulse.value <= 0.905 && _prevStrike < _hitAt;
    if (!_hitFxFired && (crossed || crushed)) {
      _hitFxFired = true;
      _fireHitFx();
    }
    _prevStrike = v;
  }

  void _fireHitFx() {
    if (widget.vibrationEnabled) {
      if (widget.softHaptics) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    }
    if (widget.soundEnabled) {
      MuyuKnockSound.playHit(volume: widget.soundVolume);
    }
  }

  @override
  void dispose() {
    _strike.removeListener(_onStrikeFrame);
    _strike.dispose();
    super.dispose();
  }

  void playKnock() => _restartStrike();

  void _restartStrike() {
    final now = DateTime.now();
    if (_lastTapAt != null) {
      final gapMs = now.difference(_lastTapAt!).inMilliseconds;
      _strike.duration = Duration(
        milliseconds: gapMs.clamp(_minStrikeMs, _maxStrikeMs),
      );
    } else {
      _strike.duration = const Duration(milliseconds: _defaultStrikeMs);
    }
    _lastTapAt = now;
    _hitFxFired = false;
    _prevStrike = 0;
    _strike.forward(from: 0);
  }

  bool _isNetwork(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  Widget _img(String path, {BoxFit fit = BoxFit.contain}) {
    if (_isNetwork(path)) {
      return Image.network(
        path,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Image.asset(ImageAssets.muyuCloudWave, fit: fit),
      );
    }
    return Image.asset(
      path,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Icon(
        Icons.spa_outlined,
        size: widget.size * 0.5,
        color: Colors.amber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fish = widget.fishAsset ?? ImageAssets.muyuCloudWave;
    final stick = widget.stickAsset ?? ImageAssets.muyuCloudWaveStick;
    final canvas = widget.size;
    final fishSize = canvas * 0.68;
    final width = canvas * 1.5;
    final height = canvas * 1.28;
    final fishLeft = (width - fishSize) / 2;
    final fishTop = height * 0.34;

    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _restartStrike();
          widget.onKnock();
        },
        child: AnimatedBuilder(
          animation: _strike,
          builder: (context, _) {
            final pulse = _fishPulse.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: fishLeft,
                  top: fishTop,
                  width: fishSize,
                  height: fishSize,
                  child: Transform.scale(
                    scale: pulse,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(0, (1 - pulse) * fishSize * 0.08),
                      child: _img(fish),
                    ),
                  ),
                ),
                Positioned(
                  left: width * 0.46,
                  top: fishTop - fishSize * 0.04,
                  width: fishSize * 0.88,
                  height: fishSize * 0.25,
                  child: Transform.translate(
                    offset: _offset.value,
                    child: Transform.rotate(
                      angle: _angle.value,
                      alignment: Alignment.centerRight,
                      child: _img(stick),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
