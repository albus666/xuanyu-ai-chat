import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

const imSessionChangedMessage = '账号已切换，请返回后重新进入';

/// 一次读取/操作（含确认对话框）固定所属会话，不能借用切号后的认证信息。
class ImWorkflowRequest {
  final int session = apiSessionChanges.value;
  final Options options = Options(headers: {
    'Authorization': apiClient.options.headers['Authorization'],
  });

  bool get current => session == apiSessionChanges.value;

  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    final response =
        await apiClient.get(path, queryParameters: query, options: options);
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    return imResponseData(response.data);
  }

  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    final response = await apiClient.post(path, data: data, options: options);
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    return imResponseData(response.data);
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    final response = await apiClient.patch(path, data: data, options: options);
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    return imResponseData(response.data);
  }

  Future<Map<String, dynamic>> delete(String path, {Object? data}) async {
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    final response = await apiClient.delete(path, data: data, options: options);
    if (!current) throw const ImWorkflowFailure(imSessionChangedMessage);
    return imResponseData(response.data);
  }
}

/// 弹窗和底部浮层位于独立路由上，账号切换后必须立即隐藏旧账号内容与操作。
class ImWorkflowSessionBoundary extends StatelessWidget {
  const ImWorkflowSessionBoundary({
    super.key,
    required this.request,
    required this.child,
    required this.expiredBuilder,
  });

  final ImWorkflowRequest request;
  final Widget child;
  final WidgetBuilder expiredBuilder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: apiSessionChanges,
        builder: (context, _, __) =>
            request.current ? child : expiredBuilder(context),
      );
}

class ImWorkflowFailure implements Exception {
  const ImWorkflowFailure(this.message, {this.code});
  final String message;
  final int? code;
}

Map<String, dynamic> imResponseData(dynamic body) {
  if (body is! Map) throw const ImWorkflowFailure('返回数据异常，请重试');
  if (body['code'] != 0) {
    throw ImWorkflowFailure(body['message']?.toString() ?? '操作失败，请重试',
        code: body['code'] is num ? (body['code'] as num).toInt() : null);
  }
  if (body['data'] == null) return {};
  if (body['data'] is! Map) throw const ImWorkflowFailure('返回数据异常，请重试');
  return Map<String, dynamic>.from(body['data'] as Map);
}

List<Map<String, dynamic>> imResponseList(Map data, {String key = 'list'}) {
  final rows = data[key];
  if (rows is! List || rows.any((row) => row is! Map)) {
    throw const ImWorkflowFailure('列表数据异常，请重试');
  }
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

int? imFailureStatus(Object error) => error is DioException
    ? error.response?.statusCode
    : error is ImWorkflowFailure
        ? error.code
        : null;

String imFailureMessage(Object error, String fallback) {
  if (error is ImWorkflowFailure) return error.message;
  if (error is DioException && error.response?.data is Map) {
    return (error.response!.data as Map)['message']?.toString() ?? fallback;
  }
  return fallback;
}

/// 隐藏接口可能跳过无权限/已变更的记录，不能把整个提交列表当作成功。
Set<String> imConfirmedHiddenKeys(
    List<Map<String, dynamic>> records, Map data) {
  final requested = records.map((e) => '${e['type']}:${e['id']}').toSet();
  final skipped = imResponseList(data, key: 'skipped')
      .map((e) => '${e['type']}:${e['id']}')
      .toSet();
  final accepted = requested.difference(skipped);
  if (!requested.containsAll(skipped) ||
      data['hiddenCount'] != accepted.length) {
    throw const ImWorkflowFailure('删除结果待确认，请刷新列表');
  }
  return accepted;
}

class ImWorkflowRetry extends StatelessWidget {
  const ImWorkflowRetry(
      {super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试加载')),
        ]),
      );
}
