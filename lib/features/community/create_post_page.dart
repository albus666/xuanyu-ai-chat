import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/media_review.dart';
import '../../core/notification/app_notifications.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'map_location_picker_page.dart';
import 'post_component_sheet.dart';
import 'post_composer_support_pages.dart';
import 'post_entity_text.dart';
import 'post_draft_store.dart';
import 'post_publish_settings_page.dart';
import 'post_publish_task.dart';
import 'local_video_preview.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _contentController = _StyledPostController();
  bool _loading = false;
  final bool _uploading = false;
  int _visibility = 1; // 1:公开, 2:仅粉丝, 3:仅自己
  bool _allowComment = true;
  final _imageFiles = <File>[];
  File? _videoFile;
  File? _audioFile;
  int _audioDurationSeconds = 0;
  PostPublishSettings _publishSettings = const PostPublishSettings();
  PostComponentSelection? _component;
  String? _locationName;
  final _availableTopics = <Map<String, dynamic>>[];
  bool _topicsLoading = false;
  final _scrollController = ScrollController();
  bool _draftFinalized = false;
  bool _allowPop = false;
  bool _closePromptOpen = false;
  final int _draftSession = apiSessionChanges.value;
  PostDraftStore? _draftStore;
  String _draftId = PostDraftStore.newId();
  bool _draftLoading = true;
  bool _draftReady = false;
  List<Map<String, dynamic>> _recoverable = [];
  bool get _sameSession => _draftSession == apiSessionChanges.value;

  // --- inline # / @ suggestion ---
  List<Map<String, dynamic>> _mentionCandidates = [];
  Future<void>? _mentionCandidatesRequest;
  final Map<String, int> _selectedTopicIds = {};
  final Map<String, int> _selectedMentionIds = {};
  final _suggestionLayerLink = LayerLink();
  OverlayEntry? _suggestionOverlay;
  String? _activeTrigger;
  String _triggerQuery = '';
  int _triggerStart = -1;
  int _suggestionGeneration = 0;

  static const _kAccent = AppColors.primary;
  static const _kAccentTagBg = AppColors.primaryLight;

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_onContentChanged);
    PostDraftStore.changes.addListener(_refreshPending);
    _restoreDraft();
    _loadTopics();
  }

  @override
  void dispose() {
    _hideSuggestions();
    PostDraftStore.changes.removeListener(_refreshPending);
    if (!_draftFinalized && _draftReady) {
      // 同步截取后再异步落盘，避免 dispose 后读取已销毁的 Controller。
      unawaited(_saveDraft().catchError((Object _) {}));
    }
    _contentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _snapshot() => {
        'id': _draftId,
        'content': _contentController.text,
        'images': _imageFiles.map((file) => file.path).toList(),
        'video': _videoFile?.path,
        'audio': _audioFile?.path,
        'audioSeconds': _audioDurationSeconds,
        'settings': _publishSettings.toJson(),
        'topics': Map<String, int>.from(_selectedTopicIds),
        'mentions': Map<String, int>.from(_selectedMentionIds),
        'location': _locationName,
        'component': _component?.toJson(),
      };

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !_sameSession) return;
      final store = PostDraftStore(prefs.getInt(AppConstants.keyUserId));
      _draftStore = store;
      final saved = await store.active();
      if (!mounted || !_sameSession) return;
      setState(() {
        if (saved != null) _applyDraft(saved);
        _draftReady = true;
      });
      await _refreshPending();
    } catch (_) {
      if (mounted) showAppToast(context, '草稿读取失败，原内容已保留，请退出后重试');
    } finally {
      if (mounted) setState(() => _draftLoading = false);
    }
  }

  void _applyDraft(Map<String, dynamic> saved) {
    _draftId = saved['id'] as String? ?? PostDraftStore.newId();
    _contentController.text = saved['content'] as String? ?? '';
    _selectedTopicIds
      ..clear()
      ..addAll(_decodeDraftEntityMap(jsonEncode(saved['topics'])));
    _selectedMentionIds
      ..clear()
      ..addAll(_decodeDraftEntityMap(jsonEncode(saved['mentions'])));
    for (final name in _selectedTopicIds.keys) {
      _contentController.registerEntity('#', name);
    }
    for (final name in _selectedMentionIds.keys) {
      _contentController.registerEntity('@', name);
    }
    _publishSettings = PostPublishSettings.fromJson(saved['settings']);
    _visibility = _publishSettings.visibility;
    _allowComment = _publishSettings.allowComment;
    _locationName = saved['location'] as String?;
    final component = saved['component'];
    _component = component is Map &&
            component['key'] != null &&
            component['title'] != null
        ? PostComponentSelection(
            key: component['key'].toString(),
            title: component['title'].toString(),
            subtitle: (component['subtitle'] ?? '').toString(),
            referenceId: (component['referenceId'] as num?)?.toInt())
        : null;
    _applyDraftMedia(saved);
  }

  void _applyDraftMedia(Map<String, dynamic> saved) {
    _imageFiles
      ..clear()
      ..addAll(
          ((saved['images'] as List?) ?? []).whereType<String>().map(File.new));
    _videoFile =
        saved['video'] is String ? File(saved['video'] as String) : null;
    _audioFile =
        saved['audio'] is String ? File(saved['audio'] as String) : null;
    _audioDurationSeconds = (saved['audioSeconds'] as num?)?.toInt() ?? 0;
  }

  Future<void> _saveDraft() {
    if (!_draftReady || _draftStore == null) {
      return Future<void>.error(StateError('草稿尚未读取成功'));
    }
    return _draftStore!.save(_snapshot()).then<void>((_) {});
  }

  Future<void> _clearDraft() async {
    if (_draftReady) await _draftStore?.discard(_draftId);
  }

  Future<void> _refreshPending() async {
    final store = _draftStore;
    if (store == null || !mounted || !_sameSession) return;
    try {
      final pending = await store.pending();
      if (!mounted || !_sameSession) return;
      setState(() => _recoverable = pending
          .where((item) =>
              !PostPublishTask.isRunning(store, item['id'] as String) &&
              !PostPublishTask.isCompleted(store, item['id'] as String))
          .toList());
    } catch (_) {
      // 读取失败不覆盖现有草稿。
    }
  }

  Future<void> _openRecovery() async {
    if (_loading || !_sameSession || _draftStore == null) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
          child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .55,
        child: Column(children: [
          const ListTile(title: Text('未完成发布'), subtitle: Text('恢复到编辑页，不会自动重发')),
          Expanded(
              child: ListView.builder(
            itemCount: _recoverable.length,
            itemBuilder: (_, index) {
              final item = _recoverable[index];
              final text = item['content']?.toString().trim() ?? '';
              final uncertain =
                  ['publishing', 'uncertain'].contains(item['status']);
              return ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: Text(text.isEmpty ? '未完成的编辑稿' : text,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(uncertain
                    ? '结果待确认 · 请先查看自己的作品'
                    : item['status'] == 'saved'
                        ? '已保存的编辑稿'
                        : '未完成 · 点击恢复'),
                onTap: () => Navigator.pop(ctx, item),
              );
            },
          )),
        ]),
      )),
    );
    if (!mounted || selected == null || !_sameSession) return;
    if (PostPublishTask.isRunning(_draftStore!, selected['id'] as String)) {
      return;
    }
    final uncertain = ['publishing', 'uncertain'].contains(selected['status']);
    final hasCurrent = PostDraftStore.hasContent(_snapshot());
    if (uncertain || hasCurrent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复到编辑页？'),
          content: Text([
            if (uncertain) '这次发布可能已经成功，请先查看个人主页作品，确认没有发布后再恢复，避免重复。',
            if (hasCurrent) '当前编辑内容会另存到“未完成发布”，不会被覆盖。',
          ].join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认恢复')),
          ],
        ),
      );
      if (confirmed != true || !mounted || !_sameSession) return;
    }
    setState(() => _loading = true);
    try {
      final restored =
          await _draftStore!.recover(selected['id'] as String, _snapshot());
      if (!mounted || !_sameSession) return;
      setState(() => _applyDraft(restored));
      await _refreshPending();
    } catch (_) {
      if (mounted) showAppToast(context, '恢复失败，记录已保留，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, int> _decodeDraftEntityMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map<String, int>(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _loadTopics() async {
    if (_topicsLoading) return;
    setState(() => _topicsLoading = true);
    try {
      final res = await apiClient.get('/api/community/topics');
      final raw = (res.data as Map?)?['data'];
      final list = raw is List
          ? raw
          : raw is Map
              ? raw['list'] as List<dynamic>?
              : null;
      if (list != null && mounted) {
        setState(() {
          _availableTopics
            ..clear()
            ..addAll(
              list.whereType<Map>().map(
                    (item) => Map<String, dynamic>.from(item),
                  ),
            );
        });
      }
    } catch (_) {
      // 话题加载失败不影响基础发布。
    } finally {
      if (mounted) setState(() => _topicsLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // inline # / @ suggestion
  // ---------------------------------------------------------------------------
  void _onContentChanged() {
    final content = _contentController.text;
    _selectedTopicIds.removeWhere((name, _) => !content.contains('#$name'));
    _selectedMentionIds.removeWhere((name, _) => !content.contains('@$name'));
    setState(() {}); // keep length counter updated
    _detectTrigger();
  }

  void _detectTrigger() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (!sel.isValid) {
      _hideSuggestions();
      return;
    }
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    // walk backwards from cursor to find the nearest trigger
    int i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '#' || ch == '@') {
        // ensure it's at word boundary (start of text or preceded by space/newline)
        if (i == 0 || _isInlineTriggerBoundary(text[i - 1])) {
          final query = text.substring(i + 1, cursor);
          // query must not contain space / newline / another trigger
          if (!query.contains(' ') &&
              !query.contains('\n') &&
              !query.contains('#') &&
              !query.contains('@')) {
            _activeTrigger = ch;
            _triggerQuery = query;
            _triggerStart = i;
            _showSuggestions();
            return;
          }
        }
        break;
      }
      if (ch == ' ' || ch == '\n') break;
      i--;
    }
    _hideSuggestions();
  }

  void _showSuggestions() {
    _removeSuggestionOverlay();
    final generation = ++_suggestionGeneration;
    if (_activeTrigger == '#') {
      _buildTopicOverlay(generation);
    } else if (_activeTrigger == '@') {
      _loadAndBuildMentionOverlay(generation);
    }
  }

  void _removeSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  void _hideSuggestions() {
    _suggestionGeneration++;
    _removeSuggestionOverlay();
    _activeTrigger = null;
    _triggerQuery = '';
    _triggerStart = -1;
  }

  void _applySuggestion(Map<String, dynamic> item) {
    if (_triggerStart < 0 || _activeTrigger == null) return;
    final trigger = _activeTrigger!;
    final display = trigger == '#'
        ? item['name']?.toString().trim() ?? ''
        : item['nickname']?.toString().trim() ?? '';
    final id = trigger == '#'
        ? (item['id'] as num?)?.toInt()
        : (item['userId'] as num?)?.toInt();
    if (display.isEmpty || id == null) return;
    final text = _contentController.text;
    final cursor = _contentController.selection.baseOffset;

    // keep everything before the trigger, then trigger + name + space
    final before = text.substring(0, _triggerStart);
    final end = cursor.clamp(0, text.length);
    final after = end < text.length ? text.substring(end) : '';
    final replacement = '$trigger$display ';
    final newText = '$before$replacement$after';
    final newCursor = before.length + replacement.length;

    // temporarily remove listener so setting .value does not re-fire detectTrigger
    _contentController.registerEntity(trigger, display);
    _contentController.removeListener(_onContentChanged);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newCursor.clamp(0, newText.length),
      ),
    );
    _contentController.addListener(_onContentChanged);
    if (trigger == '#') {
      _selectedTopicIds[display] = id;
    } else {
      _selectedMentionIds[display] = id;
    }
    _hideSuggestions();
    setState(() {});
  }

  void _buildTopicOverlay(int generation) {
    if (!mounted || generation != _suggestionGeneration) return;
    final query = _triggerQuery.toLowerCase();
    final filtered = _availableTopics.where((t) {
      final name = (t['name']?.toString() ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
    if (filtered.isEmpty) {
      _hideSuggestions();
      return;
    }
    _suggestionOverlay = OverlayEntry(
      builder: (_) {
        return _SuggestionDropdown(
          layerLink: _suggestionLayerLink,
          items: filtered,
          itemLabel: (item) => '# ${item['name']}',
          onSelected: _applySuggestion,
          onDismiss: _hideSuggestions,
        );
      },
    );
    if (generation == _suggestionGeneration) {
      Overlay.of(context).insert(_suggestionOverlay!);
    }
  }

  Future<void> _loadMentionCandidates() {
    return _mentionCandidatesRequest ??= (() async {
      try {
        final res = await apiClient.get('/api/community/mention-suggestions');
        final body = res.data as Map<String, dynamic>?;
        final data = body?['data'] as Map<String, dynamic>?;
        final list = data?['list'] as List<dynamic>?;
        if (list != null && mounted) {
          _mentionCandidates = list
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } catch (_) {
        _mentionCandidates = [];
        _mentionCandidatesRequest = null;
      }
    })();
  }

  void _loadAndBuildMentionOverlay(int generation) async {
    if (!mounted) return;
    await _loadMentionCandidates();
    if (!mounted ||
        generation != _suggestionGeneration ||
        _activeTrigger != '@') {
      return;
    }
    final query = _triggerQuery.toLowerCase();
    final filtered = _mentionCandidates.where((u) {
      final name = (u['nickname']?.toString() ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
    if (filtered.isEmpty) {
      _hideSuggestions();
      return;
    }
    _suggestionOverlay = OverlayEntry(
      builder: (_) {
        return _SuggestionDropdown(
          layerLink: _suggestionLayerLink,
          items: filtered,
          itemLabel: (item) {
            final name = item['nickname']?.toString() ?? '';
            return '@$name';
          },
          itemAvatar: (item) => item['avatar']?.toString(),
          itemSubtitle: (item) {
            final code = item['userCode']?.toString().trim() ?? '';
            return code.isEmpty ? null : '玄遇号：$code';
          },
          onSelected: _applySuggestion,
          onDismiss: _hideSuggestions,
        );
      },
    );
    if (generation == _suggestionGeneration) {
      Overlay.of(context).insert(_suggestionOverlay!);
    }
  }

  /// Insert # or @ at cursor and trigger overlay
  void _insertTriggerAtCursor(String trigger) {
    final text = _contentController.text;
    final sel = _contentController.selection;
    final cursor = sel.baseOffset;
    // ensure there's a space before the trigger unless at start or after newline
    String prefix = '';
    if (cursor > 0 && text[cursor - 1] != ' ' && text[cursor - 1] != '\n') {
      prefix = ' ';
    }
    final before = text.substring(0, cursor);
    final after = cursor < text.length ? text.substring(cursor) : '';
    final newText = '$before$prefix$trigger$after';
    final newCursor = cursor + prefix.length + trigger.length;
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(offset: newCursor);
    // trigger detection will fire via listener
  }

  Future<void> _handleClose() async {
    if (!mounted || _closePromptOpen || _loading || _draftLoading) return;
    _closePromptOpen = true;
    try {
      // 空白发布页直接退出，连续点击也只处理一次返回。
      if (!_canPublish &&
          _component == null &&
          (_locationName == null || _locationName!.trim().isEmpty)) {
        await _clearDraft();
        _draftFinalized = true;
        if (mounted) await _exitPage();
        return;
      }
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('保存草稿'),
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
              ListTile(
                title: const Text('不保存草稿', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'discard'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'save') {
        await _saveDraft();
        _draftFinalized = true;
        if (mounted) await _exitPage();
      } else if (action == 'discard') {
        await _clearDraft();
        _draftFinalized = true;
        if (mounted) await _exitPage();
      }
    } catch (_) {
      if (mounted) showAppToast(context, '草稿保存失败，请检查剩余空间后重试');
    } finally {
      _closePromptOpen = false;
    }
  }

  Future<void> _exitPage([Object? result]) async {
    if (!mounted) return;
    _allowPop = true;
    // 发布页既可能由 Get.to 打开，也可能由普通 Navigator.push 打开。
    // 用当前页面所属 Navigator 的 maybePop，若页面已经是根路由则拒绝弹出，
    // 避免系统返回把整个 APP 一起退出。
    final popped = await Navigator.of(context).maybePop(result);
    if (!popped && mounted) _allowPop = false;
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (mounted) showAppToast(context, '需要相机权限才能拍照或录视频');
    return false;
  }

  Future<bool> _ensureGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (status.isGranted || status.isLimited) return true;
      if (mounted) showAppToast(context, '需要相册权限才能选择图片或视频');
      return false;
    }
    // Android 系统相册/Photo Picker 不依赖 READ_MEDIA_IMAGES，先弹权限会拦掉选图。
    return true;
  }

  Future<bool> _ensureVideoRecordPermission() async {
    if (!await _ensureCameraPermission()) return false;
    final mic = await Permission.microphone.request();
    if (mic.isGranted) return true;
    if (mounted) showAppToast(context, '需要麦克风权限才能录视频');
    return false;
  }

  Future<void> _pickImages({ImageSource source = ImageSource.gallery}) async {
    if (_videoFile != null) return;
    try {
      if (source == ImageSource.camera) {
        if (!await _ensureCameraPermission()) return;
      } else if (!await _ensureGalleryPermission()) {
        return;
      }
      final picker = ImagePicker();
      if (source == ImageSource.gallery) {
        // Do not recompress gallery originals: metadata is inspected after upload.
        final list = await picker.pickMultiImage();
        if (list.isEmpty || !mounted) return;
        setState(() {
          for (final x in list) {
            if (_imageFiles.length < 9) _imageFiles.add(File(x.path));
          }
        });
      } else {
        final x = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1200,
          imageQuality: 85,
        );
        if (x == null || !mounted) return;
        setState(() {
          if (_imageFiles.length < 9) _imageFiles.add(File(x.path));
        });
      }
    } catch (e) {
      if (mounted) showAppToast(context, '选择图片失败: $e');
    }
  }

  Future<void> _pickVideo({ImageSource source = ImageSource.gallery}) async {
    if (_imageFiles.isNotEmpty) return;
    try {
      if (source == ImageSource.camera) {
        if (!await _ensureVideoRecordPermission()) return;
      } else if (!await _ensureGalleryPermission()) {
        return;
      }
      final picker = ImagePicker();
      final x = await picker.pickVideo(source: source);
      if (x == null || !mounted) return;
      setState(() => _videoFile = File(x.path));
    } catch (e) {
      if (mounted) showAppToast(context, '选择视频失败: $e');
    }
  }

  Future<void> _showMediaPicker() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('post-media-source-camera'),
              leading: const Icon(
                Icons.photo_camera_rounded,
                color: AppColors.primary,
              ),
              title: const Text('相机'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              key: const ValueKey('post-media-source-image'),
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primary,
              ),
              title: const Text('图片'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              key: const ValueKey('post-media-source-video'),
              leading: const Icon(
                Icons.video_library_rounded,
                color: AppColors.primary,
              ),
              title: const Text('视频'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'camera':
        await _pickImages(source: ImageSource.camera);
      case 'image':
        await _pickImages();
      case 'video':
        await _pickVideo();
    }
  }

  /// 直传 OSS：先拿预签名 URL，再 PUT 到 OSS，视频再调 confirm 取封面。返回 { url, coverUrl? }，失败抛异常。
  // ignore: unused_element
  Future<Map<String, String>> _uploadViaPresign(File file, bool isVideo) async {
    final ext = isVideo ? '.mp4' : '.jpg';
    final res = await apiClient.post(
      '/api/config/presign-upload',
      data: {
        'type': isVideo ? 'video' : 'image',
        'ext': ext,
        'moderationScope': 'public',
      },
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );
    final data = res.data;
    if (data is! Map || data['code'] != 0 || data['data'] == null) {
      final msg = data is Map
          ? (data['message']?.toString() ?? '获取上传链接失败')
          : '获取上传链接失败';
      throw Exception(msg);
    }
    final d = data['data'] as Map;
    final uploadUrl = d['uploadUrl']?.toString();
    final url = d['url']?.toString();
    final objectKey = d['objectKey']?.toString();
    if (uploadUrl == null || url == null || objectKey == null) {
      throw Exception('上传链接无效');
    }

    final bytes = await file.readAsBytes();
    final client = HttpClient();
    try {
      client.connectionTimeout =
          isVideo ? const Duration(minutes: 5) : const Duration(minutes: 2);
      final req = await client.putUrl(Uri.parse(uploadUrl));
      req.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close();
      if (resp.statusCode >= 400) {
        throw Exception('上传失败: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }

    final confirmRes = await apiClient.post(
      '/api/config/confirm-upload',
      data: {'objectKey': objectKey},
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
    final reviewed = await awaitMediaReview(
      confirmRes.data,
      fallbackUrl: url,
      timeout:
          isVideo ? const Duration(minutes: 6) : const Duration(minutes: 4),
    );
    final result = <String, String>{'url': reviewed['url'].toString()};
    final coverUrl = reviewed['coverUrl']?.toString();
    if (coverUrl != null && coverUrl.isNotEmpty) {
      result['coverUrl'] = coverUrl;
    }
    return result;
  }

  /// 经后端上传（备用，速度较慢）。返回 { url, coverUrl? }。
  // ignore: unused_element
  Future<Map<String, String>?> _uploadSingleFile(
    File file,
    bool isVideo,
  ) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: isVideo ? 'video.mp4' : 'image.jpg',
      ),
      'moderationScope': 'public',
    });
    final timeout =
        isVideo ? const Duration(minutes: 3) : const Duration(seconds: 60);
    final res = await apiClient.post(
      '/api/config/upload',
      data: formData,
      options: Options(sendTimeout: timeout, receiveTimeout: timeout),
    );
    final data = res.data;
    if (data is Map && data['code'] == 0 && data['data'] != null) {
      final d = data['data'] as Map;
      final url = d['url']?.toString();
      if (url == null) return null;
      final result = <String, String>{'url': url};
      final coverUrl = d['coverUrl']?.toString();
      if (coverUrl != null && coverUrl.isNotEmpty) {
        result['coverUrl'] = coverUrl;
      }
      return result;
    }
    final msg = data is Map ? (data['message']?.toString() ?? '上传失败') : '上传失败';
    throw Exception(msg);
  }

  Future<void> _submit() async {
    if (_loading || _draftLoading || !_draftReady || !_canPublish) return;
    if (!_sameSession ||
        _draftStore?.ownerId == null ||
        apiClient.options.headers['Authorization'] == null) {
      showAppToast(context, '登录状态已变化，请返回后重新打开发布页');
      return;
    }
    setState(() => _loading = true);
    _hideSuggestions();
    try {
      if (_contentController.text.contains('@') && _mentionCandidates.isEmpty) {
        await _loadMentionCandidates();
      }
      if (!mounted || !_sameSession) return;
      final snapshot = _snapshot();
      final content = (snapshot['content'] as String).trim();
      final topics = snapshot['topics'] as Map<String, int>;
      for (final topic in _availableTopics) {
        final name = topic['name']?.toString().trim() ?? '';
        final id = (topic['id'] as num?)?.toInt();
        if (name.isNotEmpty && id != null && content.contains('#$name')) {
          topics.putIfAbsent(name, () => id);
        }
      }
      final mentions = snapshot['mentions'] as Map<String, int>;
      for (final user in _mentionCandidates) {
        final name = user['nickname']?.toString().trim() ?? '';
        final id = (user['userId'] as num?)?.toInt();
        if (name.isNotEmpty && id != null && content.contains('@$name')) {
          mentions.putIfAbsent(name, () => id);
        }
      }
      // 先持久保存完整编辑稿，再进行任何网络检查。
      final saved = await _draftStore!.save(snapshot);
      if (!mounted || !_sameSession) return;
      setState(() => _applyDraftMedia(saved));
      if (!mounted || !_sameSession) return;
      final task = PostPublishTask(store: _draftStore!, draft: saved);
      await task.prepare();
      _draftFinalized = true;
      // 通知权限失败不能中断发布；任务只会使用创建时的原账号。
      unawaited(PostPublishTask.run(task));
      if (mounted && _sameSession) {
        showAppToast(context, '正在发布…', duration: const Duration(seconds: 3));
        await _exitPage(true);
      }
      unawaited(_requestPublishNotification());
    } catch (_) {
      if (mounted && _sameSession) {
        showAppToast(context, '暂时无法发布，编辑内容已保留，请检查网络和存储空间后重试');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestPublishNotification() async {
    if (!_sameSession) return;
    try {
      await requestNotificationPermission();
    } catch (_) {}
  }

  String get _visibilityLabel {
    switch (_visibility) {
      case 3:
        return '仅自己';
      case 2:
        return '仅粉丝';
      default:
        return '公开';
    }
  }

  void _showVisibilityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _visibilityOption(1, '公开', '所有人可见，进入广场', Icons.public_rounded),
            _visibilityOption(
              2,
              '仅粉丝',
              '只有关注你的人可以看到',
              Icons.people_outline_rounded,
            ),
            _visibilityOption(
              3,
              '仅自己',
              '只保存在你的私密空间',
              Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _visibilityOption(
    int value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = _visibility == value;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: selected ? AppColors.primary : AppColors.textSecondary,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: AppTextStyles.bodyMedium.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle, style: AppTextStyles.bodySmall),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
      onTap: () {
        setState(() => _visibility = value);
        Navigator.pop(context);
      },
    );
  }

  Future<bool> _handleSystemBack() async {
    if (_allowPop) return true;
    // 先立刻拦住本次系统返回，再异步处理草稿选择；避免在系统返回
    // 的 willPop 调用尚未结束时再次 maybePop，导致导航栈重入。
    unawaited(_handleClose());
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: _buildModernComposer(context),
    );
  }

  bool get _canPublish =>
      _contentController.text.trim().isNotEmpty ||
      _imageFiles.isNotEmpty ||
      _videoFile != null ||
      _audioFile != null;

  Future<void> _openPublishSettings() async {
    final value = await Navigator.of(context).push<PostPublishSettings>(
      MaterialPageRoute(
        builder: (_) => PostPublishSettingsPage(initial: _publishSettings),
      ),
    );
    if (value != null && mounted) {
      setState(() {
        _publishSettings = value;
        _visibility = value.visibility;
        _allowComment = value.allowComment;
      });
    }
  }

  Future<void> _openComponentPicker() async {
    final selected = await showPostComponentSheet(context);
    if (selected != null && mounted) setState(() => _component = selected);
  }

  void _openPreview() {
    if (!_canPublish) {
      showAppToast(context, '添加内容后即可预览');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostPreviewPage(
          content: _contentController.text,
          images: List<File>.from(_imageFiles),
          videoPath: _videoFile?.path,
          audioPath: _audioFile?.path,
          audioSeconds: _audioDurationSeconds,
          location: _locationName,
          component: _component,
          settings: _publishSettings,
        ),
      ),
    );
  }

  Widget _buildModernComposer(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: AbsorbPointer(
        absorbing: _loading || _draftLoading,
        child: SafeArea(
          child: Column(
            children: [
              _buildModernTopBar(),
              Expanded(
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: max(520, constraints.maxHeight - 36),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_recoverable.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: _openRecovery,
                                    icon: const Icon(Icons.restore_rounded),
                                    label:
                                        Text('未完成发布（${_recoverable.length}）'),
                                  ),
                                _buildModernMediaArea(),
                                const SizedBox(height: 20),
                                CompositedTransformTarget(
                                  link: _suggestionLayerLink,
                                  child: TextField(
                                    controller: _contentController,
                                    minLines: 5,
                                    maxLines: null,
                                    maxLength: 500,
                                    style: const TextStyle(
                                      color: Color(0xFF303237),
                                      fontSize: 15,
                                      height: 1.65,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '记录你的生活吧，因为和别人的生活不一样。',
                                      hintStyle: TextStyle(
                                        color: Color(0xFFC0C2C6),
                                        fontSize: 14,
                                        height: 1.55,
                                      ),
                                      border: InputBorder.none,
                                      counterText: '',
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _buildToolCapsules(),
                                const SizedBox(height: 18),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFF0F0F1),
                                ),
                                _modernSettingRow(
                                  Icons.location_on_outlined,
                                  _locationName?.isNotEmpty == true
                                      ? _locationName!
                                      : '选择位置',
                                  _openLocationPicker,
                                  key: const ValueKey('post-setting-location'),
                                  onClear: _locationName == null
                                      ? null
                                      : () =>
                                          setState(() => _locationName = null),
                                ),
                                _modernSettingRow(
                                  Icons.lock_outline_rounded,
                                  _publishSettings.visibilityLabel,
                                  _openPublishSettings,
                                  key:
                                      const ValueKey('post-setting-visibility'),
                                ),
                                _modernSettingRow(
                                  Icons.grid_view_rounded,
                                  _component == null
                                      ? '添加组件'
                                      : _component!.title,
                                  _openComponentPicker,
                                  key: const ValueKey('post-setting-component'),
                                  onClear: _component == null
                                      ? null
                                      : () => setState(() => _component = null),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    if (_uploading) _buildUploadingOverlay(),
                    if (_loading || _draftLoading)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTopBar() {
    final enabled = _canPublish && !_loading && _draftReady && _sameSession;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            onPressed: _handleClose,
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF24272B),
              size: 33,
            ),
          ),
          const Spacer(),
          if (_canPublish)
            TextButton(
              onPressed: _openPreview,
              child: const Text(
                '预览',
                style: TextStyle(
                  color: Color(0xFF797E84),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(width: 4),
          SizedBox(
            width: 52,
            height: 32,
            child: TextButton(
              onPressed: enabled ? _submit : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: enabled
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.18),
                disabledForegroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withValues(
                  alpha: 0.18,
                ),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '发布',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildModernMediaArea() {
    if (_audioFile != null) {
      final duration =
          '${_audioDurationSeconds ~/ 60}:${(_audioDurationSeconds % 60).toString().padLeft(2, '0')}';
      return Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE9FAF8), Color(0xFFF9F1F6)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.graphic_eq_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                '声音作品',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF2C3035),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              duration,
              style: const TextStyle(color: Color(0xFF8C9197), fontSize: 12),
            ),
            IconButton(
              onPressed: () => setState(() {
                _audioFile = null;
                _audioDurationSeconds = 0;
              }),
              icon: const Icon(Icons.close_rounded, color: Color(0xFF999DA2)),
            ),
          ],
        ),
      );
    }
    if (_imageFiles.isEmpty && _videoFile == null) {
      return InkWell(
        key: const ValueKey('post-media-add'),
        onTap: _showMediaPicker,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.add_rounded,
            color: Color(0xFFB8BABE),
            size: 45,
          ),
        ),
      );
    }
    if (_videoFile != null) {
      return Stack(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: LocalVideoPreview(path: _videoFile!.path),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: _modernRemoveButton(() => setState(() => _videoFile = null)),
          ),
        ],
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: min(9, _imageFiles.length + 1),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 7,
        crossAxisSpacing: 7,
      ),
      itemBuilder: (context, index) {
        if (index == _imageFiles.length) {
          return InkWell(
            key: const ValueKey('post-media-add-more'),
            onTap: _showMediaPicker,
            child: Container(
              color: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.add_rounded,
                color: Color(0xFFB8BABE),
                size: 38,
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _showImagePreview(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_imageFiles[index], fit: BoxFit.cover),
              ),
            ),
            Positioned(
              right: 5,
              top: 5,
              child: _modernRemoveButton(
                () => setState(() => _imageFiles.removeAt(index)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _modernRemoveButton(VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 25,
          height: 25,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 17),
        ),
      );

  Widget _buildToolCapsules() {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        _toolCapsule(
          Icons.tag_rounded,
          '话题',
          () => _insertTriggerAtCursor('#'),
        ),
        _toolCapsule(
          Icons.alternate_email_rounded,
          'Ta',
          () => _insertTriggerAtCursor('@'),
        ),
      ],
    );
  }

  Widget _toolCapsule(IconData icon, String label, VoidCallback onTap) {
    return Material(
      key: ValueKey('post-tool-$label'),
      color: const Color(0xFFF6F6F6),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF35383D)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF35383D),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modernSettingRow(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Key? key,
    VoidCallback? onClear,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: SizedBox(
        height: 66,
        child: Row(
          children: [
            Icon(icon, size: 24, color: const Color(0xFF303339)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF303339),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Color(0xFFB4B7BB),
                ),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 27,
              color: Color(0xFFB4B7BB),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(
            color: AppColors.divider.withOpacity(0.6),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: AppColors.textPrimary,
                size: 22,
              ),
            ),
            onPressed: _handleClose,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (_contentController.text.trim().isEmpty || _loading)
                    ? null
                    : _submit,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _contentController.text.trim().isEmpty
                        ? AppColors.textHint.withOpacity(0.15)
                        : _kAccent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '发布',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompositedTransformTarget(
            link: _suggestionLayerLink,
            child: TextField(
              controller: _contentController,
              maxLines: null,
              minLines: 6,
              maxLength: 500,
              style: AppTextStyles.bodyLarge.copyWith(
                height: 1.65,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '记录此刻的心情……',
                hintStyle: TextStyle(
                  color: AppColors.textHint.withOpacity(0.5),
                  fontSize: 17,
                  height: 1.65,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                counterText: '',
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.textHint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_contentController.text.length}/500',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _contentController.text.length > 450
                        ? AppColors.error
                        : AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '正在上传…',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 12,
        left: 8,
        right: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider.withOpacity(0.5), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarItem(
              Icons.image_outlined,
              '图片',
              AppColors.primary,
              () => _pickImages(source: ImageSource.gallery),
            ),
            _toolbarItem(
              Icons.camera_alt_outlined,
              '拍摄',
              AppColors.primary,
              _showMediaPicker,
            ),
            _toolbarItem(
              Icons.tag_rounded,
              '话题',
              AppColors.textSecondary,
              () => _insertTriggerAtCursor('#'),
            ),
            _toolbarItem(
              Icons.alternate_email_rounded,
              '提到',
              AppColors.textSecondary,
              () => _insertTriggerAtCursor('@'),
            ),
            const SizedBox(width: 8),
            Container(
              height: 32,
              width: 1,
              color: AppColors.divider.withOpacity(0.4),
            ),
            const SizedBox(width: 8),
            _toolbarItem(
              Icons.visibility_outlined,
              _visibilityLabel,
              const Color(0xFF6366F1),
              _showVisibilityPicker,
            ),
            const Spacer(),
            if (_contentController.text.trim().isNotEmpty ||
                _imageFiles.isNotEmpty ||
                _videoFile != null ||
                (_locationName?.isNotEmpty == true))
              _toolbarItem(
                Icons.save_outlined,
                '存草稿',
                const Color(0xFF059669),
                () async {
                  await _saveDraft();
                  if (mounted) showAppToast(context, '草稿已保存');
                },
              ),
          ],
        ),
      ),
    );
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final i = normalized.lastIndexOf('/');
    return i >= 0 ? normalized.substring(i + 1) : normalized;
  }

  void _moveImage(int from, int to) {
    if (to < 0 || to >= _imageFiles.length || from == to) return;
    setState(() {
      final file = _imageFiles.removeAt(from);
      _imageFiles.insert(to, file);
    });
  }

  void _showImagePreview(int initialIndex) {
    final controller = PageController(initialPage: initialIndex);
    int currentIndex = initialIndex;
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (_imageFiles.isEmpty) return const SizedBox.shrink();
          return Container(
            color: Colors.black.withValues(alpha: 0.94),
            child: Stack(
              children: [
                PageView.builder(
                  controller: controller,
                  itemCount: _imageFiles.length,
                  onPageChanged: (i) => setDialogState(() => currentIndex = i),
                  itemBuilder: (_, index) => Center(
                    child: Image.file(_imageFiles[index], fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Text(
                        '${currentIndex + 1}/${_imageFiles.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: currentIndex == 0
                              ? null
                              : () => controller.previousPage(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('上一张'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          onPressed: () {
                            setState(() => _imageFiles.removeAt(currentIndex));
                            if (_imageFiles.isEmpty) {
                              Navigator.pop(ctx);
                              return;
                            }
                            final nextIndex = currentIndex >= _imageFiles.length
                                ? _imageFiles.length - 1
                                : currentIndex;
                            setDialogState(() => currentIndex = nextIndex);
                            controller.jumpToPage(nextIndex);
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('删除'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: currentIndex >= _imageFiles.length - 1
                              ? null
                              : () => controller.nextPage(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('下一张'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _orderBadge(int order) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$order',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _toolbarItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    if (_imageFiles.isEmpty && _videoFile == null)
      return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemCount: _videoFile != null ? 1 : _imageFiles.length,
        itemBuilder: (context, index) {
          if (_videoFile != null) return _buildVideoItem();
          return _buildImageItem(index);
        },
      ),
    );
  }

  Widget _buildImageItem(int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => _showImagePreview(index),
          child: Hero(
            tag: 'pick_${_imageFiles[index].path}',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(_imageFiles[index], fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        Positioned(left: 6, bottom: 6, child: _orderBadge(index + 1)),
        if (_imageFiles.length > 1)
          Positioned(
            left: 6,
            top: 6,
            child: Row(
              children: [
                if (index > 0)
                  _imageMoveButton(
                    Icons.chevron_left_rounded,
                    () => _moveImage(index, index - 1),
                  ),
                if (index < _imageFiles.length - 1) ...[
                  if (index > 0) const SizedBox(width: 4),
                  _imageMoveButton(
                    Icons.chevron_right_rounded,
                    () => _moveImage(index, index + 1),
                  ),
                ],
              ],
            ),
          ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () => setState(() => _imageFiles.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageMoveButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.46),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.24), width: 1),
        ),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    );
  }

  Widget _buildVideoItem() {
    return Stack(
      fit: StackFit.expand,
      children: [
        LocalVideoPreview(path: _videoFile!.path),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () => setState(() => _videoFile = null),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider.withOpacity(0.4), width: 1),
      ),
      child: Column(
        children: [
          _buildOptionTile(
            Icons.visibility_rounded,
            '谁可以看',
            const Color(0xFF6366F1),
            trailingText: _visibilityLabel,
            onTap: _showVisibilityPicker,
          ),
          Divider(
            height: 1,
            indent: 56,
            endIndent: 20,
            color: AppColors.divider.withOpacity(0.6),
          ),
          _buildOptionTile(
            Icons.chat_bubble_outline_rounded,
            '允许评论',
            const Color(0xFF0EA5E9),
            isSwitch: true,
            switchValue: _allowComment,
            onSwitchChanged: (v) => setState(() => _allowComment = v),
          ),
          Divider(
            height: 1,
            indent: 56,
            endIndent: 20,
            color: AppColors.divider.withOpacity(0.6),
          ),
          _buildLocationTile(),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    IconData icon,
    String title,
    Color iconColor, {
    String? trailingText,
    VoidCallback? onTap,
    bool isSwitch = false,
    bool? switchValue,
    ValueChanged<bool>? onSwitchChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isSwitch ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isSwitch)
                Switch.adaptive(
                  value: switchValue!,
                  onChanged: onSwitchChanged,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                  activeThumbColor: AppColors.primary,
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccentTagBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          trailingText,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: _kAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint.withOpacity(0.8),
                      size: 22,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openLocationPicker,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF059669),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '位置',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (_locationName != null && _locationName!.isNotEmpty)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          _locationName!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: _kAccent,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _locationName = null),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textHint.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '选择位置',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textHint,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint.withOpacity(0.8),
                      size: 22,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLocationPicker() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MapLocationPickerPage()),
    );
    if (res != null && mounted) {
      setState(() => _locationName = res.isEmpty ? null : res);
    }
  }
}

// ---------------------------------------------------------------------------
bool _isInlineTriggerBoundary(String value) {
  return RegExp(r'[\s，。！？、；：,.!?;:（(【\[]').hasMatch(value);
}

// ---------------------------------------------------------------------------
// Custom controller that styles #topic (cyan) and @mention (soft violet)
// ---------------------------------------------------------------------------
class _StyledPostController extends TextEditingController {
  final Set<String> _knownTopics = {};
  final Set<String> _knownMentions = {};

  void registerEntity(String trigger, String name) {
    if (trigger == '#') {
      _knownTopics.add(name);
    } else if (trigger == '@') {
      _knownMentions.add(name);
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return TextSpan(text: '', style: style);

    final baseStyle = style ?? const TextStyle();
    final segments = parsePostEntitySegments(
      text,
      topics: _knownTopics
          .map((name) => <String, dynamic>{'id': 0, 'name': name})
          .toList(),
      mentions: _knownMentions
          .map((name) => <String, dynamic>{'userId': 0, 'nickname': name})
          .toList(),
    );
    final spans = segments.map((segment) {
      final color = switch (segment.type) {
        PostEntityType.topic => kPostTopicColor,
        PostEntityType.mention => kPostMentionColor,
        PostEntityType.text => null,
      };
      return TextSpan(
        text: segment.text,
        style: color == null
            ? null
            : TextStyle(color: color, fontWeight: FontWeight.w600),
      );
    }).toList();

    return TextSpan(style: baseStyle, children: spans);
  }
}

// ---------------------------------------------------------------------------
// Suggestion dropdown widget (shown via Overlay)
// ---------------------------------------------------------------------------
class _SuggestionDropdown extends StatelessWidget {
  const _SuggestionDropdown({
    required this.layerLink,
    required this.items,
    required this.itemLabel,
    required this.onSelected,
    required this.onDismiss,
    this.itemAvatar,
    this.itemSubtitle,
  });

  final LayerLink layerLink;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) itemLabel;
  final String? Function(Map<String, dynamic>)? itemAvatar;
  final String? Function(Map<String, dynamic>)? itemSubtitle;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // 候选列表必须位于关闭层之上，否则点击候选只会关闭弹层。
        CompositedTransformFollower(
          link: layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(20, 8),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            color: AppColors.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: min(MediaQuery.of(context).size.width - 40, 280),
                maxHeight: 240,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: items.length.clamp(0, 20),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final avatar = itemAvatar?.call(item);
                  final subtitle = itemSubtitle?.call(item);
                  return InkWell(
                    onTap: () => onSelected(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          if (avatar != null && avatar.isNotEmpty) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundImage: NetworkImage(avatar),
                              backgroundColor: AppColors.background,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  itemLabel(item),
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      subtitle,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 11,
                                        color: AppColors.textHint,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
