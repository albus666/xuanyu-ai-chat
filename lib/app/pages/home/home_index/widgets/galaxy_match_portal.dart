import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Configurable revolution with independent starlight.
/// Sampling is deterministic and supports out-of-order inspection in tests.
@immutable
class GalaxyMotionSample {
  const GalaxyMotionSample({
    required this.angleRadians,
    required this.starOpacities,
  });

  static const revolutionSeconds = 420.0;

  static double normalizePeriod(double value) =>
      value.isFinite && value >= 10 && value <= 3600
          ? value
          : revolutionSeconds;
  final double angleRadians;
  final List<double> starOpacities;

  static GalaxyMotionSample sample(double elapsedSeconds,
      {double periodSeconds = revolutionSeconds}) {
    final time = elapsedSeconds.isFinite ? math.max(0.0, elapsedSeconds) : 0.0;
    return GalaxyMotionSample(
      angleRadians: time * math.pi * 2 / normalizePeriod(periodSeconds),
      starOpacities: List.generate(12, (index) {
        final seed = 7103 + index * 911;
        final duration = 18 + _random(seed, 91) * 29;
        final phase = time / duration + _random(seed, 90);
        final segment = phase.floor();
        final from = .10 + _random(seed, segment) * .40;
        final to = .10 + _random(seed, segment + 1) * .40;
        return from + (to - from) * _smooth(phase - segment);
      }, growable: false),
    );
  }
}

double _smooth(double value) {
  final x = value.clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

double _random(int seed, int index) {
  var x = (seed ^ ((index + 1) * 0x9e3779b1)) & 0xffffffff;
  x = ((x ^ (x >> 16)) * 0x7feb352d) & 0xffffffff;
  x = ((x ^ (x >> 15)) * 0x846ca68b) & 0xffffffff;
  return ((x ^ (x >> 16)) & 0xffffffff) / 4294967296;
}

/// Native, independently tappable matching entries; no network or video player.
class GalaxyMatchPortal extends StatefulWidget {
  const GalaxyMatchPortal({
    super.key,
    required this.onDestinyTap,
    required this.onVoiceTap,
    this.active = true,
    this.revolutionSeconds = GalaxyMotionSample.revolutionSeconds,
  });
  final VoidCallback onDestinyTap;
  final VoidCallback onVoiceTap;
  final bool active;
  final double revolutionSeconds;

  @override
  State<GalaxyMatchPortal> createState() => GalaxyMatchPortalState();
}

class GalaxyMatchPortalState extends State<GalaxyMatchPortal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final _seconds = ValueNotifier<double>(0);
  final _angle = ValueNotifier<double>(0);
  double _activeAngle = 0;
  Duration _lastTick = Duration.zero;
  double _activeSeconds = 0;
  bool _tickerEnabled = false;
  bool _reduceMotion = false;
  bool _resumed = true;

  @visibleForTesting
  double get debugElapsedSeconds => _seconds.value;
  @visibleForTesting
  double get debugAngleRadians => _angle.value;
  @visibleForTesting
  bool get debugIsAnimating => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    final dt = delta.inMicroseconds / Duration.microsecondsPerSecond;
    _activeSeconds += dt;
    _activeAngle += dt *
        math.pi *
        2 /
        GalaxyMotionSample.normalizePeriod(widget.revolutionSeconds);
    // Only paint layers receive this notification. Copy and hit areas stay put.
    if (_activeSeconds - _seconds.value >= 1 / 30) {
      _seconds.value = _activeSeconds;
      _angle.value = _activeAngle;
    }
  }

  void _sync() {
    final run = widget.active && _tickerEnabled && !_reduceMotion && _resumed;
    if (run && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      _lastTick = Duration.zero;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep compatibility with the release builder’s older Flutter SDK.
    // ignore: deprecated_member_use
    _tickerEnabled = TickerMode.of(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant GalaxyMatchPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _seconds.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 369 / 170,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final side = width * .44;
        final titleSize = (width * .049).clamp(16.0, 24.0);
        final subtitleSize = (width * .028).clamp(10.0, 15.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0xff634880),
                    Color(0xff186b9c),
                    Color(0xff25569a),
                  ]),
                ),
              ),
              Image.asset(
                'images/home_match_cosmos_background.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('galaxy-stars-layer'),
                  painter: _StarlightPainter(_seconds),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: height * .36,
                bottom: 0,
                child: IgnorePointer(
                  child: ClipRect(
                    key: const ValueKey('galaxy-art-region'),
                    child: OverflowBox(
                      minWidth: side,
                      maxWidth: side,
                      minHeight: side,
                      maxHeight: side,
                      child: RepaintBoundary(
                        child: Flow(
                          key: const ValueKey('galaxy-motion-layer'),
                          clipBehavior: Clip.none,
                          delegate: _GalaxyFlow(_angle),
                          children: [
                            Image.asset(
                              'images/home_match_galaxy_layer.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(children: [
                _entry(
                  key: const ValueKey('galaxy-destiny-entry'),
                  title: '缘分匹配',
                  subtitle: '遇见与你同频的人',
                  titleSize: titleSize,
                  subtitleSize: subtitleSize,
                  padding: EdgeInsets.fromLTRB(
                      width * .05, height * .07, width * .03, 0),
                  copyHeight: height * .26,
                  onTap: widget.onDestinyTap,
                ),
                _entry(
                  key: const ValueKey('galaxy-voice-entry'),
                  title: '语音匹配',
                  subtitle: '让声音替你先认识对方',
                  titleSize: titleSize,
                  subtitleSize: subtitleSize,
                  padding: EdgeInsets.fromLTRB(
                      width * .03, height * .07, width * .05, 0),
                  copyHeight: height * .26,
                  alignRight: true,
                  onTap: widget.onVoiceTap,
                ),
              ]),
            ],
          ),
        );
      }),
    );
  }

  Widget _entry({
    required Key key,
    required String title,
    required String subtitle,
    required double titleSize,
    required double subtitleSize,
    required EdgeInsets padding,
    required double copyHeight,
    bool alignRight = false,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: Semantics(
          button: true,
          label: '$title，$subtitle',
          onTap: onTap,
          child: ExcludeSemantics(
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: SizedBox.expand(
                child: Padding(
                  padding: padding,
                  child: Align(
                    alignment:
                        alignRight ? Alignment.topRight : Alignment.topLeft,
                    child: SizedBox(
                      height: copyHeight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment:
                            alignRight ? Alignment.topRight : Alignment.topLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: alignRight
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                  shadows: const [
                                    Shadow(
                                        color: Color(0x66152443),
                                        blurRadius: 6),
                                  ],
                                )),
                            const SizedBox(height: 4),
                            Text(subtitle,
                                maxLines: 1,
                                style: TextStyle(
                                  color: const Color(0xffedf3ff),
                                  fontSize: subtitleSize,
                                  height: 1.5,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _GalaxyFlow extends FlowDelegate {
  _GalaxyFlow(this.angle) : super(repaint: angle);
  final ValueListenable<double> angle;

  @override
  void paintChildren(FlowPaintingContext context) {
    final center = context.size.center(Offset.zero);
    final transform = Matrix4.identity()
      // Older release SDKs use the original vector_math transform methods.
      // ignore: deprecated_member_use
      ..translate(center.dx, center.dy)
      ..rotateZ(-26 * math.pi / 180)
      // ignore: deprecated_member_use
      ..scale(1.0, .60)
      ..rotateZ(angle.value)
      // ignore: deprecated_member_use
      ..translate(-center.dx, -center.dy);
    context.paintChild(0, transform: transform);
  }

  @override
  bool shouldRepaint(covariant _GalaxyFlow oldDelegate) =>
      angle != oldDelegate.angle;
}

class _StarlightPainter extends CustomPainter {
  _StarlightPainter(this.seconds) : super(repaint: seconds);
  final ValueListenable<double> seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final sample = GalaxyMotionSample.sample(seconds.value);
    final paint = Paint();
    for (var i = 0; i < 12; i++) {
      final seed = 7103 + i * 911;
      final point = Offset(
        size.width * (.07 + _random(seed, 80) * .86),
        size.height * (.12 + _random(seed, 81) * .76),
      );
      paint.color =
          const Color(0xffe4f6ff).withValues(alpha: sample.starOpacities[i]);
      canvas.drawCircle(point, .65, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarlightPainter oldDelegate) =>
      seconds != oldDelegate.seconds;
}
