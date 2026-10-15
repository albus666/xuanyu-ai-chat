import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/account_session_guard.dart';
import 'suggestion_service.dart';

class SuggestionSubmitPage extends StatefulWidget {
  const SuggestionSubmitPage({super.key, this.service, this.picker});

  final SuggestionService? service;
  final ImagePicker? picker;

  @override
  State<SuggestionSubmitPage> createState() => _SuggestionSubmitPageState();
}

class _SuggestionSubmitPageState extends State<SuggestionSubmitPage>
    with AccountSessionGuard<SuggestionSubmitPage> {
  final _content = TextEditingController();
  final _images = <XFile>[];
  final _uploaded = <String, String>{};
  late final SuggestionService _service;
  late final ImagePicker _picker;
  XFile? _video;
  String _requestId = SuggestionService.newRequestId();
  bool _busy = false;
  bool _picking = false;
  bool _success = false;
  bool _allowPop = false;
  bool _askingExit = false;
  double? _progress;
  String _stage = '';
  String? _error;

  bool get _current => mounted && accountSession.current && _service.current;
  bool get _dirty =>
      _content.text.trim().isNotEmpty || _images.isNotEmpty || _video != null;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SuggestionService();
    _picker = widget.picker ?? ImagePicker();
    apiSessionChanges.addListener(_onAccountChanged);
  }

  void _onAccountChanged() {
    if (accountSession.current) return;
    _service.cancel();
    _content.clear();
    _images.clear();
    _uploaded.clear();
    _video = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onAccountChanged);
    _service.cancel();
    _content.dispose();
    super.dispose();
  }

  void _changed() {
    _requestId = SuggestionService.newRequestId();
    _error = null;
  }

  String _message(Object error, String fallback) =>
      error is SuggestionValidationException
          ? error.message
          : apiSessionFailureMessage(error, fallback);

  Future<void> _pickImages() async {
    if (!_current ||
        _busy ||
        _picking ||
        _images.length >= SuggestionService.maxImages) {
      return;
    }
    setState(() => _picking = true);
    try {
      final selected = await _picker.pickMultiImage(imageQuality: 90);
      if (!_current) return;
      var exceeded = false;
      String? failure;
      for (final file in selected) {
        if (_images.any((item) => item.path == file.path)) continue;
        if (_images.length >= SuggestionService.maxImages) {
          exceeded = true;
          break;
        }
        try {
          await SuggestionService.validateFile(file, isVideo: false);
          if (!_current) return;
          _images.add(file);
          _changed();
        } catch (error) {
          failure = _message(error, '图片无法读取，请重新选择');
        }
      }
      if (mounted && _current && (failure != null || exceeded)) {
        showAppToast(context, failure ?? '最多添加6张图片，已保留前6张');
      }
    } catch (_) {
      if (mounted && _current) {
        showAppToast(context, '无法打开相册，请检查相册权限后重试');
      }
    } finally {
      if (_current) setState(() => _picking = false);
    }
  }

  Future<void> _pickVideo() async {
    if (!_current || _busy || _picking || _video != null) return;
    setState(() => _picking = true);
    try {
      final selected = await _picker.pickVideo(source: ImageSource.gallery);
      if (!_current || selected == null) return;
      await SuggestionService.validateFile(selected, isVideo: true);
      if (!_current) return;
      setState(() {
        _video = selected;
        _changed();
      });
    } catch (error) {
      if (mounted && _current) {
        showAppToast(context, _message(error, '视频无法读取，请重新选择'));
      }
    } finally {
      if (_current) setState(() => _picking = false);
    }
  }

  void _remove(XFile file, {bool isVideo = false}) {
    if (_busy || !_current) return;
    setState(() {
      if (isVideo) {
        _video = null;
      } else {
        _images.remove(file);
      }
      _uploaded.remove(file.path);
      _changed();
    });
  }

  Future<void> _preview(XFile file, {bool isVideo = false}) async {
    if (!_current || _busy) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _SuggestionMediaPreview(file: file, isVideo: isVideo),
    ));
  }

  Future<void> _submit() async {
    if (!_current || _busy || _picking) return;
    final content = _content.text.trim();
    try {
      SuggestionService.validate(
          content: content, images: _images.length, hasVideo: _video != null);
    } on SuggestionValidationException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _stage = '准备提交…';
    });
    try {
      final files = [..._images, if (_video != null) _video!];
      final ids = <String>[];
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        var id = _uploaded[file.path];
        if (id == null) {
          setState(() {
            _stage = '正在上传附件 ${index + 1}/${files.length}';
            _progress = 0;
          });
          id = await _service.upload(file, isVideo: identical(file, _video),
              onProgress: (sent, total) {
            if (!_current) return;
            setState(() => _progress = total > 0 ? sent / total : null);
          });
          if (!_current) return;
          _uploaded[file.path] = id;
        }
        ids.add(id);
      }
      if (!_current) return;
      setState(() {
        _stage = '正在提交建议…';
        _progress = null;
      });
      await _service.submit(
          requestId: _requestId, content: content, attachmentIds: ids);
      if (!_current) return;
      setState(() {
        _success = true;
        _content.clear();
        _images.clear();
        _video = null;
        _uploaded.clear();
      });
    } catch (error) {
      if (_current) {
        setState(() => _error = _message(error, '提交失败，内容已保留，请重试'));
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _confirmExit() async {
    if (_askingExit || !mounted) return;
    if (_busy) {
      showAppToast(context, '正在提交，请等待完成后再返回');
      return;
    }
    _askingExit = true;
    try {
      final leave = !_dirty ||
          await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('放弃这条建议？'),
                  content: const Text('离开后，尚未提交的文字和附件不会保留。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('继续填写')),
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('放弃并离开')),
                  ],
                ),
              ) ==
              true;
      if (!leave || !mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop(_success);
      });
    } finally {
      _askingExit = false;
    }
  }

  Widget _imageTile(XFile file, int index) => SizedBox(
        width: 94,
        height: 94,
        child: Stack(children: [
          Positioned.fill(
              child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _busy ? null : () => _preview(file),
              child: Image.file(
                File(file.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xFFECEFF0),
                    child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          )),
          Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: '删除图片${index + 1}',
                onPressed: _busy ? null : () => _remove(file),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.close, size: 18),
              )),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    return PopScope<Object?>(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('使用建议')),
        body: SafeArea(
          top: false,
          child: _success
              ? _successBody()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    const Text('哪里不顺手，告诉我们',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('感谢你愿意花时间分享使用感受。你的每一条建议，都在帮助玄遇一点点变得更好。',
                        style: TextStyle(
                            color: AppColors.textSecondary, height: 1.6)),
                    const SizedBox(height: 8),
                    const Text('建议和附件仅你本人及平台工作人员可查看。',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 24),
                    TextField(
                      key: const ValueKey('suggestion-content'),
                      controller: _content,
                      enabled: !_busy,
                      minLines: 6,
                      maxLines: 10,
                      maxLength: SuggestionService.maxContentLength,
                      onChanged: (_) => setState(_changed),
                      decoration: const InputDecoration(
                        labelText: '你的建议',
                        alignLabelWithHint: true,
                        hintText: '例如：在哪个页面遇到了什么问题，希望怎样改进…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('补充图片（${_images.length}/6）',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('每张不超过10MB，支持JPG、PNG、WebP、GIF',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var index = 0; index < _images.length; index++)
                        _imageTile(_images[index], index),
                      if (_images.length < SuggestionService.maxImages)
                        SizedBox(
                            width: 94,
                            height: 94,
                            child: OutlinedButton(
                              key: const ValueKey('suggestion-add-images'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _busy || _picking ? null : _pickImages,
                              child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined),
                                    SizedBox(height: 6),
                                    Text('添加图片'),
                                  ]),
                            )),
                    ]),
                    const SizedBox(height: 24),
                    const Text('补充视频（最多1个）',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('不超过100MB，支持MP4、MOV、WebM',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 10),
                    if (_video != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.play_circle_outline,
                            color: AppColors.primary, size: 36),
                        title: Text(_video!.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: const Text('点击预览视频'),
                        onTap: _busy
                            ? null
                            : () => _preview(_video!, isVideo: true),
                        trailing: IconButton(
                            tooltip: '删除视频',
                            onPressed: _busy
                                ? null
                                : () => _remove(_video!, isVideo: true),
                            icon: const Icon(Icons.close)),
                      )
                    else
                      OutlinedButton.icon(
                        key: const ValueKey('suggestion-add-video'),
                        onPressed: _busy || _picking ? null : _pickVideo,
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('添加视频'),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Text(_error!,
                          key: const ValueKey('suggestion-error'),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 8),
                      Text(
                          _progress == null
                              ? _stage
                              : '$_stage · ${(_progress!.clamp(0, 1) * 100).round()}%',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const ValueKey('suggestion-submit'),
                      onPressed: _busy || _picking ? null : _submit,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(_busy ? '正在提交…' : '提交建议')),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _successBody() => Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.primary, size: 64),
          const SizedBox(height: 18),
          const Text('建议已提交',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('谢谢你的用心反馈。我们会认真阅读，也感谢你陪伴玄遇一起成长。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _confirmExit, child: const Text('完成')),
        ]),
      ));
}

class _SuggestionMediaPreview extends StatefulWidget {
  const _SuggestionMediaPreview({required this.file, required this.isVideo});
  final XFile file;
  final bool isVideo;
  @override
  State<_SuggestionMediaPreview> createState() =>
      _SuggestionMediaPreviewState();
}

class _SuggestionMediaPreviewState extends State<_SuggestionMediaPreview>
    with AccountSessionGuard<_SuggestionMediaPreview> {
  VideoPlayerController? _player;
  bool _ready = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_stopForAccountChange);
    if (widget.isVideo) unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final player = VideoPlayerController.file(File(widget.file.path));
    _player = player;
    try {
      await player.initialize();
      if (mounted && accountSession.current) setState(() => _ready = true);
    } catch (_) {
      if (mounted && accountSession.current) {
        setState(() => _error = '暂时无法预览这个视频，可返回重新选择');
      }
    }
  }

  void _stopForAccountChange() {
    if (!accountSession.current) unawaited(_player?.pause());
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_stopForAccountChange);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isVideo ? '视频预览' : '图片预览')),
      body: SafeArea(
        top: false,
        child: Center(
            child: widget.isVideo
                ? _error != null
                    ? Text(_error!, textAlign: TextAlign.center)
                    : !_ready
                        ? const CircularProgressIndicator()
                        : Column(children: [
                            Expanded(
                                child: Center(
                                    child: AspectRatio(
                                        aspectRatio: _player!.value.aspectRatio,
                                        child: VideoPlayer(_player!)))),
                            IconButton(
                                tooltip: _player!.value.isPlaying ? '暂停' : '播放',
                                icon: Icon(
                                    _player!.value.isPlaying
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    size: 44),
                                onPressed: () async {
                                  if (!accountSession.current) return;
                                  if (_player!.value.isPlaying) {
                                    await _player!.pause();
                                  } else {
                                    await _player!.play();
                                  }
                                  if (mounted && accountSession.current) {
                                    setState(() {});
                                  }
                                }),
                          ])
                : InteractiveViewer(
                    child: Image.file(File(widget.file.path),
                        errorBuilder: (_, __, ___) =>
                            const Text('图片无法预览，请返回重新选择')))),
      ),
    );
  }
}
