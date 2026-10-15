import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../app/common/values/images.dart';
import '../models/wish_pond_simulation.dart';

class WishWaterLifeLayer extends StatefulWidget {
  const WishWaterLifeLayer({
    super.key,
    this.feedSequence = 0,
    this.feedQuantity = 1,
    this.onFeedingStageChanged,
    this.onFeedingComplete,
  });

  final int feedSequence;
  final int feedQuantity;
  final ValueChanged<WishFeedingStage>? onFeedingStageChanged;
  final VoidCallback? onFeedingComplete;

  @override
  State<WishWaterLifeLayer> createState() => _WishWaterLifeLayerState();
}

class _WishWaterLifeLayerState extends State<WishWaterLifeLayer>
    with SingleTickerProviderStateMixin {
  final _pond = WishPondSimulation();
  final _repaint = ValueNotifier<int>(0);
  final _images = <ui.Image>[];
  late final Ticker _ticker;
  Duration? _lastElapsed;
  int _startedSequence = 0;
  WishFeedingStage _reportedStage = WishFeedingStage.complete;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _loadImages();
  }

  Future<void> _loadImages() async {
    for (final asset in [
      ImageAssets.wishKoiKohaku,
      ImageAssets.wishKoiGold,
      ImageAssets.wishKoiSanke,
      ImageAssets.wishPondTurtle,
    ]) {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 128,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _images.add(frame.image);
      _repaint.value++;
    }
  }

  void _tick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (_pond.size.isEmpty || previous == null) return;
    if (widget.feedSequence != _startedSequence) {
      _startedSequence = widget.feedSequence;
      _pond.feed(widget.feedQuantity);
    }
    // Returning from another app must not teleport fish or skip eating.
    final seconds =
        ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, 0.1);
    _pond.advance(seconds);
    _repaint.value++;
    final stage = _pond.stage;
    if (_reportedStage != stage) {
      _reportedStage = stage;
      widget.onFeedingStageChanged?.call(stage);
      if (stage == WishFeedingStage.complete) widget.onFeedingComplete?.call();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    for (final image in _images) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: LayoutBuilder(builder: (context, constraints) {
            _pond.resize(constraints.biggest);
            return CustomPaint(
              painter: _WishPondPainter(_pond, _images, _repaint),
              size: constraints.biggest,
            );
          }),
        ),
      );
}

class _WishPondPainter extends CustomPainter {
  _WishPondPainter(this.pond, this.images, Listenable repaint)
      : super(repaint: repaint);

  final WishPondSimulation pond;
  final List<ui.Image> images;
  static final _identity = Float64List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    // Tint the full water width, outside the animal safety clip. The former
    // clipped tint/veil produced straight dark boundaries on both sides.
    final waterTop = size.height * 0.69;
    canvas.drawRect(
      Rect.fromLTRB(0, waterTop, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, waterTop),
          Offset(0, size.height),
          const [Color(0x00168891), Color(0x08168891), Color(0x10168891)],
          const [0, 0.6, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(_waterPath(size));
    for (final fish in pond.fish) {
      if (fish.index < images.length) {
        _drawFish(canvas, fish, images[fish.index]);
      }
    }
    if (images.length == 4) _drawTurtle(canvas, size, images.last);
    _drawFood(canvas);
    canvas.restore();
  }

  void _drawFish(Canvas canvas, WishPondFish fish, ui.Image image) {
    canvas.save();
    canvas.translate(fish.position.dx, fish.position.dy);
    canvas.rotate(fish.heading + math.pi / 2);
    final width = fish.width;
    final height = fish.length;
    canvas.drawOval(
      Rect.fromCenter(
          center: const Offset(1.5, 3),
          width: width * 0.26,
          height: height * 0.72),
      Paint()
        ..color = const Color(0x0C186871)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Deform the existing ink artwork as one continuous mesh. The nose stays
    // anchored while bending grows towards the tail, avoiding rigid cut-outs.
    final vertices = <Offset>[];
    final texture = <Offset>[];
    final indices = <int>[];
    const rows = 18;
    final biting = ((fish.biteUntil - pond.time) / 0.25).clamp(0.0, 1.0);
    for (var row = 0; row <= rows; row++) {
      final t = row / rows;
      final tail = ((t - 0.16) / 0.84).clamp(0.0, 1.0);
      final bend =
          math.sin(fish.tailPhase - t * 4) * width * 0.14 * tail * tail;
      final nibble = 1 - math.sin(biting * math.pi) * 0.035 * (1 - t);
      for (var column = 0; column < 2; column++) {
        vertices.add(
            Offset((column - 0.5) * width * nibble + bend, (t - 0.5) * height));
        texture.add(Offset(column * image.width.toDouble(), t * image.height));
      }
      if (row < rows) {
        final i = row * 2;
        indices.addAll([i, i + 1, i + 2, i + 1, i + 3, i + 2]);
      }
    }
    final mesh = ui.Vertices(ui.VertexMode.triangles, vertices,
        textureCoordinates: texture, indices: indices);
    final shader =
        ImageShader(image, TileMode.clamp, TileMode.clamp, _identity);
    canvas.drawVertices(
      mesh,
      BlendMode.modulate,
      Paint()
        ..shader = shader
        ..color = const Color(0xAAFFFFFF)
        ..filterQuality = FilterQuality.medium,
    );
    mesh.dispose();
    shader.dispose();
    canvas.restore();
  }

  void _drawTurtle(Canvas canvas, Size size, ui.Image image) {
    final t = pond.time;
    final point = Offset(size.width * (0.36 + math.sin(t * 0.06) * 0.025),
        size.height * (0.895 + math.cos(t * 0.045) * 0.015));
    final dx = size.width * 0.025 * 0.06 * math.cos(t * 0.06);
    final dy = -size.height * 0.015 * 0.045 * math.sin(t * 0.045);
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(math.atan2(dy, dx) + math.pi / 2);
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(-15, -15, 30, 30),
        Paint()
          ..color = const Color(0x66FFFFFF)
          ..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  void _drawFood(Canvas canvas) {
    for (final grain in pond.grains) {
      if (pond.time < grain.releaseAt) continue;
      final landingAge = pond.time - grain.landsAt;
      if (landingAge >= 0 && landingAge < 0.85) {
        _ripple(canvas, grain.landing, landingAge / 0.85, 0.32, 9);
      }
      if (grain.eatenAt != null) {
        final age = pond.time - grain.eatenAt!;
        if (age < 0.6) _ripple(canvas, grain.position, age / 0.6, 0.42, 6);
        continue;
      }
      canvas.drawCircle(grain.position + const Offset(0.4, 0.7), grain.radius,
          Paint()..color = const Color(0x49315D58));
      canvas.drawCircle(grain.position, grain.radius,
          Paint()..color = const Color(0xFFCCA267));
      canvas.drawCircle(grain.position - const Offset(0.3, 0.3),
          grain.radius * 0.36, Paint()..color = const Color(0xFFE9CA8E));
    }
  }

  void _ripple(Canvas canvas, Offset center, double progress, double opacity,
      double radius) {
    canvas.drawOval(
      Rect.fromCenter(
          center: center,
          width: 2 + radius * 2 * progress,
          height: 1 + radius * progress * 0.7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = Color.fromRGBO(199, 235, 222, (1 - progress) * opacity),
    );
  }

  Path _waterPath(Size size) => Path()
    ..moveTo(size.width * 0.31, size.height * 0.70)
    ..quadraticBezierTo(size.width * 0.50, size.height * 0.67,
        size.width * 0.69, size.height * 0.70)
    ..lineTo(size.width * 0.74, size.height * 0.79)
    ..lineTo(size.width * 0.69, size.height)
    ..lineTo(size.width * 0.20, size.height)
    ..lineTo(size.width * 0.25, size.height * 0.79)
    ..close();

  @override
  bool shouldRepaint(covariant _WishPondPainter oldDelegate) =>
      pond != oldDelegate.pond || images != oldDelegate.images;
}
