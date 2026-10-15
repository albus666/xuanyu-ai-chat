import 'package:dio/dio.dart';

import '../../../core/cache/account_scoped_json_cache.dart';
import '../../../core/network/api_client.dart';
import 'qizheng_models.dart';

class QizhengServiceException implements Exception {
  const QizhengServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class QizhengService {
  QizhengService._();

  static final Map<String, QizhengChartData> _cache = {};
  static final Map<String, Future<QizhengChartData>> _inFlight = {};

  static Future<QizhengChartData> calculate(
    QizhengProfile profile, {
    QizhengChartType chartType = QizhengChartType.natal,
    QizhengNodeMode nodeMode = QizhengNodeMode.trueNode,
    QizhengLifeMode lifeMode = QizhengLifeMode.ascSunLock,
    DateTime? targetDateTime,
  }) async {
    final request = profile.toRequest()
      ..['chartType'] = chartType.code
      ..['nodeMode'] = nodeMode.code
      ..['lifeMode'] = lifeMode.code;
    if (chartType != QizhengChartType.natal) {
      final target = targetDateTime ?? DateTime.now();
      request['targetDate'] =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      request['targetTime'] =
          '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
    }
    final persistentKey =
        await AccountScopedJsonCache.keyFor('qizheng', request);
    final cacheKey = persistentKey.value;
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final persisted = await AccountScopedJsonCache.read(persistentKey);
    if (persisted != null) {
      try {
        final chart = QizhengChartData.fromJson(persisted);
        if (_isComplete(chart)) {
          _remember(cacheKey, chart);
          return chart;
        }
      } catch (_) {}
      await AccountScopedJsonCache.remove(persistentKey);
    }

    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;
    final future = _fetch(request, persistentKey);
    _inFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[cacheKey], future)) _inFlight.remove(cacheKey);
    }
  }

  static Future<QizhengChartData> _fetch(
    Map<String, dynamic> request,
    AccountJsonCacheKey cacheKey,
  ) async {
    try {
      final response = await apiClient.post<dynamic>(
        '/api/fortune/qizheng/chart',
        data: request,
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      final payload = response.data;
      if (payload is! Map || payload['code'] != 0 || payload['data'] is! Map) {
        throw QizhengServiceException(
          payload is Map &&
                  payload['message']?.toString().trim().isNotEmpty == true
              ? payload['message'].toString()
              : '七政四余排盘失败，请稍后重试',
        );
      }
      final chart = QizhengChartData.fromJson(
        Map<String, dynamic>.from(payload['data'] as Map),
      );
      if (!_isComplete(chart)) {
        throw const QizhengServiceException('排盘数据不完整，已停止展示');
      }
      _remember(cacheKey.value, chart);
      await AccountScopedJsonCache.write(
        cacheKey,
        Map<String, dynamic>.from(payload['data'] as Map),
      );
      return chart;
    } on QizhengServiceException {
      rethrow;
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message']?.toString() : null;
      throw QizhengServiceException(
        message?.trim().isNotEmpty == true ? message! : '网络异常，请稍后重试',
      );
    } catch (_) {
      throw const QizhengServiceException('七政四余排盘失败，请稍后重试');
    }
  }

  static bool _isComplete(QizhengChartData chart) =>
      chart.bodies.length == 11 &&
      chart.palaces.length == 12 &&
      chart.mansions.length == 28;

  static void _remember(String key, QizhengChartData chart) {
    if (_cache.length >= 32) _cache.remove(_cache.keys.first);
    _cache[key] = chart;
  }

  static void clearMemory() {
    _cache.clear();
    _inFlight.clear();
  }
}
