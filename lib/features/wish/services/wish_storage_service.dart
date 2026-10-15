import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/features/wish/models/wish_entry.dart';

class WishStorageService {
  WishStorageService._();

  static const String _storageKey = 'wish_prayer_entries_v1';
  static const int maxEntries = 50;

  static Future<List<WishEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <WishEntry>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <WishEntry>[];
      final entries = decoded
          .whereType<Map>()
          .map((item) => WishEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.content.isNotEmpty)
          .toList();
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries.take(maxEntries).toList();
    } catch (_) {
      return <WishEntry>[];
    }
  }

  static Future<List<WishEntry>> add(WishEntry entry) async {
    final entries = await load();
    final updated = <WishEntry>[
      entry,
      ...entries.where((item) => item.id != entry.id),
    ].take(maxEntries).toList();
    await _save(updated);
    return updated;
  }

  static Future<List<WishEntry>> remove(String id) async {
    final entries = await load();
    final updated = entries.where((item) => item.id != id).toList();
    await _save(updated);
    return updated;
  }

  static Future<void> _save(List<WishEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(entries.map((item) => item.toJson()).toList()),
    );
  }
}
