import 'package:flutter/material.dart';

/// 用户提供的参考稿中五个社交平台图标。
enum ReferenceShareBrand { weChat, moments, qq, qzone, weibo }

extension on ReferenceShareBrand {
  String get assetPath => switch (this) {
        ReferenceShareBrand.weChat => 'assets/reference_actions/wechat.png',
        ReferenceShareBrand.moments => 'assets/reference_actions/moments.png',
        ReferenceShareBrand.qq => 'assets/reference_actions/qq.png',
        ReferenceShareBrand.qzone => 'assets/reference_actions/qzone.png',
        ReferenceShareBrand.weibo => 'assets/reference_actions/weibo.png',
      };
}

class ReferenceShareBrandIcon extends StatelessWidget {
  const ReferenceShareBrandIcon({
    super.key,
    required this.brand,
    this.diameter = 48,
  });

  final ReferenceShareBrand brand;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        brand.assetPath,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// 社交平台列表末尾的系统分享入口，样式与参考稿中的“三点·更多”一致。
class ReferenceShareMoreIcon extends StatelessWidget {
  const ReferenceShareMoreIcon({super.key, this.diameter = 48});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F6),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.more_horiz_rounded,
        size: 24,
        color: Color(0xFF4B4B4B),
      ),
    );
  }
}

enum ReferenceActionIconType {
  privateChat,
  shareImage,
  follow,
  dislike,
  report,
}

extension on ReferenceActionIconType {
  String get circleAssetPath => switch (this) {
        ReferenceActionIconType.privateChat =>
          'assets/reference_actions/private_chat.png',
        ReferenceActionIconType.shareImage =>
          'assets/reference_actions/share_image.png',
        ReferenceActionIconType.follow => 'assets/reference_actions/follow.png',
        ReferenceActionIconType.dislike =>
          'assets/reference_actions/dislike.png',
        ReferenceActionIconType.report => 'assets/reference_actions/report.png',
      };

  String get glyphAssetPath => switch (this) {
        ReferenceActionIconType.privateChat =>
          'assets/reference_actions/private_chat_glyph.png',
        ReferenceActionIconType.shareImage =>
          'assets/reference_actions/share_image_glyph.png',
        ReferenceActionIconType.follow =>
          'assets/reference_actions/follow_glyph.png',
        ReferenceActionIconType.dislike =>
          'assets/reference_actions/dislike_glyph.png',
        ReferenceActionIconType.report =>
          'assets/reference_actions/report_glyph.png',
      };
}

/// 带原稿浅灰圆底的完整功能图标，用于操作面板。
class ReferenceActionCircleIcon extends StatelessWidget {
  const ReferenceActionCircleIcon({
    super.key,
    required this.type,
    this.diameter = 50,
  });

  final ReferenceActionIconType type;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    if (type == ReferenceActionIconType.privateChat) {
      return Container(
        width: diameter,
        height: diameter,
        decoration: const BoxDecoration(
          color: Color(0xFFF5F5F6),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: _PrivateChatGlyph(size: diameter * 0.52),
      );
    }
    return ClipOval(
      child: Image.asset(
        type.circleAssetPath,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// 从同一张原稿提取的透明线性图标，用于普通按钮和详情底栏。
class ReferenceActionGlyph extends StatelessWidget {
  const ReferenceActionGlyph({
    super.key,
    required this.type,
    this.size = 31,
    this.color,
  });

  final ReferenceActionIconType type;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? const Color(0xFF4B4B4B);
    if (type == ReferenceActionIconType.privateChat) {
      return _PrivateChatGlyph(size: size, color: resolvedColor);
    }
    return Image.asset(
      type.glyphAssetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      color: resolvedColor,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

/// 全局私聊入口：双点微笑气泡，保留轻松亲和的私聊感。
class _PrivateChatGlyph extends StatelessWidget {
  const _PrivateChatGlyph({
    required this.size,
    this.color = const Color(0xFF4B4B4B),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PrivateChatGlyphPainter(color: color),
      ),
    );
  }
}

class _PrivateChatGlyphPainter extends CustomPainter {
  const _PrivateChatGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (unit * 0.085).clamp(1.4, 2.8).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final smile = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (unit * 0.09).clamp(1.5, 3.0).toDouble()
      ..strokeCap = StrokeCap.round;
    final eye = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final bubble = Path()
      ..moveTo(unit * 0.37, unit * 0.17)
      ..lineTo(unit * 0.70, unit * 0.17)
      ..cubicTo(
        unit * 0.82,
        unit * 0.17,
        unit * 0.88,
        unit * 0.26,
        unit * 0.88,
        unit * 0.39,
      )
      ..lineTo(unit * 0.88, unit * 0.55)
      ..cubicTo(
        unit * 0.88,
        unit * 0.68,
        unit * 0.79,
        unit * 0.75,
        unit * 0.67,
        unit * 0.75,
      )
      ..lineTo(unit * 0.36, unit * 0.75)
      ..lineTo(unit * 0.20, unit * 0.87)
      ..lineTo(unit * 0.24, unit * 0.73)
      ..cubicTo(
        unit * 0.17,
        unit * 0.69,
        unit * 0.13,
        unit * 0.62,
        unit * 0.13,
        unit * 0.54,
      )
      ..lineTo(unit * 0.13, unit * 0.39)
      ..cubicTo(
        unit * 0.13,
        unit * 0.26,
        unit * 0.23,
        unit * 0.17,
        unit * 0.37,
        unit * 0.17,
      )
      ..close();
    canvas.drawPath(bubble, outline);

    final eyeRadius = (unit * 0.055).clamp(1.1, 2.2).toDouble();
    canvas.drawCircle(Offset(unit * 0.43, unit * 0.42), eyeRadius, eye);
    canvas.drawCircle(Offset(unit * 0.64, unit * 0.42), eyeRadius, eye);

    final smilePath = Path()
      ..moveTo(unit * 0.40, unit * 0.55)
      ..quadraticBezierTo(
        unit * 0.535,
        unit * 0.68,
        unit * 0.68,
        unit * 0.55,
      );
    canvas.drawPath(smilePath, smile);
  }

  @override
  bool shouldRepaint(covariant _PrivateChatGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
