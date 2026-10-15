import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/settings/app_settings_store.dart';
import '../../core/theme/app_colors.dart';
import 'virtual_gift_media.dart';

/// Queue owners advance only from [onCompleted], never from a send-time timer.
class VirtualGiftEffect extends StatefulWidget {
  const VirtualGiftEffect({
    super.key,
    required this.payload,
    this.onCompleted,
    this.preview = false,
  });

  final Map<String, dynamic> payload;
  final VoidCallback? onCompleted;
  final bool preview;

  static const videoPrepareTimeout = Duration(seconds: 5);
  static const videoStallTimeout = Duration(seconds: 4);
  static const reducedMotionDuration = Duration(milliseconds: 1700);

  @override
  State<VirtualGiftEffect> createState() => _VirtualGiftEffectState();
}

class _VirtualGiftEffectState extends State<VirtualGiftEffect>
    with TickerProviderStateMixin {
  late final AnimationController _animation;
  late final AnimationController _exit;
  VideoPlayerController? _video;
  Timer? _staticTimer;
  Timer? _prepareTimer;
  Timer? _stallTimer;
  Timer? _videoWatchdog;
  Duration _lastPosition = Duration.zero;
  bool? _reduced;
  bool _preparing = false;
  bool _videoReady = false;
  bool _ended = false;
  bool _closing = false;
  int _run = 0;
  int _played = 0;
  int get _quantity =>
      widget.preview || widget.payload['_messageType'] == 'entry'
          ? 1
          : (int.tryParse('${widget.payload['quantity'] ?? 1}') ?? 1)
              .clamp(1, 999999);

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _complete();
      });
    _exit = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _complete();
      });
    AppSettingsStore.instance.addListener(_settingsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyMotionPolicy();
  }

  @override
  void didUpdateWidget(covariant VirtualGiftEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.payload, widget.payload) ||
        oldWidget.preview != widget.preview) {
      _ended = false;
      _played = 0;
      _restart();
    }
  }

  void _settingsChanged() {
    if (!mounted) return;
    if (_applyMotionPolicy()) setState(() {});
  }

  bool _applyMotionPolicy() {
    final reduced = (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
        AppSettingsStore.instance.boolValue('reduceMotion');
    if (_reduced == reduced) return false;
    _reduced = reduced;
    if (!_ended) _restart();
    return true;
  }

  bool _current(int run) => mounted && !_ended && run == _run;

  void _restart() {
    final run = ++_run;
    _stopPlayback();
    _animation.reset();
    _exit.reset();
    _closing = false;
    _videoReady = false;
    _preparing = false;
    if (_reduced == true) {
      // No video, animated image, spinner, painter or active ticker here.
      _staticTimer = Timer(VirtualGiftEffect.reducedMotionDuration, _complete);
      return;
    }
    final videoUrl = virtualGiftVideoUrl(widget.payload);
    final uri = Uri.tryParse(videoUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      _startArtwork(run);
      return;
    }
    _preparing = true;
    unawaited(_prepareVideo(uri, run));
  }

  Future<void> _prepareVideo(Uri uri, int run) async {
    final video = VideoPlayerController.networkUrl(
      uri,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = video;
    video.addListener(_videoChanged);
    _prepareTimer =
        Timer(VirtualGiftEffect.videoPrepareTimeout, () => _fallback(run));
    try {
      await (() async {
        // Set the initial value before initialization also applies platform
        // defaults, so native playback never briefly inherits full volume.
        await video.setVolume(0);
        if (!_current(run) || !identical(_video, video)) return;
        await video.initialize();
        if (!_current(run) || !identical(_video, video)) return;
        if (video.value.duration <= Duration.zero || video.value.size.isEmpty) {
          throw StateError('Gift video has no usable timeline');
        }
        await video.setLooping(false);
        if (!_current(run) || !identical(_video, video)) return;
        await video.setVolume(0);
        if (!_current(run) || !identical(_video, video)) return;
        await video.play();
      })();
      if (!_current(run) || !identical(_video, video)) return;
      _prepareTimer?.cancel();
      _prepareTimer = null;
      setState(() {
        _preparing = false;
        _videoReady = true;
        _lastPosition = video.value.position;
      });
      _watchForStall(run);
      // A secondary guard for corrupt plugins/timelines; it starts AFTER ready,
      // and never removes a normally playing video based on catalog duration.
      _videoWatchdog = Timer(video.value.duration + const Duration(seconds: 8),
          () => _fallback(run));
      _videoChanged();
    } catch (_) {
      if (_current(run) && identical(_video, video)) _fallback(run);
    }
  }

  void _videoChanged() {
    final video = _video;
    if (!mounted || _ended || _closing || video == null) return;
    if (video.value.hasError) {
      _fallback(_run);
      return;
    }
    if (!_videoReady) return;
    final value = video.value;
    if (value.duration > Duration.zero && value.position >= value.duration) {
      _finishVideo();
    } else if (value.position > _lastPosition) {
      _lastPosition = value.position;
      _watchForStall(_run);
    }
  }

  void _finishVideo() {
    if (_closing || _ended) return;
    _closing = true;
    _stallTimer?.cancel();
    _videoWatchdog?.cancel();
    // Keep the final frame alive while fading, then release its player once.
    final video = _video;
    if (video != null) unawaited(video.pause().catchError((Object _) {}));
    _exit.forward(from: 0);
  }

  void _watchForStall(int run) {
    _stallTimer?.cancel();
    _stallTimer =
        Timer(VirtualGiftEffect.videoStallTimeout, () => _fallback(run));
  }

  void _fallback(int run) {
    if (!_current(run)) return;
    _releaseVideo();
    setState(() {
      _preparing = false;
      _videoReady = false;
      _startArtwork(run);
    });
  }

  void _startArtwork(int run) {
    if (!_current(run)) return;
    _animation.duration =
        Duration(milliseconds: virtualGiftEffectDuration(widget.payload));
    _animation.forward(from: 0);
  }

  void _releaseVideo() {
    _prepareTimer?.cancel();
    _prepareTimer = null;
    _stallTimer?.cancel();
    _videoWatchdog?.cancel();
    _stallTimer = null;
    _videoWatchdog = null;
    final video = _video;
    _video = null;
    if (video != null) {
      video.removeListener(_videoChanged);
      unawaited(video.dispose().catchError((Object _) {}));
    }
  }

  void _stopPlayback() {
    _staticTimer?.cancel();
    _staticTimer = null;
    _animation.stop();
    _exit.stop();
    _releaseVideo();
  }

  void _complete({bool skip = false}) {
    if (!mounted || _ended) return;
    if (!skip && ++_played < _quantity) {
      setState(_restart);
      return;
    }
    _ended = true;
    ++_run;
    _stopPlayback();
    setState(() {});
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    ++_run;
    AppSettingsStore.instance.removeListener(_settingsChanged);
    _stopPlayback();
    _animation.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ended) return const SizedBox.shrink();
    final color = _giftColor(widget.payload['color']?.toString());
    final tier = widget.payload['tier']?.toString() ?? 'small';
    final static = _reduced == true;
    final hasVideoSource = virtualGiftVideoUrl(widget.payload).isNotEmpty;
    return LayoutBuilder(builder: (context, constraints) {
      final screen = MediaQuery.sizeOf(context);
      final width =
          constraints.hasBoundedWidth ? constraints.maxWidth : screen.width;
      final height =
          constraints.hasBoundedHeight ? constraints.maxHeight : screen.height;
      final stageWidth =
          math.max(0.0, math.min(width - 24, static ? 380.0 : 460.0));
      final preferred = static
          ? 158.0
          : hasVideoSource || tier == 'large'
              ? 600.0
              : tier == 'small'
                  ? 260.0
                  : 350.0;
      // Loading, playback and fallback retain the same stage dimensions.
      // A portrait movie gets enough height without covering the top chat.
      final stageHeight = math.min(preferred, height * .66);
      final top = math.max(0.0, (height - stageHeight) * .69);
      final left = (width - stageWidth) / 2;
      return SizedBox(
        width: width,
        height: height,
        child: Stack(children: [
          Positioned(
            left: left,
            top: top,
            width: stageWidth,
            height: stageHeight,
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                label:
                    '${widget.preview ? '礼物预览，' : ''}${_caption(widget.payload)}',
                child: AnimatedBuilder(
                  animation: Listenable.merge([_animation, _exit]),
                  builder: (_, __) => Opacity(
                    key: const ValueKey('virtual_gift_exit'),
                    opacity: 1 - Curves.easeOut.transform(_exit.value),
                    child: _GiftStage(
                      payload: widget.payload,
                      color: color,
                      progress: static || _preparing ? .48 : _animation.value,
                      static: static,
                      preparing: _preparing,
                      video: _videoReady ? _video : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: left + 4,
            top: top + 2,
            child: Material(
              color: Colors.transparent,
              child: TextButton(
                key: const ValueKey('virtual_gift_skip'),
                onPressed: () => _complete(skip: true),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF20515B),
                  backgroundColor: const Color(0xF2F2FCFC),
                  minimumSize: const Size(64, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('跳过', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

Color _giftColor(String? value) {
  final raw = (value ?? '').replaceAll('#', '');
  final number = raw.length == 6 ? int.tryParse(raw, radix: 16) : null;
  return number == null ? AppColors.primary : Color(0xFF000000 | number);
}

String _name(Map<String, dynamic> payload, String key, String fallback) {
  final value = payload[key]?.toString().trim() ?? '';
  return value.isEmpty ? fallback : value;
}

bool _isEntry(Map<String, dynamic> payload) =>
    (payload['effectName']?.toString().trim().isNotEmpty ?? false) &&
    (payload['giftName']?.toString().trim().isEmpty ?? true);

String _caption(Map<String, dynamic> payload) => _isEntry(payload)
    ? '${_name(payload, 'nickname', '玄遇用户')} 来了'
    : '${_name(payload, 'senderName', '玄遇用户')} → '
        '${_name(payload, 'receiverName', '好友')}';

class _GiftStage extends StatelessWidget {
  const _GiftStage(
      {required this.payload,
      required this.color,
      required this.progress,
      required this.static,
      required this.preparing,
      this.video});

  final Map<String, dynamic> payload;
  final Color color;
  final double progress;
  final bool static;
  final bool preparing;
  final VideoPlayerController? video;

  @override
  Widget build(BuildContext context) {
    final tier = payload['tier']?.toString() ?? 'small';
    final entry = _isEntry(payload);
    final name = entry
        ? _name(payload, 'effectName', '欢迎入场')
        : _name(payload, 'giftName', _name(payload, 'name', '一份心意'));
    // A queued combo can exceed the single-order purchase limit.
    final quantity =
        (int.tryParse('${payload['quantity'] ?? 1}') ?? 1).clamp(1, 999999);
    final combo =
        (int.tryParse('${payload['comboCount'] ?? 1}') ?? 1).clamp(1, 999999);
    final large = tier == 'large';
    final hasPanel =
        virtualGiftVideoUrl(payload).isNotEmpty || large || static || preparing;
    final opacity = static || preparing || video != null
        ? 1.0
        : (progress < .1
                ? progress / .1
                : progress > .84
                    ? (1 - progress) / .16
                    : 1.0)
            .clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: ClipRRect(
        key: const ValueKey('virtual_gift_stage'),
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: hasPanel ? const Color(0xE8F3FCFC) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: hasPanel
                ? Border.all(color: color.withValues(alpha: .25))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
            child: LayoutBuilder(
                builder: (context, box) => Column(children: [
                      if (!static)
                        Expanded(
                          child: video != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Center(
                                      child: FittedBox(
                                    key: const ValueKey(
                                        'virtual_gift_video_contain'),
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: video!.value.size.width,
                                      height: video!.value.size.height,
                                      child: VideoPlayer(video!),
                                    ),
                                  )),
                                )
                              : preparing
                                  ? Center(
                                      child: Text(
                                          entry ? '正在准备入场特效…' : '正在准备礼物…',
                                          key: const ValueKey(
                                              'virtual_gift_preparing'),
                                          style: TextStyle(
                                              color: color, fontSize: 14)))
                                  : _GiftArtwork(
                                      progress: progress,
                                      type: payload['effectType']?.toString() ??
                                          'heart_flow',
                                      tier: tier,
                                      color: color,
                                      imageUrl: virtualGiftMediaUrl(payload,
                                          effect: true),
                                      fallback:
                                          payload['iconText']?.toString() ??
                                              '✦'),
                        ),
                      SizedBox(
                        height: static
                            ? box.maxHeight
                            : math.max(
                                0.0, math.min(box.maxHeight * .28, 84.0)),
                        child: Center(
                            child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: math.max(
                                1,
                                MediaQuery.sizeOf(context).width.clamp(0, 460) -
                                    60),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(entry ? name : '$name ×$quantity',
                                      key: const ValueKey(
                                          'virtual_gift_caption'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: const Color(0xFF174852),
                                          fontSize: large ? 20 : 17,
                                          fontWeight: FontWeight.w800,
                                          shadows: const [
                                            Shadow(
                                                color: Colors.white,
                                                blurRadius: 8)
                                          ])),
                                  const SizedBox(height: 5),
                                  if (!entry && combo > 1)
                                    Text('连击 ×$combo',
                                        key: const ValueKey(
                                            'virtual_gift_combo'),
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                  Text(_caption(payload),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Color(0xFF456571),
                                          fontSize: 13,
                                          shadows: [
                                            Shadow(
                                                color: Colors.white,
                                                blurRadius: 6)
                                          ])),
                                ]),
                          ),
                        )),
                      ),
                    ])),
          ),
        ),
      ),
    );
  }
}

class _GiftArtwork extends StatelessWidget {
  const _GiftArtwork(
      {required this.progress,
      required this.type,
      required this.tier,
      required this.color,
      required this.imageUrl,
      required this.fallback});

  final double progress;
  final String type;
  final String tier;
  final Color color;
  final String imageUrl;
  final String fallback;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final enter =
            Curves.easeOutCubic.transform((progress / .28).clamp(0, 1));
        final settle = math.sin(progress * math.pi);
        final water = type.contains('koi') || type.contains('whale');
        final rising = type.contains('phoenix') || type.contains('lantern');
        final blooming = type.contains('magnolia') || type.contains('portal');
        final x = water
            ? (1 - enter) * -box.maxWidth * .6 +
                math.sin(progress * math.pi * 2) * 7
            : type == 'fortune_ribbon'
                ? (1 - enter) * box.maxWidth * .45
                : 0.0;
        final y = rising
            ? (1 - enter) * box.maxHeight * .55 - settle * 8
            : blooming
                ? (1 - enter) * 16
                : -settle * 9;
        final angle = water
            ? math.sin(progress * math.pi * 2) * .055
            : rising
                ? (1 - enter) * -.06
                : 0.0;
        final scale = blooming ? .68 + enter * .32 : .9 + enter * .1;
        final side = math.min(box.maxWidth * .82, box.maxHeight * .92);
        return Stack(key: const ValueKey('virtual_gift_artwork'), children: [
          Positioned.fill(
              child: CustomPaint(
                  painter: _GiftAtmosphere(
                      progress: progress,
                      color: color,
                      type: type,
                      subtle: tier == 'small'))),
          Center(
              child: Transform.translate(
            offset: Offset(x, y),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                  scale: scale,
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: imageUrl.isEmpty
                        ? _fallbackIcon()
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => _fallbackIcon(),
                            loadingBuilder: (_, child, loading) =>
                                loading == null ? child : _fallbackIcon(),
                          ),
                  )),
            ),
          )),
        ]);
      });

  Widget _fallbackIcon() => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(fallback,
          style: TextStyle(
              fontSize: 72,
              color: color,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(color: color.withValues(alpha: .25), blurRadius: 18)
              ])));
}

class _GiftAtmosphere extends CustomPainter {
  const _GiftAtmosphere(
      {required this.progress,
      required this.color,
      required this.type,
      required this.subtle});
  final double progress;
  final Color color;
  final String type;
  final bool subtle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .46;
    final alpha = math.sin(progress * math.pi).clamp(0.0, 1.0);
    if (!subtle) {
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: .18 * alpha),
              color.withValues(alpha: .03 * alpha),
              Colors.transparent,
            ]).createShader(Rect.fromCircle(center: center, radius: radius)));
    }
    final water = type.contains('koi') || type.contains('whale');
    final ring = water || type.contains('portal') || type.contains('moon');
    if (ring) {
      for (var i = 0; i < 3; i++) {
        final phase = (progress * 1.4 + i / 3) % 1;
        canvas.drawOval(
            Rect.fromCenter(
              center: center + Offset(0, water ? size.height * .3 : 0),
              width: radius * (1 + phase),
              height: radius * (1 + phase) * (water ? .24 : 1),
            ),
            Paint()
              ..color = color.withValues(alpha: (1 - phase) * .22 * alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }
    final count = subtle ? 7 : 17;
    for (var i = 0; i < count; i++) {
      final phase = (progress * .7 + i * .137) % 1;
      final angle = i * 2.4 + (water ? progress * .2 : 0);
      final distance = radius * (.45 + phase * .65);
      final point = center +
          Offset(
              math.cos(angle) * distance,
              math.sin(angle) * distance -
                  (type.contains('phoenix') ? phase * radius * .25 : 0));
      final paint = Paint()
        ..color = (i % 3 == 0 ? const Color(0xFFE5C97A) : color)
            .withValues(alpha: (1 - phase) * .5 * alpha);
      final r = subtle ? 2.0 : 2.6;
      if (type.contains('magnolia') || type == 'fortune_ribbon') {
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle + progress * .6);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 4),
            paint);
        canvas.restore();
      } else {
        canvas.drawCircle(point, r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GiftAtmosphere old) =>
      progress != old.progress ||
      color != old.color ||
      type != old.type ||
      subtle != old.subtle;
}
