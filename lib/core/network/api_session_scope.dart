import 'package:dio/dio.dart';

import 'api_client.dart';

const apiSessionChangedMessage = '账号已切换，请重新进入当前页面';

class ApiSessionChangedException implements Exception {
  const ApiSessionChangedException();

  @override
  String toString() => apiSessionChangedMessage;
}

/// 把一组读取、确认弹窗和写操作固定在发起时的登录会话。
///
/// 切换账号后，旧请求仍携带旧账号当时的认证头，但它的结果不能再写入当前
/// 页面；后续写操作也会在发出前被拦住，避免借用新账号认证继续旧流程。
class ApiSessionScope {
  ApiSessionScope()
      : session = apiSessionChanges.value,
        _authorization = apiClient.options.headers['Authorization'];

  final int session;
  final Object? _authorization;

  bool get current => session == apiSessionChanges.value;
  bool get authenticated => _authorization != null;

  Options get _options => Options(
        headers: <String, Object?>{'Authorization': _authorization},
      );

  void ensureCurrent() {
    if (!current) throw const ApiSessionChangedException();
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    ensureCurrent();
    final response = await apiClient.get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: _options,
    );
    ensureCurrent();
    return response;
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) async {
    ensureCurrent();
    final response = await apiClient.post<dynamic>(
      path,
      data: data,
      options: sendTimeout == null && receiveTimeout == null
          ? _options
          : Options(
              headers: <String, Object?>{'Authorization': _authorization},
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
            ),
    );
    ensureCurrent();
    return response;
  }

  Future<Response<dynamic>> put(String path, {Object? data}) async {
    ensureCurrent();
    final response =
        await apiClient.put<dynamic>(path, data: data, options: _options);
    ensureCurrent();
    return response;
  }

  Future<Response<dynamic>> patch(String path, {Object? data}) async {
    ensureCurrent();
    final response =
        await apiClient.patch<dynamic>(path, data: data, options: _options);
    ensureCurrent();
    return response;
  }

  Future<Response<dynamic>> delete(String path, {Object? data}) async {
    ensureCurrent();
    final response =
        await apiClient.delete<dynamic>(path, data: data, options: _options);
    ensureCurrent();
    return response;
  }
}

String apiSessionFailureMessage(Object error, String fallback) {
  if (error is ApiSessionChangedException) return apiSessionChangedMessage;
  if (error is DioException && error.response?.data is Map) {
    return ((error.response!.data as Map)['message'] ?? fallback).toString();
  }
  return fallback;
}
