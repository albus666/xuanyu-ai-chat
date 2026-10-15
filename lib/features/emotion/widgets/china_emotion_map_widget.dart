import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'package:xuanyu/features/emotion/data/china_province_loader.dart';
import 'package:xuanyu/features/emotion/data/province_names.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';

/// 情绪地图上的匿名状态点。坐标应由服务端完成模糊化后再下发。
class EmotionMapPoint {
  const EmotionMapPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.emotion,
    required this.locationLabel,
  });

  final int id;
  final double latitude;
  final double longitude;
  final EmotionType emotion;
  final String locationLabel;
}

/// 全国省级情绪热力/图标地图（GeoJSON 矢量自绘）。
///
/// [provinceEmotions] / [provinceCounts] 的 key 可为短名（河南）或全称（河南省）。
class ChinaEmotionMapWidget extends StatefulWidget {
  const ChinaEmotionMapWidget({
    super.key,
    required this.provinceEmotions,
    this.provinceCounts = const {},
    this.selectedProvince,
    this.onProvinceTap,
    this.points = const [],
    this.onPointTap,
    this.onScaleChanged,
    this.expand = false,
  });

  final Map<String, EmotionType> provinceEmotions;
  final Map<String, int> provinceCounts;
  final String? selectedProvince;
  final void Function(String province, EmotionType? emotion)? onProvinceTap;
  final List<EmotionMapPoint> points;
  final ValueChanged<EmotionMapPoint>? onPointTap;
  final ValueChanged<double>? onScaleChanged;

  /// true：铺满父布局；false：保持 1:1 正方形（面板嵌入用）
  final bool expand;

  @override
  State<ChinaEmotionMapWidget> createState() => _ChinaEmotionMapWidgetState();
}

class _ChinaEmotionMapWidgetState extends State<ChinaEmotionMapWidget> {
  List<ChinaProvince>? _provinces;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ChinaProvinceLoader.load();
      if (!mounted) return;
      setState(() {
        _provinces = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _provinces = const [];
        _loading = false;
      });
    }
  }

  EmotionType? _emotionOf(String shortName) {
    final emos = widget.provinceEmotions;
    final direct = emos[shortName];
    if (direct != null) return direct;
    final full = ProvinceNames.toFull(shortName);
    if (full != null && emos[full] != null) return emos[full];
    for (final e in emos.entries) {
      if (ProvinceNames.toShort(e.key) == shortName) return e.value;
    }
    return null;
  }

  int _countOf(String shortName) {
    final counts = widget.provinceCounts;
    if (counts.containsKey(shortName)) return counts[shortName]!;
    final full = ProvinceNames.toFull(shortName);
    if (full != null && counts.containsKey(full)) return counts[full]!;
    for (final e in counts.entries) {
      if (ProvinceNames.toShort(e.key) == shortName) return e.value;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final map = _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _ChinaVectorMap(
            provinces: _provinces ?? [],
            emotionOf: _emotionOf,
            countOf: _countOf,
            selectedProvince: widget.selectedProvince,
            points: widget.points,
            onPointTap: widget.onPointTap,
            onScaleChanged: widget.onScaleChanged,
            onProvinceTap: (province) {
              widget.onProvinceTap?.call(province, _emotionOf(province));
            },
          );

    if (widget.expand) {
      return map;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: 1, child: map),
    );
  }
}

class _MapProjection {
  _MapProjection._();

  static const _bounds = _GeoBounds(
    minLng: 75.0,
    maxLng: 134.0,
    minLat: 18.0,
    maxLat: 53.5,
  );

  static const _pad = 0.05;

  static double get _geoW => _bounds.maxLng - _bounds.minLng;
  static double get _geoH => _bounds.maxLat - _bounds.minLat;
  static double get _refLatRad => 36.0 * math.pi / 180;
  static double get _lngVisualW => _geoW * math.cos(_refLatRad);
  static double get _geoAspect => _lngVisualW / _geoH;

  static ({double mapW, double mapH, double offsetX, double offsetY}) get _fit {
    const avail = 1.0 - _pad * 2;
    const intrinsicH = 1.0;
    final intrinsicW = _geoAspect;
    final longSide = math.max(intrinsicW, intrinsicH);
    final scale = avail / longSide;
    final mapW = intrinsicW * scale;
    final mapH = intrinsicH * scale;
    return (
      mapW: mapW,
      mapH: mapH,
      offsetX: (1 - mapW) / 2,
      offsetY: (1 - mapH) / 2,
    );
  }

  static Offset normalized(LatLng p) {
    final fit = _fit;
    final nx =
        fit.offsetX + ((p.longitude - _bounds.minLng) / _geoW) * fit.mapW;
    final ny =
        fit.offsetY + (1 - (p.latitude - _bounds.minLat) / _geoH) * fit.mapH;
    return Offset(nx, ny);
  }

  static Offset toCanvas(LatLng p, Size size) {
    final n = normalized(p);
    return Offset(n.dx * size.width, n.dy * size.height);
  }

  static Path scaleToCanvas(Path normPath, Size canvasSize) {
    final m = Matrix4.diagonal3Values(canvasSize.width, canvasSize.height, 1);
    return normPath.transform(m.storage);
  }
}

class _ChinaVectorMap extends StatefulWidget {
  const _ChinaVectorMap({
    required this.provinces,
    required this.emotionOf,
    required this.countOf,
    required this.selectedProvince,
    required this.onProvinceTap,
    required this.points,
    required this.onPointTap,
    required this.onScaleChanged,
  });

  final List<ChinaProvince> provinces;
  final EmotionType? Function(String shortName) emotionOf;
  final int Function(String shortName) countOf;
  final String? selectedProvince;
  final ValueChanged<String> onProvinceTap;
  final List<EmotionMapPoint> points;
  final ValueChanged<EmotionMapPoint>? onPointTap;
  final ValueChanged<double>? onScaleChanged;

  @override
  State<_ChinaVectorMap> createState() => _ChinaVectorMapState();
}

class _ChinaVectorMapState extends State<_ChinaVectorMap> {
  List<_ProvinceDrawData> _drawData = const [];
  final TransformationController _transform = TransformationController();
  Size _viewportSize = Size.zero;
  int _zoomBucket = 0;

  @override
  void initState() {
    super.initState();
    _rebuildPaths();
    _transform.addListener(_handleTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_handleTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChinaVectorMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provinces != widget.provinces) {
      _rebuildPaths();
    }
  }

  void _rebuildPaths() {
    _drawData = widget.provinces.map((prov) {
      final paths = <Path>[];
      Path? hitPath;
      for (final ring in prov.rings) {
        final path = _ringToPath(ring);
        paths.add(path);
        hitPath ??= path;
      }
      return _ProvinceDrawData(province: prov, paths: paths, hitPath: hitPath);
    }).toList();
  }

  Path _ringToPath(List<LatLng> ring) {
    final path = Path();
    if (ring.isEmpty) return path;
    final first = _MapProjection.normalized(ring.first);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < ring.length; i++) {
      final p = _MapProjection.normalized(ring[i]);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  void _handleTransform() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final bucket = scale >= 4.0
        ? 2
        : scale >= 2.15
            ? 1
            : 0;
    if (bucket == _zoomBucket) return;
    setState(() => _zoomBucket = bucket);
    widget.onScaleChanged?.call(scale);
  }

  void _setScale(double scale) {
    if (_viewportSize.isEmpty) return;
    final target = scale.clamp(1.0, 8.0);
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, target)
      ..setEntry(1, 1, target)
      ..setEntry(0, 3, (1 - target) * _viewportSize.width / 2)
      ..setEntry(1, 3, (1 - target) * _viewportSize.height / 2);
    _transform.value = matrix;
  }

  void _zoomBy(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    _setScale(current * factor);
  }

  void _resetMap() => _transform.value = Matrix4.identity();

  Widget _mapPoint(EmotionMapPoint point, Offset position) {
    final showLabel = _zoomBucket >= 2 && point.locationLabel.isNotEmpty;
    return Positioned(
      left: position.dx - 52,
      top: position.dy - 20,
      width: 104,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPointTap?.call(point),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: point.emotion.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330F172A),
                    blurRadius: 7,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(point.emotion.emoji,
                  style: const TextStyle(fontSize: 18)),
            ),
            if (showLabel) ...[
              const SizedBox(height: 2),
              Container(
                constraints: const BoxConstraints(maxWidth: 104),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  point.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _viewportSize = size;
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 8,
                panEnabled: true,
                scaleEnabled: true,
                clipBehavior: Clip.hardEdge,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => _zoomBy(1.8),
                  onTapUp: (details) {
                    final local = details.localPosition;
                    final nx = local.dx / size.width;
                    final ny = local.dy / size.height;
                    for (final item in _drawData.reversed) {
                      final hit = item.hitPath;
                      if (hit != null && hit.contains(Offset(nx, ny))) {
                        widget.onProvinceTap(item.province.shortName);
                        return;
                      }
                    }
                  },
                  child: CustomPaint(
                    size: size,
                    painter: _ChinaMapPainter(
                      drawData: _drawData,
                      emotionOf: widget.emotionOf,
                      countOf: widget.countOf,
                      selectedProvince: widget.selectedProvince,
                      canvasSize: size,
                      showProvinceBubbles: _zoomBucket == 0,
                    ),
                  ),
                ),
              ),
            ),
            if (_zoomBucket > 0 && widget.points.isNotEmpty)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _transform,
                  builder: (context, _) {
                    final children = <Widget>[];
                    for (final point in widget.points) {
                      final normalized = _MapProjection.normalized(
                        LatLng(point.latitude, point.longitude),
                      );
                      final base = Offset(
                        normalized.dx * size.width,
                        normalized.dy * size.height,
                      );
                      final position = MatrixUtils.transformPoint(
                        _transform.value,
                        base,
                      );
                      final angle = (point.id % 12) * math.pi / 6;
                      final radius = 5.0 + ((point.id ~/ 12) % 3) * 6.0;
                      final spread = position.translate(
                        math.cos(angle) * radius,
                        math.sin(angle) * radius,
                      );
                      if (spread.dx < -60 ||
                          spread.dx > size.width + 60 ||
                          spread.dy < -60 ||
                          spread.dy > size.height + 60) {
                        continue;
                      }
                      children.add(_mapPoint(point, spread));
                    }
                    return Stack(clipBehavior: Clip.none, children: children);
                  },
                ),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Material(
                color: Colors.white.withValues(alpha: 0.94),
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '放大',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _zoomBy(1.55),
                      icon: const Icon(Icons.add_rounded),
                    ),
                    const SizedBox(width: 34, child: Divider(height: 1)),
                    IconButton(
                      tooltip: '缩小',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _zoomBy(1 / 1.55),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 34, child: Divider(height: 1)),
                    IconButton(
                      tooltip: '回到全国',
                      visualDensity: VisualDensity.compact,
                      onPressed: _resetMap,
                      icon: const Icon(Icons.public_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProvinceDrawData {
  _ProvinceDrawData({
    required this.province,
    required this.paths,
    required this.hitPath,
  });

  final ChinaProvince province;
  final List<Path> paths;
  final Path? hitPath;
}

class _GeoBounds {
  const _GeoBounds({
    required this.minLng,
    required this.maxLng,
    required this.minLat,
    required this.maxLat,
  });
  final double minLng;
  final double maxLng;
  final double minLat;
  final double maxLat;
}

class _ChinaMapPainter extends CustomPainter {
  _ChinaMapPainter({
    required this.drawData,
    required this.emotionOf,
    required this.countOf,
    required this.selectedProvince,
    required this.canvasSize,
    required this.showProvinceBubbles,
  });

  final List<_ProvinceDrawData> drawData;
  final EmotionType? Function(String shortName) emotionOf;
  final int Function(String shortName) countOf;
  final String? selectedProvince;
  final Size canvasSize;
  final bool showProvinceBubbles;

  @override
  void paint(Canvas canvas, Size size) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB8D4E8), Color(0xFFE8F4FA)],
        ).createShader(bgRect),
    );

    for (final item in drawData) {
      final prov = item.province;
      final emo = emotionOf(prov.shortName);
      final count = countOf(prov.shortName);
      final hasData = emo != null && count > 0;
      final selected = selectedProvince == prov.shortName ||
          selectedProvince == prov.fullName ||
          (selectedProvince != null &&
              ProvinceNames.toShort(selectedProvince!) == prov.shortName);

      final fillColor = hasData
          ? emo.color.withValues(alpha: selected ? 0.78 : 0.52)
          : (selected
              ? const Color(0xFF94A3B8).withValues(alpha: 0.45)
              : const Color(0xFFE2E8F0).withValues(alpha: 0.85));
      final strokeColor = selected
          ? const Color(0xFF0F172A)
          : (hasData
              ? emo.color.withValues(alpha: 0.9)
              : const Color(0xFFCBD5E1));

      for (final normPath in item.paths) {
        final path = _MapProjection.scaleToCanvas(normPath, canvasSize);
        canvas.drawPath(
            path,
            Paint()
              ..color = fillColor
              ..style = PaintingStyle.fill);
        canvas.drawPath(
          path,
          Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.2 : 0.7,
        );
      }

      final c = _MapProjection.toCanvas(prov.centroid, canvasSize);

      if (showProvinceBubbles && hasData) {
        // 情绪气泡：emoji + 人数
        final bubbleR = selected ? 16.0 : 13.0;
        canvas.drawCircle(
          c,
          bubbleR + 1.5,
          Paint()..color = Colors.white.withValues(alpha: 0.95),
        );
        canvas.drawCircle(
          c,
          bubbleR,
          Paint()..color = emo.color.withValues(alpha: 0.9),
        );

        final emojiTp = TextPainter(
          text: TextSpan(
            text: emo.emoji,
            style: TextStyle(fontSize: selected ? 14 : 12),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        emojiTp.paint(
          canvas,
          Offset(c.dx - emojiTp.width / 2, c.dy - emojiTp.height / 2 - 1),
        );

        if (count > 0) {
          final badge = count > 99 ? '99+' : '$count';
          final countTp = TextPainter(
            text: TextSpan(
              text: badge,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          final badgeCenter =
              Offset(c.dx + bubbleR * 0.75, c.dy - bubbleR * 0.75);
          canvas.drawCircle(
            badgeCenter,
            math.max(countTp.width, countTp.height) / 2 + 3,
            Paint()..color = const Color(0xFFEF4444),
          );
          countTp.paint(
            canvas,
            Offset(
              badgeCenter.dx - countTp.width / 2,
              badgeCenter.dy - countTp.height / 2,
            ),
          );
        }
      } else if (selected) {
        final tip = TextPainter(
          text: TextSpan(
            text: prov.shortName,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
              shadows: [Shadow(color: Colors.white, blurRadius: 3)],
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tip.paint(canvas, Offset(c.dx - tip.width / 2, c.dy - tip.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChinaMapPainter old) => true;
}
