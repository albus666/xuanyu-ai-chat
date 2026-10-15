import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../../shared/widgets/cultural_reference_notice.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 罗盘样式：入门 = compass.png，综合 = 4.png
enum _CompassStyle { beginner, comprehensive }

/// 电子罗盘：入门/综合样式切换 + 指南针度数（0–360°）
class BaguaCompassTab extends StatefulWidget {
  const BaguaCompassTab({super.key});

  @override
  State<BaguaCompassTab> createState() => _BaguaCompassTabState();
}

class _BaguaCompassTabState extends State<BaguaCompassTab> with SingleTickerProviderStateMixin {
  static const _assetBeginner = 'assets/baguapan/compass.png';
  static const _assetComprehensive = 'assets/baguapan/4.png';

  _CompassStyle _style = _CompassStyle.beginner;
  bool _compassAssetExists = true;
  StreamSubscription<CompassEvent>? _compassSubscription;

  /// 罗盘旋转角度（弧度），由 Ticker 以 60fps 插值更新，保证转动流畅
  final ValueNotifier<double> _displayAngle = ValueNotifier(0);
  /// 真实朝向度数，用于显示方位/度数
  final ValueNotifier<double?> _headingDegrees = ValueNotifier(null);
  double? _targetHeadingDegrees;
  late Ticker _ticker;

  String get _currentAsset => _style == _CompassStyle.beginner ? _assetBeginner : _assetComprehensive;

  @override
  void initState() {
    super.initState();
    // Android 仅在原生隐私同意、Flutter 引擎启动之后才会走到这里。
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted || event.heading == null) return;
      _targetHeadingDegrees = event.heading;
      _headingDegrees.value = event.heading;
    });
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (_targetHeadingDegrees == null || !mounted) return;
    final targetRad = -_targetHeadingDegrees! * math.pi / 180;
    final current = _displayAngle.value;
    final diff = _shortestAngleDiff(current, targetRad);
    const factor = 0.25; // 每帧逼近 25%，约 4 帧跟上
    final step = diff * factor;
    if (step.abs() > 0.0001) {
      _displayAngle.value = current + step;
    }
  }

  static double _shortestAngleDiff(double fromRad, double toRad) {
    var d = toRad - fromRad;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _displayAngle.dispose();
    _headingDegrees.dispose();
    _compassSubscription?.cancel();
    super.dispose();
  }

  static String _directionName(double degrees) {
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final index = ((degrees + 22.5) % 360 / 45).floor().clamp(0, 7);
    return names[index];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.shortestSide * 0.95;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildStyleSwitch(),
          const SizedBox(height: 32),
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildCompassPlate(size),
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(size, size),
                    painter: _CompassOverlayPainter(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          ValueListenableBuilder<double?>(
            valueListenable: _headingDegrees,
            builder: (_, heading, __) => _buildDegreeDisplay(heading),
          ),
          const SizedBox(height: 24),
          Text(
            '请水平放置手机，红线指向即为当前方位',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
          const CulturalReferenceNotice(),
        ],
      ),
    );
  }

  Widget _buildStyleSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _styleButton('入门', _CompassStyle.beginner),
          _styleButton('综合', _CompassStyle.comprehensive),
        ],
      ),
    );
  }

  Widget _styleButton(String label, _CompassStyle style) {
    final selected = _style == style;
    return GestureDetector(
      onTap: () => setState(() {
        _style = style;
        _compassAssetExists = true;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCompassPlate(double size) {
    return ValueListenableBuilder<double>(
      valueListenable: _displayAngle,
      builder: (_, angle, child) {
        return RepaintBoundary(
          child: Transform.rotate(
            angle: angle,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, spreadRadius: 5),
          ],
        ),
        child: _compassAssetExists
            ? Image.asset(
                _currentAsset,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  if (_compassAssetExists) WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _compassAssetExists = false));
                  return _buildCompassFallback(size);
                },
              )
            : _buildCompassFallback(size),
      ),
    );
  }

  Widget _buildDegreeDisplay(double? heading) {
    if (heading == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4))],
        ),
        child: Text('正在获取传感器数据...', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
      );
    }
    final deg = heading.round() % 360;
    final dir = _directionName(heading);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Text(dir, style: AppTextStyles.displayLarge.copyWith(color: AppColors.primary, fontSize: 32)),
          const SizedBox(height: 8),
          Text('$deg°', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textSecondary, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildCompassFallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2C2C2C),
        border: Border.all(color: const Color(0xFF8B4513).withOpacity(0.8), width: 6),
      ),
      child: CustomPaint(
        painter: _CompassRingPainter(),
        size: Size(size, size),
      ),
    );
  }
}

/// 罗盘上的十字线 + 指针（固定不随罗盘旋转，指针指向上方为当前朝向）
class _CompassOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2;

    // 十字虚线：红线
    final linePaint = Paint()
      ..color = const Color(0xFFC62828).withOpacity(0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    // 绘制十字参考线
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), linePaint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), linePaint);

    // 绘制顶部指向指针
    final pointerPaint = Paint()
      ..color = const Color(0xFFC62828)
      ..style = PaintingStyle.fill;
    
    final pointerPath = Path()
      ..moveTo(cx, cy - r + 5)
      ..lineTo(cx - 10, cy - r + 30)
      ..lineTo(cx + 10, cy - r + 30)
      ..close();
    
    canvas.drawPath(pointerPath, pointerPaint);
    
    // 增加一个外圈刻度引导
    final guidePaint = Paint()
      ..color = const Color(0xFFC62828)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r - 2), -math.pi/2 - 0.05, 0.1, false, guidePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompassRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = size.width / 2 - 12;
    final paint = Paint()..color = const Color(0xFFD4AF37).withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1;
    
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final start = (i % 3 == 0) ? r - 20 : r - 10;
      canvas.drawLine(
        Offset(cx + start * math.cos(a), cy + start * math.sin(a)),
        Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
        paint,
      );
    }
    
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labels = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: const Color(0xFFD4AF37), fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2)]),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(cx + (r - 40) * math.cos(a) - textPainter.width / 2, cy + (r - 40) * math.sin(a) - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
