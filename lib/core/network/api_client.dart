import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../utils/user_cache_utils.dart';

/// 优先用 baseUrlOverride（本地调试）；否则用 baseUrl（线上）。Android 模拟器连本机时请设 baseUrlOverride = 'http://10.0.2.2:8080'
String get _baseUrl {
  if (AppConstants.baseUrlOverride != null &&
      AppConstants.baseUrlOverride!.isNotEmpty) {
    return AppConstants.baseUrlOverride!;
  }
  return AppConstants.baseUrl;
}

final apiClient = Dio(BaseOptions(
  baseUrl: _baseUrl,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 15),
));

/// 401 时触发，用于主界面退出登录并刷新（见 main.dart）
final ValueNotifier<int> unauthorizedTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> apiSessionChanges = ValueNotifier<int>(0);
String? lastUnauthorizedMessage;

Future<void> _on401(int requestSession, dynamic data) async {
  final prefs = await SharedPreferences.getInstance();
  if (requestSession != apiSessionChanges.value) return;
  lastUnauthorizedMessage = data is Map ? data['message']?.toString() : null;
  setupApiClientToken(null);
  final clearedSession = apiSessionChanges.value;
  await Future.wait([
    prefs.remove(AppConstants.keyToken),
    prefs.remove(AppConstants.keyUserId),
    clearUserDependentCache(
      shouldClear: () => apiSessionChanges.value == clearedSession,
    ),
  ]);
  if (apiSessionChanges.value == clearedSession) unauthorizedTrigger.value++;
}

/// 初始化时调用：为已登录请求附加 Token；并设置 401 拦截（仅一次）
bool _interceptorAdded = false;
void setupApiClientToken(String? token) {
  apiClient.options.headers['Authorization'] =
      token != null ? 'Bearer $token' : null;
  apiSessionChanges.value++;
  if (!_interceptorAdded) {
    _interceptorAdded = true;
    apiClient.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['authSession'] = apiSessionChanges.value;
        handler.next(options);
      },
      onError: (error, handler) {
        final session = error.requestOptions.extra['authSession'];
        if (error.response?.statusCode == 401 &&
            (error.requestOptions.headers['Authorization']
                    ?.toString()
                    .isNotEmpty ??
                false) &&
            session is int &&
            session == apiSessionChanges.value &&
            error.requestOptions.headers['Authorization'] ==
                apiClient.options.headers['Authorization']) {
          _on401(session, error.response?.data);
        }
        return handler.next(error);
      },
    ));
  }
}

/// 后端统一响应
class ApiResult<T> {
  ApiResult({this.code, this.message, this.data});

  final int? code;
  final String? message;
  final T? data;

  bool get isOk => code == 0;
}
