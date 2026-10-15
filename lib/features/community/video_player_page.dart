import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 全屏播放单个网络视频，按视频分辨率/宽高比自动适配（竖屏竖着、横屏横着）
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.videoUrl, this.aiLabel = ''});

  final String videoUrl;
  final String aiLabel;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  void _initVideo() {
    final url = widget.videoUrl.trim();

    if (url.isEmpty) {
      setState(() {
        _error = '视频地址无效';
        _loading = false;
      });
      return;
    }

    final uri = Uri.tryParse(url);
    final ctrl = uri != null && ['http', 'https'].contains(uri.scheme)
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.file(
            File(uri?.scheme == 'file' ? uri!.toFilePath() : url));
    _controller = ctrl;
    ctrl.initialize().then((_) {
      if (mounted) {
        ctrl.addListener(_onVideoUpdate);
        final size = ctrl.value.size;
        final ar = ctrl.value.aspectRatio;
        if (size.width > 0 && size.height > 0) {
          debugPrint(
              '[VideoPlayer] 原始视频分辨率: ${size.width.toInt()} x ${size.height.toInt()}, aspectRatio: $ar');
        }
        setState(() => _loading = false);
        ctrl.play();
      }
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _error = '视频暂时无法播放';
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: widget.aiLabel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(widget.aiLabel,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)))),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              _buildError()
            else if (_loading)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white))
            else if (_controller != null && _controller!.value.isInitialized)
              _buildVideo(),
            if (_controller != null && _controller!.value.isInitialized) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showControls = true;
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: (_controller!.value.isPlaying && !_showControls)
                          ? 0.0
                          : 0.85,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        color: Colors.white,
                        size: 72,
                      ),
                    ),
                  ),
                ),
              ),
              _buildProgressBar(),
            ],
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black38,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: Colors.white70),
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final ctrl = _controller!;
    final duration = ctrl.value.duration;
    final position = ctrl.value.position;
    if (duration.inMilliseconds <= 0) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white38,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: position.inMilliseconds
                  .clamp(0, duration.inMilliseconds)
                  .toDouble(),
              max: duration.inMilliseconds.toDouble(),
              onChanged: (v) => ctrl.seekTo(Duration(milliseconds: v.toInt())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(_formatDuration(duration),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 按视频 aspectRatio 在可用空间内等比适配，不拉伸（直接信任解码器给出的比例）
  Widget _buildVideo() {
    final ctrl = _controller!;
    final ar = ctrl.value.aspectRatio;
    if (ar <= 0) {
      return Center(child: VideoPlayer(ctrl));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        double w;
        double h;
        if (constraints.maxWidth / constraints.maxHeight > ar) {
          h = constraints.maxHeight;
          w = h * ar;
        } else {
          w = constraints.maxWidth;
          h = w / ar;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: VideoPlayer(ctrl),
          ),
        );
      },
    );
  }
}
