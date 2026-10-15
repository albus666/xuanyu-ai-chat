import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// 账号隔离的小型 JSON 缓存。
///
/// 命盘接口返回的数据量不大，使用应用私有的 SharedPreferences 可以避免
/// 引入新的数据库依赖。缓存键包含用户 ID、业务命名空间、缓存协议版本和
/// 请求摘要，切换账号时不会命中其他账号的数据。
class AccountScopedJsonCache {
  AccountScopedJsonCache._();

  static const _root = 'fortune_chart_cache_v2_';
  static const _schemaVersion = 2;
  static final Map<String, Map<String, dynamic>> _memory = {};

  static Future<AccountJsonCacheKey> keyFor(
    String namespace,
    Map<String, dynamic> request,
  ) async {
    int? userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt(AppConstants.keyUserId);
    } catch (_) {
      // 纯 Dart 单元测试或插件尚未完成注册时退化为仅内存缓存。
    }
    final signature = _hash(_canonicalJson(request));
    return AccountJsonCacheKey(
      value:
          '$_root${userId ?? 'guest'}_${namespace}_v${_schemaVersion}_$signature',
      userId: userId,
    );
  }

  static Future<Map<String, dynamic>?> read(
    AccountJsonCacheKey key, {
    Duration maxAge = const Duration(days: 7),
  }) async {
    final memory = _memory[key.value];
    if (memory != null && !_expired(memory, maxAge)) {
      final payload = memory['payload'];
      if (payload is Map) return Map<String, dynamic>.from(payload);
    }

    if (!key.canPersist) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key.value);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final entry = Map<String, dynamic>.from(decoded);
      if (_expired(entry, maxAge) || entry['payload'] is! Map) {
        await prefs.remove(key.value);
        _memory.remove(key.value);
        return null;
      }
      _memory[key.value] = entry;
      return Map<String, dynamic>.from(entry['payload'] as Map);
    } catch (_) {
      await prefs.remove(key.value);
      _memory.remove(key.value);
      return null;
    }
  }

  static Future<void> write(
    AccountJsonCacheKey key,
    Map<String, dynamic> payload, {
    int maxEntriesPerNamespace = 18,
  }) async {
    final entry = <String, dynamic>{
      'cachedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    _memory[key.value] = entry;
    if (!key.canPersist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key.value, jsonEncode(entry));
    await _trim(
      prefs,
      key.namespacePrefix,
      maxEntries: maxEntriesPerNamespace,
    );
  }

  static Future<void> remove(AccountJsonCacheKey key) async {
    _memory.remove(key.value);
    if (!key.canPersist) return;
    await (await SharedPreferences.getInstance()).remove(key.value);
  }

  static void clearMemory() => _memory.clear();

  static Future<void> clearForUser(int userId) async {
    final prefix = '$_root${userId}_';
    _memory.removeWhere((key, _) => key.startsWith(prefix));
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
    await Future.wait(keys.map(prefs.remove));
  }

  static bool _expired(Map<String, dynamic> entry, Duration maxAge) {
    final cachedAt = DateTime.tryParse(entry['cachedAt']?.toString() ?? '');
    return cachedAt == null ||
        DateTime.now().toUtc().difference(cachedAt) > maxAge;
  }

  static Future<void> _trim(
    SharedPreferences prefs,
    String prefix, {
    required int maxEntries,
  }) async {
    final keys =
        prefs.getKeys().where((key) => key.startsWith(prefix)).toList();
    if (keys.length <= maxEntries) return;
    final dated = <(String, DateTime)>[];
    for (final key in keys) {
      DateTime date = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      try {
        final decoded = jsonDecode(prefs.getString(key) ?? '');
        if (decoded is Map) {
          date =
              DateTime.tryParse(decoded['cachedAt']?.toString() ?? '') ?? date;
        }
      } catch (_) {}
      dated.add((key, date));
    }
    dated.sort((a, b) => a.$2.compareTo(b.$2));
    final removeCount = dated.length - maxEntries;
    for (var index = 0; index < removeCount; index++) {
      _memory.remove(dated[index].$1);
      await prefs.remove(dated[index].$1);
    }
  }

  static String _canonicalJson(dynamic value) {
    dynamic normalize(dynamic item) {
      if (item is Map) {
        final keys = item.keys.map((key) => key.toString()).toList()..sort();
        return <String, dynamic>{
          for (final key in keys) key: normalize(item[key]),
        };
      }
      if (item is Iterable) return item.map(normalize).toList();
      return item;
    }

    return jsonEncode(normalize(value));
  }

  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class AccountJsonCacheKey {
  const AccountJsonCacheKey({required this.value, required this.userId});

  final String value;
  final int? userId;

  bool get canPersist => userId != null;

  String get namespacePrefix {
    final separator = value.lastIndexOf('_v');
    return separator < 0 ? value : value.substring(0, separator + 1);
  }
}
