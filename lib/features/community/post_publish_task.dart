import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../core/network/api_client.dart';
import '../../core/network/media_review.dart';
import '../../core/notification/app_notifications.dart';
import '../../core/utils/app_toast.dart';
import 'post_draft_store.dart';
import 'post_publish_settings_page.dart';

/// 每个任务固定所属账号；本地保存完成之后才能离开编辑页。
class PostPublishTask {
  PostPublishTask({required this.store, required Map<String, dynamic> draft})
      : _draft = PostDraftStore.copy(draft),
        _session = apiSessionChanges.value,
        _authorization = apiClient.options.headers['Authorization'];

  final PostDraftStore store;
  Map<String, dynamic> _draft;
  final int _session;
  final dynamic _authorization; // 只在内存中使用，禁止写入草稿或日志。
  bool _prepared = false;
  Future<void>? _execution;
  static final _running = <String, Future<void>>{};
  static final _completed = <String>{};

  String get id => _draft['id'] as String;
  String get _key => '${store.storageKey}:$id';
  static bool isRunning(PostDraftStore store, String id) =>
      _running.containsKey('${store.storageKey}:$id');
  static bool isCompleted(PostDraftStore store, String id) =>
      _completed.contains('${store.storageKey}:$id');
  bool get _current =>
      store.ownerId != null &&
      _authorization != null &&
      _authorization == apiClient.options.headers['Authorization'] &&
      _session == apiSessionChanges.value;

  void _checkSession() {
    if (!_current) throw const _PublishError('账号已切换，作品已保留，请回原账号恢复发布');
  }

  Options _options(Duration timeout) => Options(
        headers: {'Authorization': _authorization},
        receiveTimeout: timeout,
      );

  Future<void> prepare() async {
    if (_prepared) return;
    _draft = await store.stage(_draft);
    _prepared = true;
  }

  static Future<void> run(PostPublishTask task) =>
      task._execution ??= task._start();

  Future<void> _start() {
    if (_completed.contains(_key)) return Future<void>.value();
    if (_running.containsKey(_key)) return _running[_key]!;
    final operation = _execute().whenComplete(() {
      _running.remove(_key);
      PostDraftStore.changes.value++;
    });
    _running[_key] = operation;
    return operation;
  }

  void _toast(String message) {
    // 后台无界面时只保留记录/本地通知，不调用依赖 Overlay 的提示。
    if (_current && Get.key.currentState?.overlay != null) {
      showGlobalAppToast(message, duration: const Duration(seconds: 5));
    }
  }

  Future<void> _execute() async {
    var posting = false;
    var confirmed = false;
    try {
      await prepare();
      _checkSession();
      final audio = _draft['audio'] as String?;
      final video = _draft['video'] as String?;
      final images = ((_draft['images'] as List?) ?? []).cast<String>();
      if ((audio != null ? 1 : 0) +
              (video != null ? 1 : 0) +
              (images.isNotEmpty ? 1 : 0) >
          1) {
        throw const _PublishError('附件类型冲突，请恢复草稿后重新选择');
      }
      final paths = [
        if (audio != null) audio,
        if (video != null) video,
        ...images
      ];
      for (final path in paths) {
        if (!await File(path).exists()) {
          throw const _PublishError('附件已失效，请恢复草稿后重新选择，作品尚未发布');
        }
      }
      _checkSession();
      await store.mark(id, 'uploading');
      final urls = <String>[];
      final covers = <String>[];
      final kind = audio != null
          ? 'audio'
          : video != null
              ? 'video'
              : 'image';
      for (final path in paths) {
        _checkSession();
        final result = await _upload(File(path), kind);
        urls.add(result['url']!);
        if (result['coverUrl']?.isNotEmpty == true) {
          covers.add(result['coverUrl']!);
        }
      }
      final settings = PostPublishSettings.fromJson(_draft['settings']);
      final content = (_draft['content'] as String? ?? '').trim();
      final topics = (_draft['topics'] as Map?) ?? {};
      final mentions = (_draft['mentions'] as Map?) ?? {};
      final mentioned = [
        for (final entry in mentions.entries)
          if (content.contains('@${entry.key}'))
            {'userId': entry.value, 'nickname': entry.key},
      ];
      _checkSession();
      await store.mark(id, 'publishing');
      _checkSession();
      posting = true;
      final response = await apiClient.post(
        '/api/community/post',
        options: _options(const Duration(minutes: 2)),
        data: {
          'content': content,
          'mediaUrls': urls,
          'mediaCoverUrls': covers,
          'mediaType': urls.isEmpty
              ? null
              : video != null
                  ? 'video'
                  : audio != null
                      ? 'audio'
                      : 'image_text',
          if (audio != null)
            'audioDurationSeconds': _draft['audioSeconds'] ?? 0,
          'visibility': settings.visibility,
          'allowComment': settings.allowComment,
          'publishSettings': settings.toJson(),
          if (_draft['component'] != null) 'component': _draft['component'],
          'topicIds': {
            for (final entry in topics.entries)
              if (content.contains('#${entry.key}')) entry.value,
          }.toList(),
          if (mentioned.isNotEmpty) ...{
            'mentionedUserIds':
                mentioned.map((item) => item['userId']).toSet().toList(),
            'mentionedUsers': mentioned,
          },
          if (_draft['location']?.toString().isNotEmpty == true) ...{
            'locationCode': _draft['location'],
            'locationSource': 'user',
          },
        },
      );
      final body = response.data;
      if (body is Map && body['code'] != null && body['code'] != 0) {
        posting = false;
        throw const _PublishError('发布未成功，作品已保留，请稍后恢复重试');
      }
      if (body is! Map || body['data'] is! Map || body['data']['id'] == null) {
        throw const _PublishError('发布结果待确认');
      }
      confirmed = true;
      _completed.add(_key);
      await store.complete(id);
      _toast('发布成功，作品已展示');
      if (_current) {
        try {
          await showPostPublishSuccess(message: '发布成功，作品已展示');
        } catch (_) {}
      }
    } catch (error) {
      if (confirmed) {
        _toast('作品已发布，请勿重复发布');
        return;
      }
      final rejected = error is DioException &&
          (error.response?.statusCode ?? 0) >= 400 &&
          (error.response?.statusCode ?? 0) < 500;
      final uncertain = posting && !rejected;
      final message = uncertain
          ? '发布结果待确认，请先查看自己的作品，避免重复发布'
          : error is _PublishError
              ? error.message
              : error is MediaReviewException
                  ? '${error.message}，内容已保留，可在发布页恢复'
                  : '发布未完成，内容已保留，可在发布页恢复';
      if (_prepared) {
        try {
          await store.mark(id, uncertain ? 'uncertain' : 'failed',
              error: message);
        } catch (_) {}
      }
      _toast(message);
      if (_current) {
        try {
          await showPostPublishFailure(message);
        } catch (_) {}
      }
    }
  }

  Future<Map<String, String>> _upload(File file, String kind) async {
    final ext =
        RegExp(r'\.[a-zA-Z0-9]{1,8}$').firstMatch(file.path)?.group(0) ??
            (kind == 'audio'
                ? '.m4a'
                : kind == 'video'
                    ? '.mp4'
                    : '.jpg');
    final limit = kind == 'video'
        ? 100
        : kind == 'audio'
            ? 30
            : 15;
    if (await file.length() > limit * 1024 * 1024) {
      throw _PublishError('请选择不超过$limit MB的原文件');
    }
    _checkSession();
    final response = await apiClient.post(
      '/api/config/presign-upload',
      data: {
        'type': kind,
        'ext': ext.toLowerCase(),
        'moderationScope': 'public'
      },
      options: _options(const Duration(seconds: 30)),
    );
    _checkSession();
    final body = response.data;
    if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
      throw const _PublishError('获取上传链接失败，作品已保留');
    }
    final data = body['data'] as Map;
    final uploadUrl = data['uploadUrl'] as String?;
    final url = data['url'] as String?;
    final key = data['objectKey'] as String?;
    if (uploadUrl == null || url == null || key == null) {
      throw const _PublishError('上传链接无效，作品已保留');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.putUrl(Uri.parse(uploadUrl));
      _checkSession();
      request.contentLength = await file.length();
      await request
          .addStream(file.openRead())
          .timeout(const Duration(minutes: 5));
      final result = await request.close().timeout(const Duration(minutes: 5));
      await result.drain<void>().timeout(const Duration(seconds: 30));
      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw const _PublishError('附件上传失败，作品已保留');
      }
    } finally {
      client.close(force: true);
    }
    _checkSession();
    final confirm = await apiClient.post('/api/config/confirm-upload',
        data: {'objectKey': key},
        options: _options(const Duration(minutes: 2)));
    _checkSession();
    if (confirm.data is! Map || confirm.data['code'] != 0) {
      throw const _PublishError('附件确认失败，作品已保留');
    }
    final reviewed =
        Map<String, dynamic>.from(confirm.data['data'] as Map? ?? {});
    return {
      'url': (reviewed['url'] ?? url).toString(),
      if (reviewed['coverUrl'] != null)
        'coverUrl': reviewed['coverUrl'].toString(),
    };
  }
}

class _PublishError implements Exception {
  const _PublishError(this.message);
  final String message;
}
