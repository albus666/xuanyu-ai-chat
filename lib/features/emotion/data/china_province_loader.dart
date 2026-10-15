import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'package:xuanyu/features/emotion/data/province_names.dart';

/// 省级行政区边界（来自 DataV GeoJSON）
class ChinaProvince {
  ChinaProvince({
    required this.fullName,
    required this.shortName,
    required this.rings,
    required this.centroid,
  });

  final String fullName;
  final String shortName;
  final List<List<LatLng>> rings;
  final LatLng centroid;
}

class ChinaProvinceLoader {
  ChinaProvinceLoader._();

  static const _assetPath = 'assets/china_provinces.geojson';
  static Future<List<ChinaProvince>>? _cache;

  static Future<List<ChinaProvince>> load() {
    _cache ??= _doLoad();
    return _cache!;
  }

  static Future<List<ChinaProvince>> _doLoad() async {
    final raw = await rootBundle.loadString(_assetPath);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final features = map['features'] as List<dynamic>? ?? [];
    final result = <ChinaProvince>[];

    for (final f in features) {
      final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
      final geom = f['geometry'] as Map<String, dynamic>?;
      if (props == null || geom == null) continue;

      final fullName = (props['name'] as String?)?.trim() ?? '';
      if (fullName.isEmpty) continue;
      final shortName = ProvinceNames.toShort(fullName);
      final rings = _parseRings(geom);
      if (rings.isEmpty) continue;

      result.add(ChinaProvince(
        fullName: fullName,
        shortName: shortName,
        rings: rings,
        centroid: _centroid(rings.first),
      ));
    }
    return result;
  }

  static List<List<LatLng>> _parseRings(Map<String, dynamic> geom) {
    final type = geom['type'] as String?;
    final coords = geom['coordinates'];
    if (coords == null) return [];

    final rings = <List<LatLng>>[];
    if (type == 'Polygon') {
      rings.addAll(_polygonRings(coords as List<dynamic>));
    } else if (type == 'MultiPolygon') {
      for (final poly in coords as List<dynamic>) {
        rings.addAll(_polygonRings(poly as List<dynamic>));
      }
    }
    return rings;
  }

  static List<List<LatLng>> _polygonRings(List<dynamic> polygonCoords) {
    final rings = <List<LatLng>>[];
    for (final ring in polygonCoords) {
      final pts = <LatLng>[];
      for (final p in ring as List<dynamic>) {
        final lng = (p[0] as num).toDouble();
        final lat = (p[1] as num).toDouble();
        pts.add(LatLng(lat, lng));
      }
      if (pts.length >= 3) rings.add(pts);
    }
    return rings;
  }

  static LatLng _centroid(List<LatLng> ring) {
    var lat = 0.0;
    var lng = 0.0;
    for (final p in ring) {
      lat += p.latitude;
      lng += p.longitude;
    }
    final n = ring.length;
    return LatLng(lat / n, lng / n);
  }
}
