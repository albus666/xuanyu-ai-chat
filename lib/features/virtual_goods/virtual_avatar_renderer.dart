import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'virtual_avatar_spec.dart';

enum VirtualAvatarPaintLayer {
  all,
  background,
  base,
  features,
  details,
  adornments,
  accessory,
}

/// 免费初始款的原创线描人文渲染器。
///
/// 付费成品头像直接使用独立完整资源，不经过本绘制器。这里所有部件共享同一
/// 100×100 坐标系，保证脸型、眉眼、发型、服装和背景任意组合都不会错位。
class VirtualAvatarPainter extends CustomPainter {
  VirtualAvatarPainter(
    Map<String, dynamic> source, {
    this.layer = VirtualAvatarPaintLayer.all,
  }) : config = VirtualAvatarSpec.normalize(source);

  final Map<String, dynamic> config;
  final VirtualAvatarPaintLayer layer;

  int _v(String key) => (config[key] as num?)?.toInt() ?? 0;
  String get _presentation => config['presentation']?.toString() ?? 'neutral';

  static const _backgrounds = <List<Color>>[
    [Color(0xFFF7F0E5), Color(0xFFD9E0D2)],
    [Color(0xFFF3E8D9), Color(0xFFD4DFD7)],
    [Color(0xFFF8E9E2), Color(0xFFE6C7BC)],
    [Color(0xFFF0E9F1), Color(0xFFD4C8D8)],
    [Color(0xFFEAF0F3), Color(0xFFBFCED7)],
    [Color(0xFFF6EBD7), Color(0xFFE4C685)],
    [Color(0xFFEAF1EE), Color(0xFFB9CFCA)],
    [Color(0xFFF6E9EC), Color(0xFFDDBFC5)],
    [Color(0xFFECE9E6), Color(0xFFC8C2BD)],
    [Color(0xFFF0F1E7), Color(0xFFC8D0AF)],
    [Color(0xFFE6ECE9), Color(0xFF99B1A9)],
    [Color(0xFFEAE7EC), Color(0xFFAAA1B2)],
  ];
  static const _skins = <Color>[
    Color(0xFFFFE9D7),
    Color(0xFFFFDCC2),
    Color(0xFFF3C6A6),
    Color(0xFFE6B18C),
    Color(0xFFD99A72),
    Color(0xFFC5805D),
    Color(0xFFA7654B),
    Color(0xFF7D4938),
  ];
  static const _hairColors = <Color>[
    Color(0xFF252321),
    Color(0xFF45352E),
    Color(0xFF674938),
    Color(0xFF93654A),
    Color(0xFFC3A282),
    Color(0xFF6A5750),
    Color(0xFF3E4B59),
    Color(0xFF59435E),
    Color(0xFF365F59),
    Color(0xFFA85D64),
    Color(0xFFC8C9CA),
    Color(0xFFE5DCCE),
  ];
  static const _outfitColors = <Color>[
    Color(0xFF365F55),
    Color(0xFF394B5B),
    Color(0xFF665269),
    Color(0xFF874E42),
    Color(0xFF56738A),
    Color(0xFFA17735),
    Color(0xFF343434),
    Color(0xFF68745D),
    Color(0xFFC77E74),
    Color(0xFF74699B),
    Color(0xFFA88462),
    Color(0xFFE6DDD0),
  ];

  Color get _skin => _skins[_v('skin')];
  Color get _hair => _hairColors[_v('hairColor')];
  Color get _outfit => _outfitColors[_v('outfitColor')];
  Color get _ink =>
      _v('skin') >= 6 ? const Color(0xFF3D302B) : const Color(0xFF59463C);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = math.min(size.width, size.height) / 100;
    canvas.translate(
      (size.width - 100 * scale) / 2,
      (size.height - 100 * scale) / 2,
    );
    canvas.scale(scale);

    if (layer == VirtualAvatarPaintLayer.all ||
        layer == VirtualAvatarPaintLayer.background ||
        layer == VirtualAvatarPaintLayer.base) {
      _drawBackground(canvas);
    }
    if (layer == VirtualAvatarPaintLayer.all ||
        layer == VirtualAvatarPaintLayer.base) {
      _drawOutfit(canvas);
    }
    if (layer == VirtualAvatarPaintLayer.all) {
      _drawNeck(canvas);
      _drawEars(canvas);
      _drawFace(canvas);
      _drawHairBack(canvas);
      _drawHairFront(canvas);
    }
    if (layer == VirtualAvatarPaintLayer.all ||
        layer == VirtualAvatarPaintLayer.features) {
      _drawBrows(canvas);
      _drawEyes(canvas);
    }
    if (layer == VirtualAvatarPaintLayer.all ||
        layer == VirtualAvatarPaintLayer.features ||
        layer == VirtualAvatarPaintLayer.details) {
      _drawNose(canvas);
      _drawMouth(canvas);
    }
    if (layer != VirtualAvatarPaintLayer.base &&
        layer != VirtualAvatarPaintLayer.background &&
        layer != VirtualAvatarPaintLayer.accessory) {
      _drawGlasses(canvas);
    }
    if (layer != VirtualAvatarPaintLayer.base &&
        layer != VirtualAvatarPaintLayer.background) {
      _drawAccessory(canvas);
    }
    canvas.restore();
  }

  Paint _line({Color? color, double width = .7}) => Paint()
    ..color = color ?? _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _drawBackground(Canvas canvas) {
    final palette = _backgrounds[_v('background')];
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette,
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );

    final index = _v('background');
    final sun = index.isEven ? const Offset(72, 22) : const Offset(24, 25);
    final sunColor = index % 3 == 0
        ? const Color(0x99B98C42)
        : index % 3 == 1
            ? const Color(0x77E8DFCF)
            : const Color(0x77A36351);
    canvas.drawCircle(sun, 10 + (index % 3) * 1.5, Paint()..color = sunColor);

    final far = Path()
      ..moveTo(0, 67)
      ..quadraticBezierTo(15, 48 + index % 5, 30, 62)
      ..quadraticBezierTo(43, 76, 58, 56 - index % 4)
      ..quadraticBezierTo(75, 42, 100, 63)
      ..lineTo(100, 100)
      ..lineTo(0, 100)
      ..close();
    canvas.drawPath(
      far,
      Paint()..color = Color.lerp(palette.last, const Color(0xFF6D786A), .26)!,
    );
    final near = Path()
      ..moveTo(0, 79)
      ..quadraticBezierTo(20, 63, 40, 76)
      ..quadraticBezierTo(59, 88, 77, 65)
      ..quadraticBezierTo(89, 55, 100, 71)
      ..lineTo(100, 100)
      ..lineTo(0, 100)
      ..close();
    canvas.drawPath(
      near,
      Paint()
        ..color = Color.lerp(palette.last, const Color(0xFF3D514A), .44)!
            .withValues(alpha: .72),
    );
    for (final y in [30.0, 35.5]) {
      canvas.drawPath(
        Path()
          ..moveTo(index.isEven ? 4 : 55, y)
          ..cubicTo(25, y - 4, 33, y + 4, index.isEven ? 51 : 96, y - 1),
        _line(color: const Color(0x66A98A5A), width: .45),
      );
    }
  }

  void _drawOutfit(Canvas canvas) {
    final outfit = _v('outfit');
    final base = outfit % 6;
    final detail = outfit ~/ 6;
    final male = _presentation == 'male';
    final shoulder = male ? 7.0 : 10.0;
    final top = base == 1 ? 77.0 : 75.0;
    final body = Path()
      ..moveTo(shoulder, 100)
      ..cubicTo(12, 84, 27, top, 40, 75)
      ..quadraticBezierTo(50, 80, 60, 75)
      ..cubicTo(73, top, 88, 84, 100 - shoulder, 100)
      ..close();
    final fill = Color.lerp(_outfit, const Color(0xFFF2E8D9), .12)!;
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(body, _line(width: .85));

    final light = Color.lerp(fill, Colors.white, .48)!;
    final dark = Color.lerp(fill, _ink, .30)!;
    if (base == 0) {
      canvas.drawPath(
        Path()
          ..moveTo(39, 75)
          ..lineTo(50, 87)
          ..lineTo(61, 75),
        _line(color: light, width: 2.4),
      );
    } else if (base == 1) {
      canvas.drawArc(
        const Rect.fromLTWH(39, 72.5, 22, 15),
        .05,
        math.pi - .1,
        false,
        _line(color: dark, width: 2.2),
      );
    } else if (base == 2) {
      canvas.drawPath(
        Path()
          ..moveTo(38, 75)
          ..lineTo(46.5, 84)
          ..lineTo(50, 77)
          ..lineTo(53.5, 84)
          ..lineTo(62, 75),
        Paint()..color = light.withValues(alpha: .86),
      );
      canvas.drawLine(const Offset(50, 78), const Offset(50, 100),
          _line(color: dark, width: .55));
    } else if (base == 3) {
      canvas.drawPath(
        Path()
          ..moveTo(38, 76)
          ..quadraticBezierTo(50, 87, 62, 76),
        _line(color: dark, width: 3),
      );
      canvas.drawLine(const Offset(50, 84), const Offset(50, 100),
          _line(color: light, width: .6));
    } else if (base == 4) {
      canvas.drawPath(
        Path()
          ..moveTo(37, 75)
          ..lineTo(46, 88)
          ..lineTo(50, 79)
          ..lineTo(54, 88)
          ..lineTo(63, 75),
        _line(color: light, width: 1.4),
      );
      for (final y in [86.0, 92.0]) {
        canvas.drawCircle(Offset(50, y), .75, Paint()..color = light);
      }
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(37, 75)
          ..quadraticBezierTo(50, 91, 63, 75),
        _line(color: const Color(0xFFCFAC65), width: 1.5),
      );
      canvas.drawCircle(
          const Offset(50, 86), 1.2, Paint()..color = const Color(0xFFCFAC65));
    }
    if (detail == 1) {
      canvas.drawLine(const Offset(22, 88), const Offset(78, 88),
          _line(color: light.withValues(alpha: .65), width: .75));
    } else if (detail == 2) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(68, 84, 7, 7),
          const Radius.circular(1.5),
        ),
        Paint()..color = dark.withValues(alpha: .55),
      );
    }
  }

  void _drawNeck(Canvas canvas) {
    final width = _presentation == 'male' ? 14.0 : 11.0;
    final rect = Rect.fromCenter(
      center: const Offset(50, 74),
      width: width,
      height: 16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = _skin,
    );
    canvas.drawLine(Offset(rect.left, 69), Offset(rect.left + 1, 77),
        _line(color: _ink.withValues(alpha: .42), width: .45));
    canvas.drawLine(Offset(rect.right, 69), Offset(rect.right - 1, 77),
        _line(color: _ink.withValues(alpha: .42), width: .45));
  }

  void _drawHairBack(Canvas canvas) {
    final index = _v('hair');
    final base = index % 8;
    final length = index ~/ 8;
    if (length == 0 && base < 5) return;
    final bottom = length == 2 ? 91.0 : 74.0;
    final back = Path()
      ..moveTo(26, 31)
      ..cubicTo(18, 47, 21, bottom - 3, 29, bottom)
      ..quadraticBezierTo(39, bottom + 4, 45, bottom - 2)
      ..lineTo(55, bottom - 2)
      ..quadraticBezierTo(63, bottom + 4, 72, bottom)
      ..cubicTo(80, bottom - 3, 82, 47, 74, 31)
      ..close();
    canvas.drawPath(back, Paint()..color = _hair);
    if (base == 6) {
      canvas.drawOval(
          const Rect.fromLTWH(62, 14, 17, 14), Paint()..color = _hair);
    } else if (base == 7) {
      canvas.drawOval(
          const Rect.fromLTWH(20, 33, 13, 17), Paint()..color = _hair);
      canvas.drawOval(
          const Rect.fromLTWH(67, 33, 13, 17), Paint()..color = _hair);
    }
  }

  void _drawEars(Canvas canvas) {
    final ear = Paint()..color = _skin;
    canvas.drawOval(const Rect.fromLTWH(23, 42, 7, 11), ear);
    canvas.drawOval(const Rect.fromLTWH(70, 42, 7, 11), ear);
    canvas.drawArc(const Rect.fromLTWH(25, 45, 3, 5), -1.3, 2.3, false,
        _line(color: _ink.withValues(alpha: .42), width: .45));
    canvas.drawArc(const Rect.fromLTWH(72, 45, 3, 5), 2.1, 2.3, false,
        _line(color: _ink.withValues(alpha: .42), width: .45));
  }

  void _drawFace(Canvas canvas) {
    final index = _v('face');
    final widths = [43.0, 45.0, 47.0, 49.0, 44.0, 46.0, 48.0, 50.0];
    final chins = [72.0, 73.5, 74.0, 73.0, 75.0, 74.5, 72.5, 74.0];
    final width = widths[index] +
        (_presentation == 'male' ? 1.6 : 0) +
        (_presentation == 'female' ? -1.0 : 0);
    final left = 50 - width / 2;
    final right = 50 + width / 2;
    final jawPull = [4.5, 6.0, 7.5, 9.0, 5.2, 6.8, 8.3, 9.7][index];
    final path = Path()
      ..moveTo(left + 7, 25)
      ..quadraticBezierTo(50, 18.5, right - 7, 25)
      ..cubicTo(right + 1, 36, right + 1, 53, right - 4, 61)
      ..cubicTo(
          right - 7, 67, 55 + jawPull * .18, chins[index], 50, chins[index])
      ..cubicTo(45 - jawPull * .18, chins[index], left + 7, 67, left + 4, 61)
      ..cubicTo(left - 1, 53, left - 1, 36, left + 7, 25)
      ..close();
    final fill = Color.lerp(_skin, const Color(0xFFFFF6EA), .08)!;
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, _line(width: .72));

    final shade = Color.lerp(_skin, const Color(0xFF9C5F4B), .22)!;
    canvas.drawPath(
      Path()
        ..moveTo(left + 4, 55)
        ..quadraticBezierTo(left + 9, 67, 43, 71),
      _line(color: shade.withValues(alpha: .28), width: 1.1),
    );
    canvas.drawOval(const Rect.fromLTWH(29, 54, 7.5, 3.6),
        Paint()..color = const Color(0x12D65F68));
    canvas.drawOval(const Rect.fromLTWH(63.5, 54, 7.5, 3.6),
        Paint()..color = const Color(0x12D65F68));
  }

  void _drawHairFront(Canvas canvas) {
    final index = _v('hair');
    final base = index % 8;
    final crown = Path()
      ..moveTo(25, 39)
      ..cubicTo(20, 22, 30, 11.5, 49, 12.5)
      ..cubicTo(70, 10.5, 80, 23, 75, 40)
      ..quadraticBezierTo(69, 30, 62, 27)
      ..quadraticBezierTo(48, 34, 25, 39)
      ..close();
    canvas.drawPath(crown, Paint()..color = _hair);

    final fringe = Path()..moveTo(25, 34);
    switch (base) {
      case 0:
        fringe
          ..cubicTo(34, 20, 44, 22, 49, 31)
          ..cubicTo(56, 20, 67, 23, 75, 35)
          ..cubicTo(64, 31, 58, 36, 54, 42)
          ..cubicTo(45, 31, 35, 31, 25, 34);
      case 1:
        fringe
          ..cubicTo(38, 18, 52, 19, 57, 28)
          ..cubicTo(64, 27, 70, 30, 75, 36)
          ..cubicTo(61, 31, 52, 36, 47, 43)
          ..cubicTo(41, 31, 33, 31, 25, 34);
      case 2:
        fringe
          ..quadraticBezierTo(36, 24, 42, 40)
          ..quadraticBezierTo(49, 25, 54, 40)
          ..quadraticBezierTo(62, 24, 75, 35)
          ..quadraticBezierTo(53, 30, 25, 34);
      case 3:
        fringe
          ..lineTo(37, 22)
          ..lineTo(43, 36)
          ..lineTo(51, 20)
          ..lineTo(58, 36)
          ..lineTo(68, 23)
          ..lineTo(75, 36)
          ..quadraticBezierTo(50, 29, 25, 34);
      case 4:
        fringe
          ..cubicTo(39, 18, 58, 17, 73, 28)
          ..cubicTo(63, 31, 55, 36, 52, 43)
          ..cubicTo(45, 28, 34, 29, 25, 34);
      case 5:
        fringe
          ..cubicTo(34, 20, 43, 23, 49, 30)
          ..cubicTo(59, 18, 69, 24, 75, 35)
          ..cubicTo(64, 30, 56, 34, 50, 40)
          ..cubicTo(41, 29, 33, 30, 25, 34);
      case 6:
        fringe
          ..cubicTo(38, 20, 46, 23, 50, 37)
          ..cubicTo(57, 21, 67, 25, 75, 35)
          ..cubicTo(56, 29, 39, 29, 25, 34);
      default:
        fringe
          ..cubicTo(35, 19, 45, 21, 49, 33)
          ..cubicTo(58, 18, 69, 24, 75, 35)
          ..cubicTo(57, 29, 39, 29, 25, 34);
    }
    fringe.close();
    canvas.drawPath(fringe, Paint()..color = _hair);

    final highlight = Color.lerp(_hair, const Color(0xFFE5C9A7), .30)!;
    final shadow = Color.lerp(_hair, const Color(0xFF171514), .34)!;
    for (var i = 0; i < 7; i++) {
      final x = 30.0 + i * 6.7;
      final sweep = base.isEven ? -1.0 : 1.0;
      canvas.drawPath(
        Path()
          ..moveTo(x, 19 + (i % 3))
          ..quadraticBezierTo(x + sweep * 3, 27, x + sweep * 5, 34 + i * .35),
        _line(
          color: (i.isEven ? highlight : shadow).withValues(alpha: .58),
          width: .48,
        ),
      );
    }
  }

  void _drawBrows(Canvas canvas) {
    final index = _v('brows');
    final shape = index % 4;
    final weight =
        .75 + (index ~/ 4) * .34 + (_presentation == 'male' ? .2 : 0);
    final rise = [0.0, -1.2, .9, -.4][shape];
    final paint = _line(color: _hair.withValues(alpha: .86), width: weight);
    canvas.drawPath(
      Path()
        ..moveTo(33, 39.5 + rise)
        ..quadraticBezierTo(38, 37.5 - rise, 44, 39 + (shape == 2 ? .8 : 0)),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(56, 39 + (shape == 2 ? .8 : 0))
        ..quadraticBezierTo(62, 37.5 - rise, 67, 39.5 + rise),
      paint,
    );
  }

  void _drawEyes(Canvas canvas) {
    final index = _v('eyes');
    final shape = index % 4;
    final size = .94 + (index ~/ 4) * .08;
    final iris = Color.lerp(_hair, const Color(0xFF735B49), .48)!;
    for (final side in [-1.0, 1.0]) {
      final cx = 50 + side * 10.7;
      final width = (shape == 2 ? 10.6 : 9.8) * size;
      final height = (shape == 0
              ? 4.2
              : shape == 3
                  ? 6.2
                  : 5.2) *
          size;
      final rect = Rect.fromCenter(
        center: Offset(cx, 46.2),
        width: width,
        height: height,
      );
      final eye = Path()
        ..moveTo(rect.left, rect.center.dy)
        ..quadraticBezierTo(cx, rect.top, rect.right, rect.center.dy)
        ..quadraticBezierTo(cx, rect.bottom, rect.left, rect.center.dy)
        ..close();
      canvas.drawPath(eye, Paint()..color = const Color(0xFFFFFCF6));
      canvas.drawPath(eye, _line(width: 1.0));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, 46.4),
          width: height * .58,
          height: height * .78,
        ),
        Paint()..color = iris,
      );
      canvas.drawCircle(Offset(cx, 46.4), height * .18, Paint()..color = _ink);
      canvas.drawCircle(
          Offset(cx - .55, 45.8), .35, Paint()..color = Colors.white);
      if (_presentation == 'female' && shape.isOdd) {
        canvas.drawLine(Offset(rect.right - .2, rect.center.dy),
            Offset(rect.right + 1.3, rect.center.dy - .8), _line(width: .55));
      }
    }
  }

  void _drawNose(Canvas canvas) {
    final index = _v('nose');
    final shade = Color.lerp(_skin, const Color(0xFF795044), .54)!;
    final paint = _line(color: shade.withValues(alpha: .68), width: .62);
    final x = index.isEven ? 49.7 : 50.3;
    canvas.drawPath(
      Path()
        ..moveTo(x, 49.5)
        ..quadraticBezierTo(x - 1.2 + (index % 3) * .45, 55, 50.5, 57.2),
      paint,
    );
    if (index >= 4) {
      canvas.drawArc(const Rect.fromLTWH(47.5, 55, 5, 3), .25, 2.6, false,
          _line(color: shade.withValues(alpha: .46), width: .45));
    }
  }

  void _drawMouth(Canvas canvas) {
    final index = _v('mouth');
    final shape = index % 6;
    final strong = index ~/ 6 == 1;
    const lip = Color(0xFFA96062);
    final paint = _line(color: lip, width: strong ? .95 : .68);
    if (shape == 0) {
      canvas.drawPath(
          Path()
            ..moveTo(46.5, 63.4)
            ..quadraticBezierTo(50, 64, 53.5, 63.4),
          paint);
    } else if (shape == 1) {
      canvas.drawPath(
          Path()
            ..moveTo(45.8, 63)
            ..quadraticBezierTo(50, 66, 54.2, 63),
          paint);
    } else if (shape == 2) {
      canvas.drawLine(const Offset(46, 63.8), const Offset(54, 63.8), paint);
    } else if (shape == 3) {
      canvas.drawOval(const Rect.fromLTWH(47, 61.8, 6, 3.8),
          Paint()..color = lip.withValues(alpha: .72));
    } else if (shape == 4) {
      canvas.drawPath(
          Path()
            ..moveTo(45.5, 63.4)
            ..quadraticBezierTo(48, 61.5, 50, 63.1)
            ..quadraticBezierTo(52, 61.5, 54.5, 63.4),
          paint);
    } else {
      canvas.drawPath(
          Path()
            ..moveTo(46, 63.2)
            ..quadraticBezierTo(50, 67, 54, 63.2),
          paint);
    }
  }

  void _drawGlasses(Canvas canvas) {
    final index = _v('glasses');
    if (index == 0) return;
    final colors = [
      const Color(0xFF383735),
      const Color(0xFF9A7544),
      const Color(0xFF70737A),
    ];
    final paint = _line(
      color: colors[(index - 1) % colors.length],
      width: index > 6 ? 1.25 : .82,
    );
    final round = index % 3 == 1;
    if (round) {
      canvas.drawOval(const Rect.fromLTWH(32.7, 41.7, 13, 10), paint);
      canvas.drawOval(const Rect.fromLTWH(54.3, 41.7, 13, 10), paint);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(32.5, 42, 13.5, 9.3),
              Radius.circular(index % 3 == 2 ? 3 : 1)),
          paint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(54, 42, 13.5, 9.3),
              Radius.circular(index % 3 == 2 ? 3 : 1)),
          paint);
    }
    canvas.drawLine(const Offset(46, 45.6), const Offset(54, 45.6), paint);
  }

  void _drawAccessory(Canvas canvas) {
    final index = _v('accessory');
    if (index == 0) return;
    const gold = Color(0xFFB98A45);
    if (index == 1) {
      canvas.drawCircle(const Offset(74, 49), 1.2, Paint()..color = gold);
    } else if (index == 2) {
      canvas.drawCircle(const Offset(74, 50), 1, Paint()..color = gold);
      canvas.drawLine(const Offset(74, 51), const Offset(74, 56),
          _line(color: gold, width: .7));
      canvas.drawCircle(
          const Offset(74, 57), 1.2, Paint()..color = const Color(0xFF47746B));
    } else if (index == 3) {
      canvas.drawArc(const Rect.fromLTWH(38, 76, 24, 16), .2, 2.75, false,
          _line(color: gold, width: .65));
      canvas.drawCircle(const Offset(50, 88), 1.5, Paint()..color = gold);
    } else if (index == 4) {
      _drawStar(canvas, const Offset(70, 21), 3, gold);
    } else if (index == 5) {
      canvas.drawCircle(
          const Offset(70, 23), 2.7, Paint()..color = const Color(0xFFC97674));
      canvas.drawCircle(
          const Offset(75, 25), 1.8, Paint()..color = const Color(0xFFD9A09C));
    } else if (index == 6) {
      canvas.drawLine(const Offset(65, 18), const Offset(77, 23),
          _line(color: gold, width: 1.3));
    } else if (index == 7) {
      final horn = _line(color: const Color(0xFF547A72), width: 1.15);
      canvas.drawPath(
          Path()
            ..moveTo(28, 24)
            ..quadraticBezierTo(21, 18, 24, 12)
            ..quadraticBezierTo(28, 17, 31, 20),
          horn);
      canvas.drawPath(
          Path()
            ..moveTo(72, 24)
            ..quadraticBezierTo(79, 18, 76, 12)
            ..quadraticBezierTo(72, 17, 69, 20),
          horn);
    } else if (index == 8) {
      canvas.drawArc(const Rect.fromLTWH(31, 15, 38, 22), math.pi, math.pi,
          false, _line(color: gold, width: 1.1));
    } else if (index == 9) {
      final ribbon = _line(color: const Color(0xFF657981), width: 2.1);
      canvas.drawArc(const Rect.fromLTWH(27, 14.5, 46, 28), math.pi + .15,
          math.pi - .3, false, ribbon);
      canvas.drawPath(
          Path()
            ..moveTo(70, 24)
            ..quadraticBezierTo(77, 28, 75, 36),
          _line(color: const Color(0xFF657981), width: 1.25));
    } else if (index == 10) {
      canvas.drawOval(const Rect.fromLTWH(35, 9.5, 30, 7),
          _line(color: const Color(0xFFD5B15F), width: 1.05));
    } else {
      const bow = Color(0xFF8E667C);
      canvas.drawOval(const Rect.fromLTWH(65, 17, 8, 6), Paint()..color = bow);
      canvas.drawOval(const Rect.fromLTWH(74, 17, 8, 6), Paint()..color = bow);
      canvas.drawCircle(const Offset(73.5, 20), 1.7,
          Paint()..color = const Color(0xFFB38C55));
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? radius : radius * .34;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant VirtualAvatarPainter oldDelegate) =>
      oldDelegate.layer != layer ||
      oldDelegate.config.toString() != config.toString();
}
