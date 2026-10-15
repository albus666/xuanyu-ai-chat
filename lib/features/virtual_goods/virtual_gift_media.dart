import '../../core/network/api_client.dart';

int virtualGiftEffectDuration(Map<String, dynamic> payload) {
  final value = int.tryParse(payload['effectDurationMs']?.toString() ?? '');
  return (value ?? 2200).clamp(1200, 8000);
}

int normalizeVirtualGiftQuantity(int? value) => (value ?? 1).clamp(1, 999);

String virtualGiftCoinAmount(num amount) {
  final value = amount.toDouble();
  if (value % 1 == 0) return value.toStringAsFixed(0);
  final rounded = double.parse(value.toStringAsFixed(4));
  return rounded == double.parse(rounded.toStringAsFixed(2))
      ? rounded.toStringAsFixed(2)
      : rounded.toStringAsFixed(4);
}

String virtualGiftMediaUrl(
  Map<String, dynamic> payload, {
  bool effect = false,
  bool thumbnail = false,
}) {
  final keys = effect
      ? const ['effectAssetPath', 'assetPath', 'effectAssetUrl', 'assetUrl']
      : thumbnail
          ? const ['thumbnailPath', 'assetPath', 'thumbnailUrl', 'assetUrl']
          : const ['assetPath', 'thumbnailPath', 'assetUrl', 'thumbnailUrl'];
  var raw = '';
  for (final key in keys) {
    final value = payload[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      raw = value;
      break;
    }
  }
  if (raw.isEmpty) {
    final code = payload['giftCode'] ?? payload['code'];
    if (code != null && code.toString().trim().isNotEmpty) {
      raw = '/api/virtual/gifts/${Uri.encodeComponent(code.toString())}/asset'
          '${effect ? '?kind=effect' : thumbnail ? '?kind=thumbnail' : ''}';
    }
  }
  if (raw.isEmpty || raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }
  final base = apiClient.options.baseUrl;
  if (base.isEmpty) return raw;
  final normalizedBase = base.endsWith('/') ? base : '$base/';
  return Uri.parse(normalizedBase)
      .resolve(raw.startsWith('/') ? raw.substring(1) : raw)
      .toString();
}

String virtualGiftVideoUrl(Map<String, dynamic> payload) {
  var raw = '';
  for (final key in const ['effectVideoPath', 'effectVideoUrl']) {
    final value = payload[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      raw = value;
      break;
    }
  }
  if (raw.isEmpty) return '';
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final base = apiClient.options.baseUrl;
  if (base.isEmpty) return raw;
  final normalizedBase = base.endsWith('/') ? base : '$base/';
  return Uri.parse(normalizedBase)
      .resolve(raw.startsWith('/') ? raw.substring(1) : raw)
      .toString();
}
