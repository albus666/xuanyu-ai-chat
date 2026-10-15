import 'package:dio/dio.dart';

import '../../../core/cache/account_scoped_json_cache.dart';
import '../../../core/network/api_client.dart';
import '../paipan/models/region.dart';
import 'astrology_models.dart';

class AstrologyServiceException implements Exception {
  const AstrologyServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AstrologyService {
  AstrologyService._();

  static final Map<String, AstrologyChartData> _cache = {};
  static final Map<String, Future<AstrologyChartData>> _inFlight = {};

  static Future<AstrologyChartData> calculate(
    AstrologyProfile profile, {
    AstrologyChartType chartType = AstrologyChartType.natal,
    DateTime? targetDateTime,
    Region? eventPlace,
  }) async {
    final request = profile.toRequest();
    request['chartType'] = chartType.code;
    if (chartType.usesTargetDate || chartType == AstrologyChartType.current) {
      final target = targetDateTime ?? DateTime.now();
      request['targetDate'] =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      request['targetTime'] =
          '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
    }
    if (chartType.usesEventPlace && eventPlace != null) {
      request['targetPlace'] = eventPlace.extPath;
      request['targetLongitude'] = eventPlace.lng;
      request['targetLatitude'] = eventPlace.lat;
    }
    final persistentKey =
        await AccountScopedJsonCache.keyFor('astrology', request);
    final key = persistentKey.value;
    final cached = _cache[key];
    if (cached != null) return cached;

    final persisted = await AccountScopedJsonCache.read(persistentKey);
    if (persisted != null) {
      try {
        final result = AstrologyChartData.fromJson(persisted);
        if (result.planets.length == 10 && result.houses.length == 12) {
          _remember(key, result);
          return result;
        }
      } catch (_) {}
      await AccountScopedJsonCache.remove(persistentKey);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _fetch(request, persistentKey);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  static Future<AstrologyChartData> _fetch(
    Map<String, dynamic> request,
    AccountJsonCacheKey cacheKey,
  ) async {
    try {
      final response = await apiClient.post<dynamic>(
        '/api/fortune/astrology/chart',
        data: request,
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final payload = response.data;
      if (payload is! Map || payload['code'] != 0 || payload['data'] is! Map) {
        throw AstrologyServiceException(
          payload is Map &&
                  payload['message']?.toString().trim().isNotEmpty == true
              ? payload['message'].toString()
              : '星盘计算失败，请稍后重试',
        );
      }
      final result = AstrologyChartData.fromJson(
        Map<String, dynamic>.from(payload['data'] as Map),
      );
      if (result.planets.length != 10 || result.houses.length != 12) {
        throw const AstrologyServiceException('星盘数据不完整，已停止展示');
      }
      _remember(cacheKey.value, result);
      await AccountScopedJsonCache.write(
        cacheKey,
        Map<String, dynamic>.from(payload['data'] as Map),
      );
      return result;
    } on AstrologyServiceException {
      rethrow;
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message']?.toString() : null;
      throw AstrologyServiceException(
        message?.trim().isNotEmpty == true ? message! : '网络异常，请稍后重试',
      );
    } catch (_) {
      throw const AstrologyServiceException('星盘计算失败，请稍后重试');
    }
  }

  static void _remember(String key, AstrologyChartData result) {
    if (_cache.length >= 32) _cache.remove(_cache.keys.first);
    _cache[key] = result;
  }

  static void clearMemory() {
    _cache.clear();
    _inFlight.clear();
  }
}
