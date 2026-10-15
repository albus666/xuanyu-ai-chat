import 'virtual_avatar_catalog.dart';

/// 成品头像配置协议。
///
/// 第 6 版要求云端完整头像通过圆形安全区验收；旧字段仅为兼容历史数据保留，
/// 所有未知、未验收、非 HTTPS 或旧版配置都会安全迁移到免费初始款。
abstract final class VirtualAvatarSpec {
  static const schemaVersion = 6;
  static const outputPixels = 1024;
  static const safeCircleInsetPercent = 13;

  static const partCounts = <String, int>{
    'face': 8,
    'skin': 8,
    'hair': 24,
    'hairColor': 12,
    'eyes': 12,
    'brows': 12,
    'nose': 8,
    'mouth': 12,
    'glasses': 9,
    'accessory': 12,
    'outfit': 18,
    'outfitColor': 12,
    'background': 12,
  };

  static const presentations = {'male', 'female', 'neutral'};
  static const renderStyles = {
    'micro',
    'oriental',
    'urban',
    'healing',
    'night',
    'shanhai',
    'anime',
    'clay',
  };

  static Map<String, dynamic> defaults([int? gender]) => {
        ...VirtualAvatarCatalog.initialConfig(gender),
        'face': 2,
        'skin': 1,
        'hair': 6,
        'hairColor': 0,
        'eyes': 3,
        'brows': 2,
        'nose': 1,
        'mouth': 2,
        'glasses': 0,
        'accessory': 0,
        'outfit': 3,
        'outfitColor': 0,
        'background': 0,
      };

  static Map<String, dynamic> normalize(
    Map<dynamic, dynamic>? source, {
    int? gender,
  }) {
    final fallback = defaults(gender);
    final input = source ?? const <dynamic, dynamic>{};
    final assetCode = _safeCode(input['assetCode']);
    final assetUrl = _httpsUrl(input['assetUrl']);
    final thumbnailUrl = _httpsUrl(input['thumbnailUrl']);
    final localAsset = assetCode != null &&
        VirtualAvatarCatalog.finishedAssets.containsKey(assetCode);
    final remoteSafeCircleApproved = input['safeCircleApproved'] == true &&
        _safeInset(input['safeCircleInsetPercent']) == safeCircleInsetPercent &&
        (input['mediaType'] != 'animated' ||
            input['animationSafeCircleApproved'] == true);
    final validFinished = input['productType'] == 'finished' &&
        assetCode != null &&
        (localAsset || (assetUrl != null && remoteSafeCircleApproved));
    final result = Map<String, dynamic>.from(fallback);

    if (validFinished) {
      final presentation = input['presentation']?.toString();
      final style = input['renderStyle']?.toString();
      final category = input['categoryCode']?.toString();
      final remoteCategory =
          _safeCode(category) ?? _safeCode(style) ?? 'remote';
      final resolvedStyle = localAsset
          ? (renderStyles.contains(style)
              ? style!
              : _styleFromAssetCode(assetCode))
          : remoteCategory;
      result
        ..['productType'] = 'finished'
        ..['assetCode'] = assetCode
        ..['presentation'] = presentations.contains(presentation)
            ? presentation
            : fallback['presentation']
        ..['renderStyle'] = resolvedStyle
        ..['safeCircleApproved'] = true
        ..['safeCircleInsetPercent'] = safeCircleInsetPercent
        ..['categoryCode'] = localAsset
            ? (VirtualAvatarCatalog.styleNames.containsKey(category)
                ? category!
                : _styleFromAssetCode(assetCode))
            : remoteCategory;
      if (assetUrl != null) {
        result
          ..['assetUrl'] = assetUrl
          ..['thumbnailUrl'] = thumbnailUrl ?? assetUrl;
        if (input['mediaType'] == 'animated') {
          result
            ..['mediaType'] = 'animated'
            ..['animationSafeCircleApproved'] = true;
        }
      }
    }

    for (final entry in partCounts.entries) {
      final raw = input[entry.key];
      final value = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (value != null) {
        result[entry.key] = ((value % entry.value) + entry.value) % entry.value;
      }
    }
    result['schemaVersion'] = schemaVersion;
    result['safeCircleApproved'] = true;
    result['safeCircleInsetPercent'] = safeCircleInsetPercent;
    return result;
  }

  static int? _safeInset(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  static String _styleFromAssetCode(String code) {
    final prefix = code.split('_').first;
    return renderStyles.contains(prefix) ? prefix : 'micro';
  }

  static String? _safeCode(dynamic value) {
    final code = value?.toString().trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(code)) return null;
    return code;
  }

  static String? _httpsUrl(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return raw;
  }
}
