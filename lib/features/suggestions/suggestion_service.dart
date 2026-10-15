import 'dart:math';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';

class SuggestionValidationException implements Exception {
  const SuggestionValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps uploads, retries and the final write bound to the opening account.
class SuggestionService {
  SuggestionService()
      : scope = ApiSessionScope(),
        _authorization = apiClient.options.headers['Authorization'];

  static const maxImages = 6;
  static const maxContentLength = 2000;
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxVideoBytes = 100 * 1024 * 1024;
  final ApiSessionScope scope;
  final Object? _authorization;
  final CancelToken _cancelToken = CancelToken();

  bool get current => scope.current && !_cancelToken.isCancelled;

  static String newRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static void validate(
      {required String content, required int images, required bool hasVideo}) {
    if (content.trim().isEmpty && images == 0 && !hasVideo) {
      throw const SuggestionValidationException('请填写建议，或添加图片、视频');
    }
    if (content.runes.length > maxContentLength) {
      throw const SuggestionValidationException('建议文字不能超过2000字');
    }
    if (images > maxImages) {
      throw const SuggestionValidationException('最多添加6张图片');
    }
  }

  static Future<void> validateFile(XFile file, {required bool isVideo}) async {
    final extension = file.name.toLowerCase().split('.').last;
    final allowed = isVideo
        ? const {'mp4', 'mov', 'webm'}
        : const {'jpg', 'jpeg', 'png', 'webp', 'gif'};
    if (!allowed.contains(extension)) {
      throw SuggestionValidationException(
          isVideo ? '请选择MP4、MOV或WebM视频' : '请选择JPG、PNG、WebP或GIF图片');
    }
    final size = await file.length();
    if (size <= 0) {
      throw const SuggestionValidationException('文件为空，请重新选择');
    }
    if (size > (isVideo ? maxVideoBytes : maxImageBytes)) {
      throw SuggestionValidationException(
          isVideo ? '视频不能超过100MB，请选择较短的视频' : '每张图片不能超过10MB');
    }
  }

  Future<String> upload(XFile file,
      {required bool isVideo, required ProgressCallback onProgress}) async {
    scope.ensureCurrent();
    await validateFile(file, isVideo: isVideo);
    scope.ensureCurrent();
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
      'type': isVideo ? 'video' : 'image',
    });
    scope.ensureCurrent();
    final response = await apiClient.post<dynamic>(
      '/api/config/suggestions/upload',
      data: form,
      options: Options(
        headers: {'Authorization': _authorization},
        sendTimeout: const Duration(minutes: 6),
        receiveTimeout: const Duration(minutes: 2),
      ),
      cancelToken: _cancelToken,
      onSendProgress: (sent, total) {
        if (current) onProgress(sent, total);
      },
    );
    scope.ensureCurrent();
    final data = _data(response);
    final id = data['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const SuggestionValidationException('附件上传未完成，请重试');
    }
    return id;
  }

  Future<void> submit(
      {required String requestId,
      required String content,
      required List<String> attachmentIds}) async {
    validate(content: content, images: 0, hasVideo: attachmentIds.isNotEmpty);
    if (attachmentIds.length > maxImages + 1) {
      throw const SuggestionValidationException('最多添加6张图片和1个视频');
    }
    scope.ensureCurrent();
    final response = await scope.post('/api/config/suggestions', data: {
      'requestId': requestId,
      'content': content.trim(),
      'attachmentIds': attachmentIds,
    });
    _data(response);
  }

  Map<dynamic, dynamic> _data(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
      throw SuggestionValidationException(body is Map
          ? body['message']?.toString() ?? '提交失败，请重试'
          : '服务暂时不可用，请稍后重试');
    }
    return body['data'] as Map;
  }

  void cancel() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('suggestion page closed');
    }
  }
}
