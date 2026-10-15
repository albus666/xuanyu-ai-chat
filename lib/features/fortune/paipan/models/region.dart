/// 行政区划节点，与 myresource/bazi_gui 使用的 map.json 结构一致
/// （id/pid/deep/name/ext_path/geo，按 pid 建树为省→市→区）
class Region {
  final int id;
  final int pid;
  final int deep;
  final String name;
  final String extPath;
  /// 经纬度 "经度 纬度"，如 "116.407387 39.904179"
  final String? geo;
  /// 经度（从 geo 解析，与 bazi_gui 的 lng 一致）
  final double? lng;
  /// 纬度（从 geo 解析，与 bazi_gui 的 lat 一致）
  final double? lat;
  /// 子级（市/区），与 bazi_gui 的 children 一致
  final List<Region> children;

  const Region({
    required this.id,
    required this.pid,
    required this.deep,
    required this.name,
    required this.extPath,
    this.geo,
    this.lng,
    this.lat,
    this.children = const [],
  });

  /// 从记录等场景构造仅含名称和经纬度的占位对象（用于回填表单）
  factory Region.placeholder({required String name, String? extPath, double? lng, double? lat}) {
    final geo = (lng != null && lat != null) ? '$lng $lat' : null;
    return Region(
      id: 0,
      pid: 0,
      deep: 0,
      name: name,
      extPath: extPath ?? name,
      geo: geo,
      lng: lng,
      lat: lat,
    );
  }

  /// 从 map.json 的 Feature.properties 解析（仅基础字段，树由 RegionLoader 构建）
  factory Region.fromJson(Map<String, dynamic> json) {
    final geoStr = json['geo'] as String?;
    double? lng, lat;
    if (geoStr != null && geoStr.trim().isNotEmpty) {
      final parts = geoStr.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        lng = double.tryParse(parts[0]);
        lat = double.tryParse(parts[1]);
      }
    }
    return Region(
      id: _readInt(json, 'id'),
      pid: _readInt(json, 'pid'),
      deep: _readInt(json, 'deep'),
      name: (json['name'] as String?) ?? '',
      extPath: (json['ext_path'] as String?) ?? '',
      geo: geoStr,
      lng: lng,
      lat: lat,
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// 是否为最底层（区/县），选到这一级可确认
  bool get isLeaf => deep >= 2;
}
