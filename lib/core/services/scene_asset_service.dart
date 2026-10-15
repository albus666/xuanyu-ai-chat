import 'dart:async';

import 'package:xuanyu/core/network/api_client.dart';

/// 多个卡片共用同一个轮询 Future，避免同一场景在一个页面重复请求。
class SceneAssetService {
  SceneAssetService._();

  static final Map<String, String> _readyUrls = {};
  static final Map<String, Future<String?>> _inflight = {};

  static Future<String?> resolve({
    required String sceneToken,
    String initialUrl = '',
  }) {
    final token = sceneToken.trim();
    final direct = initialUrl.trim();
    if (direct.isNotEmpty) {
      _readyUrls[token] = direct;
      return Future.value(direct);
    }
    if (token.isEmpty) return Future.value(null);
    final ready = _readyUrls[token];
    if (ready != null && ready.isNotEmpty) return Future.value(ready);
    return _inflight.putIfAbsent(token, () => _poll(token));
  }

  static Future<String?> refresh(String sceneToken) {
    final token = sceneToken.trim();
    if (token.isEmpty) return Future.value(null);
    _readyUrls.remove(token);
    return _inflight.putIfAbsent(token, () => _poll(token));
  }

  static Future<String?> _poll(String token) async {
    try {
      for (var attempt = 0; attempt < 15; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        try {
          final response = await apiClient.get<Map<String, dynamic>>(
            '/api/fortune/scene-assets/$token',
          );
          final body = response.data;
          final data = body?['data'];
          if (body?['code'] != 0 || data is! Map) continue;
          final status = data['imageStatus']?.toString() ?? '';
          final url = data['imageUrl']?.toString().trim() ?? '';
          if (status == 'ready' && url.isNotEmpty) {
            _readyUrls[token] = url;
            return url;
          }
          if (status == 'not_found' ||
              status == 'unavailable' ||
              status == 'failed') {
            return null;
          }
        } catch (_) {
          // 网络短暂不可用时继续保留内置场景，并在下一轮重试。
        }
      }
      return null;
    } finally {
      _inflight.remove(token);
    }
  }
}
