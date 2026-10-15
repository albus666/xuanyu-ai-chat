import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/region.dart';

/// 从 map.json 加载并组织成省市区三级树
class RegionLoader {
  static List<Region> fromFeatureCollectionJson(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>?;
    if (map == null) return [];
    final features = map['features'] as List<dynamic>?;
    if (features == null || features.isEmpty) return [];

    final regionDict = <int, Region>{};
    for (final f in features) {
      final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
      if (props == null) continue;
      final nameRaw = props['name'];
      final String name = nameRaw is String ? nameRaw.trim() : '';
      final geoRaw = props['geo'];
      final String? geo = geoRaw is String ? geoRaw : null;
      if (name.isEmpty || geo == null || geo.trim().isEmpty) continue;
      final region = Region.fromJson(props);
      if (region.lng != null && region.lat != null) regionDict[region.id] = region;
    }

    final childIds = <int, List<int>>{};
    final rootIds = <int>[];
    for (final entry in regionDict.entries) {
      final id = entry.key;
      final item = entry.value;
      final pid = item.pid;
      if (pid == 0 || !regionDict.containsKey(pid)) {
        rootIds.add(id);
      } else {
        childIds.putIfAbsent(pid, () => []).add(id);
      }
    }

    rootIds.sort((a, b) => regionDict[a]!.name.compareTo(regionDict[b]!.name));
    return rootIds.map((id) => _buildNode(id, regionDict, childIds)).toList();
  }

  static Region _buildNode(int id, Map<int, Region> dict, Map<int, List<int>> childIds) {
    final r = dict[id]!;
    final ids = childIds[id] ?? [];
    ids.sort((a, b) => dict[a]!.name.compareTo(dict[b]!.name));
    final children = ids.map((cid) => _buildNode(cid, dict, childIds)).toList();
    return Region(
      id: r.id,
      pid: r.pid,
      deep: r.deep,
      name: r.name,
      extPath: r.extPath,
      geo: r.geo,
      lng: r.lng,
      lat: r.lat,
      children: children,
    );
  }

  static Future<List<Region>>? _cachedFuture;

  /// 加载省市区数据（首次调用会加载，后续复用同一 Future）
  static Future<List<Region>> loadFromAsset(String assetPath) async {
    if (_cachedFuture != null) return _cachedFuture!;
    _cachedFuture = _doLoad(assetPath);
    return _cachedFuture!;
  }

  static Future<List<Region>> _doLoad(String assetPath) async {
    final str = await rootBundle.loadString(assetPath);
    return fromFeatureCollectionJson(str);
  }

  /// 提前加载出生地数据（在打开八字排盘页时调用，点击出生地时优先使用缓存）
  static void preload() {
    loadFromAsset('assets/region_map.json');
  }
}
