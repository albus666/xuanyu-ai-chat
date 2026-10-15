import 'package:dio/dio.dart';
import 'package:xuanyu/core/cache/account_scoped_json_cache.dart';
import 'package:xuanyu/core/network/api_client.dart';

import 'ziwei_models.dart';

class ZiweiServiceException implements Exception {
  const ZiweiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ZiweiService {
  ZiweiService._();

  static const _maxMemoryCacheEntries = 96;
  static final Map<String, ZiweiChartData> _memoryCache = {};
  static final Map<String, Future<ZiweiChartData>> _inFlight = {};

  static Future<ZiweiChartData> calculate({
    required ZiweiProfile profile,
    required DateTime targetDate,
    required int targetTimeIndex,
  }) async {
    final request = <String, dynamic>{
      'birthDate': _date(profile.effectiveBirthDate),
      'birthTimeIndex': profile.birthTimeIndex,
      'gender': profile.gender,
      'targetDate': _date(targetDate),
      'targetTimeIndex': targetTimeIndex,
      'fixLeap': profile.settings.fixLeap,
      'astroType': profile.settings.astroType,
      'config': profile.settings.toRequestConfig(),
    };
    final cacheKey = await AccountScopedJsonCache.keyFor('ziwei', request);
    final key = cacheKey.value;
    final cached = _memoryCache[key];
    if (cached != null) {
      _memoryCache
        ..remove(key)
        ..[key] = cached;
      return cached;
    }

    final persisted = await AccountScopedJsonCache.read(cacheKey);
    if (persisted != null) {
      try {
        final result = ZiweiChartData.fromJson(persisted);
        if (result.astrolabe.palaces.length == 12) {
          _remember(key, result);
          return result;
        }
      } catch (_) {}
      await AccountScopedJsonCache.remove(cacheKey);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _fetch(request, cacheKey);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  static Future<ZiweiChartData> _fetch(
    Map<String, dynamic> request,
    AccountJsonCacheKey cacheKey,
  ) async {
    try {
      final response = await apiClient.post<dynamic>(
        '/api/fortune/ziwei/chart',
        data: request,
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final payload = response.data;
      if (payload is! Map) {
        throw const ZiweiServiceException('暂时无法完成排盘，请稍后重试');
      }
      final map = Map<String, dynamic>.from(payload);
      if (map['code'] != 0 || map['data'] is! Map) {
        throw ZiweiServiceException(
          map['message']?.toString().trim().isNotEmpty == true
              ? map['message'].toString()
              : '排盘失败，请稍后重试',
        );
      }
      final result = ZiweiChartData.fromJson(
        Map<String, dynamic>.from(map['data'] as Map),
      );
      if (result.astrolabe.palaces.length != 12) {
        throw const ZiweiServiceException('暂时无法完成排盘，请稍后重试');
      }
      _remember(cacheKey.value, result);
      await AccountScopedJsonCache.write(
        cacheKey,
        Map<String, dynamic>.from(map['data'] as Map),
      );
      return result;
    } on ZiweiServiceException {
      rethrow;
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message']?.toString() : null;
      throw ZiweiServiceException(
        message?.trim().isNotEmpty == true ? message! : '网络异常，请稍后重试',
      );
    } catch (_) {
      throw const ZiweiServiceException('排盘失败，请稍后重试');
    }
  }

  static void _remember(String key, ZiweiChartData result) {
    if (_memoryCache.length >= _maxMemoryCacheEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = result;
  }

  static void clearMemory() {
    _memoryCache.clear();
    _inFlight.clear();
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
