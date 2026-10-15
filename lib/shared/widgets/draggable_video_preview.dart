import 'package:flutter/material.dart';

/// Video preview movement updates only this overlay, preserving both RTC views.
class DraggableVideoPreview extends StatefulWidget {
  const DraggableVideoPreview({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<DraggableVideoPreview> createState() => _DraggableVideoPreviewState();
}

class _DraggableVideoPreviewState extends State<DraggableVideoPreview> {
  Offset? _position;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final safe = MediaQuery.paddingOf(context);
        final maxX = (box.maxWidth - 105).clamp(0.0, double.infinity);
        final maxY =
            (box.maxHeight - 150 - safe.bottom).clamp(0.0, double.infinity);
        final minY = (safe.top + 64).clamp(0.0, maxY);
        Offset bound(Offset p) =>
            Offset(p.dx.clamp(0.0, maxX), p.dy.clamp(minY, maxY));
        final position = bound(_position ?? Offset(maxX - 16, minY + 16));
        return Stack(children: [
          Positioned(
            key: const ValueKey('local-video-preview-position'),
            left: position.dx,
            top: position.dy,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onPanUpdate: (details) => setState(() {
                _position = bound((_position ?? position) + details.delta);
              }),
              child: SizedBox(width: 105, height: 150, child: widget.child),
            ),
          ),
        ]);
      });
}
