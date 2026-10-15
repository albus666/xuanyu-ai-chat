import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'video_player_page.dart';

/// Display a decoded, muted frame of the selected file before publishing.
class LocalVideoPreview extends StatefulWidget {
  const LocalVideoPreview({super.key, required this.path, this.radius = 14});

  final String path;
  final double radius;

  @override
  State<LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<LocalVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _load();
    }
  }

  Future<void> _load() async {
    _ready = false;
    _failed = false;
    final uri = Uri.tryParse(widget.path);
    final controller = VideoPlayerController.file(
      File(uri?.scheme == 'file' ? uri!.toFilePath() : widget.path),
    );
    _controller = controller;
    bool current() => mounted && identical(_controller, controller);
    try {
      await controller.initialize();
      if (!current()) return;
      if (controller.value.size.width <= 0 ||
          controller.value.size.height <= 0) {
        throw const FormatException('Invalid video dimensions');
      }
      await controller.setVolume(0);
      if (!current()) return;
      // Move past a common black opening frame, without starting playback.
      final duration = controller.value.duration.inMilliseconds;
      await controller
          .seekTo(Duration(milliseconds: duration > 500 ? 500 : duration ~/ 2));
      if (!current()) return;
      setState(() => _ready = true);
    } catch (_) {
      if (current()) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Material(
        color: const Color(0xFF292D35),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => VideoPlayerPage(videoUrl: widget.path),
          )),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && controller != null)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              if (!_ready && !_failed)
                const Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)))
              else
                Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white, size: 48),
                  if (_failed)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('画面加载失败，点击重试播放',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white, fontSize: 12))),
                ])),
            ],
          ),
        ),
      ),
    );
  }
}
