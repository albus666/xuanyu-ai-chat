import 'package:flutter/material.dart';

/// Keeps each drag delta on the latest position, including multiple events
/// before the next frame. Releasing in the bottom zone requests confirmation.
class DraggableCallBubble extends StatefulWidget {
  const DraggableCallBubble(
      {super.key,
      required this.child,
      required this.onTap,
      required this.onDismiss});
  final Widget child;
  final VoidCallback onTap;
  final Future<void> Function() onDismiss;
  @override
  State<DraggableCallBubble> createState() => _DraggableCallBubbleState();
}

class _DraggableCallBubbleState extends State<DraggableCallBubble> {
  Offset? _position;
  Offset? _dragOrigin;
  Offset? _bubbleOrigin;
  bool _dragging = false;
  bool _confirming = false;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final p = _position ?? Offset(size.width - 76, safe.top + 80);
    final bottom = p.dy + 60 >= size.height - safe.bottom - 90;
    return Stack(children: [
      if (_dragging)
        Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 140 + safe.bottom,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                padding: EdgeInsets.only(bottom: safe.bottom),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: bottom
                      ? const [Color(0xFFF05D55), Color(0xFFD93C3C)]
                      : const [Color(0xFFE96B64), Color(0xFFD94B47)],
                )),
                child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 22),
                      SizedBox(height: 4),
                      Text('松手结束通话',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              decoration: TextDecoration.none,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            )),
      Positioned(
          key: const ValueKey('call-bubble'),
          left: p.dx,
          top: p.dy,
          child: GestureDetector(
              onTap: widget.onTap,
              onPanStart: (details) => setState(() {
                    _dragOrigin = details.globalPosition;
                    _bubbleOrigin = p;
                    _position = p;
                    _dragging = true;
                  }),
              onPanUpdate: (d) => setState(() {
                    final next = (_bubbleOrigin ?? p) +
                        (d.globalPosition - (_dragOrigin ?? d.globalPosition));
                    _position = Offset(
                        next.dx.clamp(
                            0.0, (size.width - 60).clamp(0.0, double.infinity)),
                        next.dy.clamp(
                            safe.top,
                            (size.height - safe.bottom - 60)
                                .clamp(safe.top, double.infinity)));
                  }),
              onPanCancel: () => setState(() => _dragging = false),
              onPanEnd: (_) async {
                final dropped =
                    (_position ?? p).dy + 60 >= size.height - safe.bottom - 90;
                setState(() => _dragging = false);
                if (dropped && !_confirming) {
                  _confirming = true;
                  try {
                    await widget.onDismiss();
                  } finally {
                    _confirming = false;
                    if (mounted) {
                      setState(() =>
                          _position = Offset(size.width - 76, safe.top + 80));
                    }
                  }
                }
              },
              child: widget.child)),
    ]);
  }
}
