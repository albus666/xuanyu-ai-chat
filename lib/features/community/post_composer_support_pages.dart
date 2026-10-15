import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'post_component_sheet.dart';
import 'local_video_preview.dart';
import 'post_publish_settings_page.dart';

const _accent = AppColors.primary;
const _ink = Color(0xFF25272B);
const _muted = Color(0xFFB5B8BE);

class ComposerMediaSelection {
  const ComposerMediaSelection({
    this.imagePaths = const [],
    this.videoPath,
  });

  final List<String> imagePaths;
  final String? videoPath;
}

/// 参考系统相册的轻量选择页；实际媒体授权与选择仍交给系统选择器，
/// 因而不会越权扫描用户未选中的照片。
class PostAlbumPickerPage extends StatefulWidget {
  const PostAlbumPickerPage({
    super.key,
    this.initialImages = const [],
    this.initialVideo,
  });

  final List<String> initialImages;
  final String? initialVideo;

  @override
  State<PostAlbumPickerPage> createState() => _PostAlbumPickerPageState();
}

class _PostAlbumPickerPageState extends State<PostAlbumPickerPage> {
  final _images = <String>[];
  String? _video;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _images.addAll(widget.initialImages);
    _video = widget.initialVideo;
  }

  Future<bool> _galleryPermission() async {
    if (Platform.isIOS) {
      final value = await Permission.photos.request();
      return value.isGranted || value.isLimited;
    }
    return true;
  }

  Future<void> _pickImages() async {
    if (!await _galleryPermission()) {
      if (mounted) showAppToast(context, '需要相册权限才能选择图片');
      return;
    }
    final values =
        await ImagePicker().pickMultiImage(maxWidth: 1440, imageQuality: 88);
    if (!mounted || values.isEmpty) return;
    setState(() {
      _video = null;
      for (final value in values) {
        if (_images.length >= 9) break;
        if (!_images.contains(value.path)) _images.add(value.path);
      }
    });
  }

  Future<void> _pickVideo() async {
    if (!await _galleryPermission()) {
      if (mounted) showAppToast(context, '需要相册权限才能选择视频');
      return;
    }
    final value = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (!mounted || value == null) return;
    setState(() {
      _images.clear();
      _video = value.path;
    });
  }

  Future<void> _camera() async {
    if (!(await Permission.camera.request()).isGranted) {
      if (mounted) showAppToast(context, '需要相机权限才能拍摄');
      return;
    }
    final value = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1440,
      imageQuality: 88,
    );
    if (!mounted || value == null) return;
    setState(() {
      _video = null;
      if (_images.length < 9) _images.add(value.path);
    });
  }

  void _done() {
    Navigator.of(context).pop(ComposerMediaSelection(
      imagePaths: List<String>.from(_images),
      videoPath: _video,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final assets = <String>[
      if (_filter != 2) ..._images,
      if (_filter != 1 && _video != null) _video!,
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: _ink, size: 32),
        ),
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('相机胶卷',
                style: TextStyle(
                    color: _ink, fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(width: 5),
            Icon(Icons.keyboard_arrow_down_rounded, color: _ink),
          ],
        ),
        actions: [
          TextButton(
            onPressed: (_images.isEmpty && _video == null) ? null : _done,
            child: const Text('完成', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 7),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                _filterTab(0, '全部'),
                _filterTab(1, '图片'),
                _filterTab(2, '视频'),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(5),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: assets.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _mediaAction(
                    Icons.photo_camera_outlined,
                    '玄遇相机',
                    _camera,
                  );
                }
                if (index == 1) {
                  return _mediaAction(
                    _filter == 2
                        ? Icons.video_library_outlined
                        : Icons.photo_library_outlined,
                    _filter == 2 ? '选择视频' : '打开相册',
                    _filter == 2 ? _pickVideo : _pickImages,
                  );
                }
                final path = assets[index - 2];
                final isVideo = path == _video;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    isVideo
                        ? Container(
                            color: const Color(0xFF31343C),
                            child: const Icon(Icons.play_circle_fill_rounded,
                                color: Colors.white, size: 44),
                          )
                        : Image.file(File(path), fit: BoxFit.cover),
                    Positioned(
                      right: 7,
                      top: 7,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          if (isVideo) {
                            _video = null;
                          } else {
                            _images.remove(path);
                          }
                        }),
                        child: Container(
                          width: 25,
                          height: 25,
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _ComposerModeBar(selected: 1),
        ],
      ),
    );
  }

  Widget _filterTab(int value, String label) {
    final selected = _filter == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filter = value),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: TextStyle(
                  color: selected ? _ink : _muted,
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 26 : 0,
              height: 3,
              decoration: BoxDecoration(
                  color: _accent, borderRadius: BorderRadius.circular(3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: ColoredBox(
        color: const Color(0xFFF6F6F6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFB8B9BC), size: 42),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(color: Color(0xFFB8B9BC), fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class AudioComposerResult {
  const AudioComposerResult(
      {required this.path, required this.durationSeconds});

  final String path;
  final int durationSeconds;
}

class PostAudioComposerPage extends StatefulWidget {
  const PostAudioComposerPage({super.key});

  @override
  State<PostAudioComposerPage> createState() => _PostAudioComposerPageState();
}

class _PostAudioComposerPageState extends State<PostAudioComposerPage> {
  static const _channel = MethodChannel('xuanyu/audio_recorder');
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  String? _path;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) _channel.invokeMethod<void>('cancelRecording');
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      try {
        final path = await _channel.invokeMethod<String>('stopRecording');
        if (!mounted) return;
        _timer?.cancel();
        setState(() {
          _recording = false;
          _path = path;
        });
      } on PlatformException catch (error) {
        if (mounted) showAppToast(context, error.message ?? '录音保存失败');
      }
      return;
    }
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (mounted) showAppToast(context, '需要麦克风权限才能录音');
      return;
    }
    try {
      await _channel.invokeMethod<void>('startRecording');
      if (!mounted) return;
      setState(() {
        _recording = true;
        _seconds = 0;
        _path = null;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_seconds >= 299) {
          _toggleRecord();
        } else {
          setState(() => _seconds++);
        }
      });
    } on MissingPluginException {
      if (mounted) showAppToast(context, '当前设备暂不支持录音发布');
    } on PlatformException catch (error) {
      if (mounted) showAppToast(context, error.message ?? '无法开始录音');
    }
  }

  String get _duration =>
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  void _done() {
    if (_path == null) return;
    Navigator.of(context).pop(
      AudioComposerResult(path: _path!, durationSeconds: _seconds),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: _ink, size: 32),
        ),
        centerTitle: true,
        title: const Text('录制声音',
            style: TextStyle(
                color: _ink, fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _path == null ? null : _done,
            child: const Text('完成', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 7),
        ],
      ),
      body: Column(
        children: [
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recording
                  ? const Color(0xFFFFEFF1)
                  : const Color(0xFFEAFBFA),
              boxShadow: [
                BoxShadow(
                  color: (_recording ? const Color(0xFFFF6074) : _accent)
                      .withValues(alpha: 0.15),
                  blurRadius: 38,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _duration,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 39,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 44),
          Text(
            _recording
                ? '正在聆听，点击结束'
                : _path == null
                    ? '点击开始录音，最长 5 分钟'
                    : '录音已保存，可重新录制',
            style: const TextStyle(color: _muted, fontSize: 15),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _toggleRecord,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording ? const Color(0xFFFF5369) : _accent,
              ),
              child: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
          const Spacer(),
          _ComposerModeBar(selected: 2),
        ],
      ),
    );
  }
}

class PostPreviewPage extends StatelessWidget {
  const PostPreviewPage({
    super.key,
    required this.content,
    required this.images,
    this.videoPath,
    this.audioPath,
    this.audioSeconds = 0,
    this.location,
    this.component,
    required this.settings,
  });

  final String content;
  final List<File> images;
  final String? videoPath;
  final String? audioPath;
  final int audioSeconds;
  final String? location;
  final PostComponentSelection? component;
  final PostPublishSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: _ink, size: 31),
        ),
        centerTitle: true,
        title: const Text('作品预览',
            style: TextStyle(
                color: _ink, fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF8BE1DC), Color(0xFFE9A7BE)],
                  ),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('我',
                        style: TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      ['刚刚', if (location?.isNotEmpty == true) location!]
                          .join(' · '),
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(settings.visibilityLabel,
                    style: const TextStyle(color: _accent, fontSize: 12)),
              ),
            ],
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 22),
            _PreviewImages(images),
          ] else if (videoPath != null) ...[
            const SizedBox(height: 22),
            SizedBox(
              height: 280,
              child: LocalVideoPreview(path: videoPath!, radius: 18),
            ),
          ] else if (audioPath != null) ...[
            const SizedBox(height: 22),
            _AudioPreviewCard(seconds: audioSeconds),
          ],
          if (content.trim().isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(content,
                style:
                    const TextStyle(color: _ink, fontSize: 18, height: 1.65)),
          ],
          if (component != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE9EEEE)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.widgets_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(component!.title,
                            style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(component!.subtitle,
                            style:
                                const TextStyle(color: _muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _muted),
                ],
              ),
            ),
          ],
          if (settings.originalDeclaration ||
              settings.repostDeclaration ||
              settings.aiGenerated) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (settings.originalDeclaration) _declaration('已声明原创'),
                if (settings.repostDeclaration) _declaration('转载内容'),
                if (settings.aiGenerated) _declaration('含AI合成内容'),
              ],
            ),
          ],
          const SizedBox(height: 26),
          const Divider(height: 1, color: Color(0xFFF0F0F1)),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PreviewAction(Icons.favorite_border_rounded, '点赞'),
              _PreviewAction(Icons.chat_bubble_outline_rounded, '评论'),
              _PreviewAction(Icons.ios_share_rounded, '分享'),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _declaration(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF2FBFA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(color: _accent, fontSize: 12)),
      );
}

class _PreviewImages extends StatelessWidget {
  const _PreviewImages(this.images);

  final List<File> images;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(images.first, fit: BoxFit.cover),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (_, index) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(images[index], fit: BoxFit.cover),
      ),
    );
  }
}

class _AudioPreviewCard extends StatelessWidget {
  const _AudioPreviewCard({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final duration =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8FAF8), Color(0xFFF8F0F5)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: _accent,
            child:
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 31),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Icon(Icons.graphic_eq_rounded, color: _accent, size: 48),
          ),
          Text(duration,
              style: const TextStyle(color: Color(0xFF70757B), fontSize: 14)),
        ],
      ),
    );
  }
}

class _PreviewAction extends StatelessWidget {
  const _PreviewAction(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF545960), size: 27),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Color(0xFF777B81), fontSize: 13)),
      ],
    );
  }
}

class _ComposerModeBar extends StatelessWidget {
  const _ComposerModeBar({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 78,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF0F0F1))),
        ),
        child: Row(
          children: [
            _mode(0, '发文字'),
            _mode(1, '相册'),
            _mode(2, '音频', dot: true),
          ],
        ),
      ),
    );
  }

  Widget _mode(int value, String label, {bool dot = false}) {
    final active = selected == value;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Text(label,
                  style: TextStyle(
                    color: active ? _ink : const Color(0xFF85898F),
                    fontSize: 18,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  )),
              if (dot)
                const Positioned(
                  right: -10,
                  top: -4,
                  child: CircleAvatar(
                      radius: 4, backgroundColor: Color(0xFFFF586B)),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            width: active ? 24 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}
