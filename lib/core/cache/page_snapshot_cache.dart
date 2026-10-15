import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../network/api_client.dart';

/// Small display snapshots. Never use these values to authorize a mutation.
/// Memory is session-scoped; optional disk snapshots are account-scoped.
class PageSnapshotCache {
  PageSnapshotCache(
    this.namespace, {
    Map<String, dynamic> parameters = const {},
    this.maxAge = const Duration(minutes: 15),
    this.persist = false,
  })  : _session = apiSessionChanges.value,
        _authorization = apiClient.options.headers['Authorization'],
        _signature =
            sha256.convert(utf8.encode(_canonical(parameters))).toString() {
    if (!_listening) {
      _listening = true;
      apiSessionChanges.addListener(clearMemory);
    }
  }

  final String namespace;
  final Duration maxAge;
  final bool persist;
  final int _session;
  final Object? _authorization;
  final String _signature;
  static const _prefix = 'page_snapshot_v1_';
  static const _maxBytes = 256 * 1024;
  static const _maxEntries = 24;
  static const _maxTotalBytes = 2 * 1024 * 1024;
  static bool _listening = false;
  static final Map<String, String> _memory = {};
  static Future<void> _diskQueue = Future.value();
  String get _memoryKey => '$_session:$namespace:$_signature';
  bool get current =>
      _session == apiSessionChanges.value &&
      _authorization == apiClient.options.headers['Authorization'];

  Future<Map<String, dynamic>?> read() async {
    if (!current) return null;
    try {
      final memory = _memory[_memoryKey];
      if (memory != null) {
        final result = _decode(memory);
        if (result != null) return result;
        _memory.remove(_memoryKey);
      }
      if (!persist) return null;
      final prefs = await SharedPreferences.getInstance();
      if (!current) return null;
      final key = _diskKey(prefs);
      if (key == null) return null;
      final raw = prefs.getString(key);
      if (raw == null || raw.length > _maxBytes) return null;
      final result = _decode(raw);
      if (result != null && current) {
        _remember(raw);
        return result;
      }
    } catch (_) {
      // Corrupt, missing or unavailable storage must not block the live request.
    }
    return null;
  }

  Future<void> write(Map<String, dynamic> payload) async {
    if (!current) return;
    try {
      final raw = jsonEncode({
        'cachedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        'payload': payload,
      });
      if (utf8.encode(raw).length > _maxBytes) return;
      _remember(raw);
      if (!persist) return;
      await _serializeDisk(() async {
        if (!current) return;
        final prefs = await SharedPreferences.getInstance();
        if (!current) return;
        final key = _diskKey(prefs);
        if (key == null) return;
        await prefs.setString(key, raw);
        if (!current) {
          await prefs.remove(key);
          return;
        }
        final keys =
            prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
        final entries = <(String, int, int)>[];
        for (final key in keys) {
          final value = prefs.getString(key) ?? '';
          int timestamp = 0;
          try {
            timestamp = (jsonDecode(value)['cachedAt'] as num).toInt();
          } catch (_) {}
          entries.add((key, timestamp, utf8.encode(value).length));
        }
        entries.sort((a, b) => a.$2.compareTo(b.$2));
        var total = entries.fold<int>(0, (sum, item) => sum + item.$3);
        var remaining = entries.length;
        for (final entry in entries) {
          if (remaining <= _maxEntries && total <= _maxTotalBytes) break;
          await prefs.remove(entry.$1);
          remaining--;
          total -= entry.$3;
        }
      });
    } catch (_) {}
  }

  Future<void> remove() async {
    _memory.remove(_memoryKey);
    if (!persist || !current) return;
    await _serializeDisk(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!current) return;
      final key = _diskKey(prefs);
      if (key != null) await prefs.remove(key);
    });
  }

  static void clearMemory() => _memory.clear();

  String? _diskKey(SharedPreferences prefs) {
    final user = prefs.getInt(AppConstants.keyUserId);
    final token = prefs.getString(AppConstants.keyToken);
    if (user == null || token == null || _authorization != 'Bearer $token') {
      return null;
    }
    // Include an opaque credential fingerprint so an account switch between
    // preference writes and setupApiClientToken cannot cross disk ownership.
    return '$_prefix${user}_${sha256.convert(utf8.encode('$namespace:$_signature:$_authorization'))}';
  }

  static Future<void> clearAll() async {
    clearMemory();
    await _serializeDisk(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key
          in prefs.getKeys().where((key) => key.startsWith(_prefix)).toList()) {
        await prefs.remove(key);
      }
    });
  }

  void _remember(String raw) {
    if (!current) return;
    _memory.remove(_memoryKey);
    _memory[_memoryKey] = raw;
    while (_memory.length > _maxEntries ||
        _memory.values.fold<int>(
              0,
              (sum, value) => sum + utf8.encode(value).length,
            ) >
            _maxTotalBytes) {
      _memory.remove(_memory.keys.first);
    }
  }

  Map<String, dynamic>? _decode(String raw) {
    final entry = jsonDecode(raw);
    if (entry is! Map ||
        entry['cachedAt'] is! num ||
        entry['payload'] is! Map) {
      return null;
    }
    final age = DateTime.now().toUtc().millisecondsSinceEpoch -
        (entry['cachedAt'] as num).toInt();
    if (age < 0 || age > maxAge.inMilliseconds) return null;
    return Map<String, dynamic>.from(entry['payload'] as Map);
  }

  static Future<void> _serializeDisk(Future<void> Function() action) {
    final work = _diskQueue.then((_) => action()).catchError((_) {});
    _diskQueue = work;
    return work;
  }

  static String _canonical(dynamic value) {
    dynamic ordered(dynamic value) {
      if (value is Map) {
        final keys = value.keys.map((key) => key.toString()).toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return jsonEncode(ordered(value));
  }
}
