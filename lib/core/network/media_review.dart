import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';

class MediaReviewException implements Exception {
  const MediaReviewException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 等待服务端媒体审核完成。
/// 公开内容默认等审核通过；私聊可 [acceptPending]，拿到 URL 后先发送。
Future<Map<String, dynamic>> awaitMediaReview(
  dynamic responseBody, {
  String? fallbackUrl,
  Duration timeout = const Duration(minutes: 4),
  bool acceptPending = false,
  Future<Response<dynamic>> Function(String path)? fetchReview,
}) async {
  Map<String, dynamic>? payload = _payloadFrom(responseBody);
  final reviewId = payload?['reviewId'];
  if (reviewId == null) {
    final url = payload?['url']?.toString() ?? fallbackUrl;
    if (url == null || url.isEmpty) throw Exception('媒体上传结果无效');
    return {...?payload, 'url': url};
  }

  final deadline = DateTime.now().add(timeout);
  while (true) {
    final state = payload?['reviewStatus']?.toString() ?? '';
    final message = payload?['message']?.toString();
    if (state == 'approved') {
      final url = payload?['url']?.toString();
      if (url == null || url.isEmpty) throw Exception('审核通过但媒体地址无效');
      return payload!;
    }
    final pendingUrl = payload?['url']?.toString() ?? fallbackUrl;
    if (acceptPending &&
        pendingUrl != null &&
        pendingUrl.isNotEmpty &&
        state != 'rejected' &&
        state != 'error') {
      return {...payload!, 'url': pendingUrl};
    }
    if (!acceptPending && state == 'manual_review') {
      throw const MediaReviewException('媒体正在人工复核，通过后才能公开发布');
    }
    if (state == 'rejected') {
      throw MediaReviewException(
          message?.isNotEmpty == true ? message! : '媒体包含违规风险，无法发布');
    }
    if (state == 'error') {
      throw Exception(message?.isNotEmpty == true ? message : '媒体安全审核失败，请重试');
    }
    if (DateTime.now().isAfter(deadline)) {
      throw Exception(
          state == 'manual_review' ? '媒体正在人工复核，请稍后再试' : '媒体审核超时，请稍后再试');
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      final path = '/api/config/media-review/$reviewId';
      final response =
          await (fetchReview != null ? fetchReview(path) : apiClient.get(path));
      payload = _payloadFrom(response.data) ?? payload;
    } on DioException catch (error) {
      final next = _payloadFrom(error.response?.data);
      if (next != null) {
        payload = next;
        continue;
      }
      final message = error.response?.data is Map
          ? (error.response?.data as Map)['message']?.toString()
          : null;
      throw Exception(message?.isNotEmpty == true ? message : '无法查询媒体审核结果');
    }
  }
}

Map<String, dynamic>? _payloadFrom(dynamic body) {
  if (body is! Map) return null;
  final raw = body['data'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (body.containsKey('reviewStatus') || body.containsKey('url')) {
    return Map<String, dynamic>.from(body);
  }
  return null;
}
