import 'utils/bazi_result.dart';

/// 八字排盘完全在本地计算。登录预热后复用同一个结果，避免进入结果页时重复计算。
class BaziCalculationCache {
  BaziCalculationCache._();

  static const _maxEntries = 24;
  static final Map<String, BaziResult> _cache = {};
  static final Map<String, Future<BaziResult>> _inFlight = {};

  static BaziResult? peek(DateTime birthDateTime, {required bool isFemale}) {
    final key = _key(birthDateTime, isFemale);
    final result = _cache[key];
    if (result != null) {
      _cache
        ..remove(key)
        ..[key] = result;
    }
    return result;
  }

  static Future<BaziResult> calculate(
    DateTime birthDateTime, {
    required bool isFemale,
  }) {
    final key = _key(birthDateTime, isFemale);
    final cached = peek(birthDateTime, isFemale: isFemale);
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = Future<BaziResult>.sync(
      () => computeBaziResult(birthDateTime, isFemale: isFemale),
    ).then((result) {
      if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    });
    _inFlight[key] = future;
    future.then<void>(
      (_) {
        if (identical(_inFlight[key], future)) _inFlight.remove(key);
      },
      onError: (_) {
        if (identical(_inFlight[key], future)) _inFlight.remove(key);
      },
    );
    return future;
  }

  static void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  static String _key(DateTime value, bool isFemale) =>
      '${value.toIso8601String()}|${isFemale ? 1 : 0}';
}
