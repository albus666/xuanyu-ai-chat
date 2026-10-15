import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';

class StartupQuoteService {
  StartupQuoteService._();

  static const int maxLength = 42;
  static const String defaultQuote = '愿你在认真生活的日子里，既有向前奔赴的勇气，也有拥抱自己的温柔。';
  static const String _cacheKey = 'startup_quote_content_v1';

  static String cached(SharedPreferences prefs) {
    return normalize(prefs.getString(_cacheKey)) ?? defaultQuote;
  }

  static Future<String> refresh(SharedPreferences prefs) async {
    final fallback = cached(prefs);
    try {
      final response = await apiClient
          .get('/api/config/startup-quote')
          .timeout(const Duration(seconds: 2));
      final data = (response.data as Map?)?['data'];
      final content = data is Map ? normalize(data['content']) : null;
      if (content == null) return fallback;
      await prefs.setString(_cacheKey, content);
      return content;
    } catch (_) {
      return fallback;
    }
  }

  static String? normalize(Object? value) {
    final content = value?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (content == null ||
        content.isEmpty ||
        content.runes.length > maxLength) {
      return null;
    }
    return content;
  }
}
