import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 为整套 App 提供一致的左缘右滑返回手势。
///
/// 使用原始指针事件监听，不占用子页面的手势竞技场，因此不会让横向列表、
/// 轮播图或地图失去原有拖动能力；只有从屏幕左缘开始、方向明确的右滑才触发。
class GlobalEdgeBackGesture extends StatefulWidget {
  const GlobalEdgeBackGesture({
    super.key,
    required this.child,
    required this.onBack,
  });

  final Widget child;
  final FutureOr<void> Function() onBack;

  @override
  State<GlobalEdgeBackGesture> createState() => _GlobalEdgeBackGestureState();
}

class _GlobalEdgeBackGestureState extends State<GlobalEdgeBackGesture> {
  static const double _edgeWidth = 30;
  static const double _triggerDistance = 78;

  int? _pointer;
  Offset? _origin;
  Offset? _latest;
  bool _cancelled = false;
  double _progress = 0;

  void _handleDown(PointerDownEvent event) {
    if (_pointer != null || event.localPosition.dx > _edgeWidth) return;
    _pointer = event.pointer;
    _origin = event.localPosition;
    _latest = event.localPosition;
    _cancelled = false;
    _updateProgress(0);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _origin == null) return;
    _latest = event.localPosition;
    final delta = event.localPosition - _origin!;
    if (delta.dx < -8 ||
        (delta.dy.abs() > 30 && delta.dy.abs() > delta.dx.abs() * 1.12)) {
      _cancelled = true;
    }
    _updateProgress(
      _cancelled ? 0 : (delta.dx / _triggerDistance).clamp(0.0, 1.0),
    );
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer || _origin == null) return;
    _latest = event.localPosition;
    final delta = _latest! - _origin!;
    final shouldPop = !_cancelled &&
        delta.dx >= _triggerDistance &&
        delta.dx > delta.dy.abs() * 1.3;
    _reset();
    if (!shouldPop) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(Future<void>.sync(widget.onBack));
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _reset();
  }

  void _updateProgress(double value) {
    if (!mounted || (_progress - value).abs() < .01) return;
    setState(() => _progress = value);
  }

  void _reset() {
    if (!mounted) return;
    setState(() {
      _pointer = null;
      _origin = null;
      _latest = null;
      _cancelled = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final indicatorTop = ((_origin?.dy ?? 120) - 24).clamp(
      MediaQuery.paddingOf(context).top + 8,
      MediaQuery.sizeOf(context).height - 64,
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            left: -8 + 15 * _progress,
            top: indicatorTop,
            child: IgnorePointer(
              child: Opacity(
                opacity: Curves.easeOut.transform(_progress),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xEEFFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x3324BFB7)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x290E3E4D),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18 + 2 * _progress,
                    color: const Color(0xFF176C72),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
