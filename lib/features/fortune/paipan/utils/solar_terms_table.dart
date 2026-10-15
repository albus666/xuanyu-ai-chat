import 'package:flutter/services.dart';

/// 12 节名称（流月顺序）：立春、惊蛰…小寒
const List<String> kJieQiNames = ['立春', '惊蛰', '清明', '立夏', '芒种', '小暑', '立秋', '白露', '寒露', '立冬', '小雪', '小寒'];

const List<(int, int)> kJieQiMdDefault = [(2, 4), (3, 5), (4, 5), (5, 5), (6, 5), (7, 7), (8, 7), (9, 7), (10, 8), (11, 7), (11, 22), (1, 6)];

class SolarTermsTable {
  SolarTermsTable._();

  static Map<int, List<(int, int)>>? _cache;
  static const _path = 'assets/bz/data/solar_terms.csv';

  static Future<void> ensureLoaded() async {
    if (_cache != null) return;
    try {
      final csv = await rootBundle.loadString(_path);
      final lines = csv.split('\n');
      if (lines.isEmpty) return;
      final byYear = <int, Map<String, (int, int)>>{};
      for (int i = 1; i < lines.length; i++) {
        final p = lines[i].split(',');
        if (p.length < 4) continue;
        final y = int.tryParse(p[0].trim());
        final name = p[1].trim();
        final m = int.tryParse(p[2].trim());
        final d = int.tryParse(p[3].trim());
        if (y == null || m == null || d == null || !kJieQiNames.contains(name)) continue;
        byYear.putIfAbsent(y, () => {});
        byYear[y]![name] = (m, d);
      }
      _cache = {};
      for (final e in byYear.entries) {
        _cache![e.key] = kJieQiNames.map((n) => e.value[n] ?? kJieQiMdDefault[kJieQiNames.indexOf(n)]).toList();
      }
    } catch (_) {
      _cache = {};
    }
  }

  static (int, int) getMd(int year, int index) {
    if (index < 0 || index >= 12) return kJieQiMdDefault[index.clamp(0, 11)];
    final list = _cache?[year];
    if (list == null || index >= list.length) return kJieQiMdDefault[index];
    return list[index];
  }
}
