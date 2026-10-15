import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';

class AppContentConfig {
  AppContentConfig._();

  static Map<String, dynamic> _config = {};
  static DateTime? _loadedAt;
  static Future<Map<String, dynamic>>? _pending;
  static bool _diskRead = false;
  static const _diskKey = 'public_app_content_config_v1';
  static const _freshFor = Duration(minutes: 2);
  static const _maxAge = Duration(days: 7);
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Map<String, dynamic> get current => _config;

  /// Public configuration is available from disk while it is refreshed.
  /// A failed refresh never replaces a valid snapshot or suppresses later retries.
  static Future<Map<String, dynamic>> load({bool force = false}) async {
    if (!_diskRead) {
      _diskRead = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_diskKey);
        if (raw != null && _config.isEmpty) {
          final saved = jsonDecode(raw);
          final date = DateTime.tryParse(saved['cachedAt']?.toString() ?? '');
          if (date != null &&
              !date.isAfter(DateTime.now()) &&
              DateTime.now().difference(date) < _maxAge &&
              saved['data'] is Map) {
            _config = Map<String, dynamic>.from(saved['data']);
            _loadedAt = date;
            changes.value++;
          }
        }
      } catch (_) {}
    }
    if (!force && _config.isNotEmpty) {
      if (_loadedAt == null ||
          DateTime.now().difference(_loadedAt!) >= _freshFor) {
        unawaited(_refresh());
      }
      return _config;
    }
    return _refresh();
  }

  static Future<Map<String, dynamic>> _refresh() {
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  static Future<Map<String, dynamic>> _fetch() async {
    try {
      final res = await apiClient.get('/api/config/app-content');
      final body = res.data;
      if (body is! Map ||
          (body['code'] != null && body['code'] != 0) ||
          body['data'] is! Map) {
        return _config;
      }
      _config = Map<String, dynamic>.from(body['data']);
      _loadedAt = DateTime.now();
      changes.value++;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _diskKey,
          jsonEncode({
            'cachedAt': _loadedAt!.toIso8601String(),
            'data': _config,
          }),
        );
      } catch (_) {}
    } catch (_) {}
    return _config;
  }

  static Map<String, dynamic> section(String key) {
    final value = _config[key];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  static Map<String, String> stringMap(String sectionKey, String fieldKey) {
    final value = section(sectionKey)[fieldKey];
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        if (entry.key != null && entry.value != null)
          entry.key.toString(): entry.value.toString(),
    };
  }

  static List<String> stringList(String sectionKey, String fieldKey) {
    final value = section(sectionKey)[fieldKey];
    if (value is! List) return const [];
    return value
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }
}
