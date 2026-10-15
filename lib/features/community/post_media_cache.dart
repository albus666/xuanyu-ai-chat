import 'package:flutter/painting.dart';

const _previewEdges = [480, 720, 1080, 1440];

/// Quantized physical pixels keep visible thumbnails and warmup on one key.
int postPreviewEdge(double logicalWidth, double pixelRatio) {
  final needed = logicalWidth * pixelRatio;
  return _previewEdges.firstWhere(
    (edge) => edge >= needed,
    orElse: () => _previewEdges.last,
  );
}

ResizeImage postPreviewImage(String url, int edge) => ResizeImage(
      NetworkImage(url),
      width: edge,
      height: edge,
      policy: ResizeImagePolicy.fit,
    );

/// Only ignore signing parameters, never transformations or content versions.
String _imageIdentity(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  const signingKeys = {
    'ossaccesskeyid',
    'signature',
    'expires',
    'security-token',
    'x-oss-signature',
    'x-oss-credential',
    'x-oss-date',
    'x-oss-expires',
    'x-oss-security-token',
    'x-oss-signature-version',
  };
  final query = Map<String, dynamic>.fromEntries(
    uri.queryParametersAll.entries.where(
      (entry) => !signingKeys.contains(entry.key.toLowerCase()),
    ),
  );
  return uri.replace(queryParameters: query, fragment: '').toString();
}

bool _isLoaded(String url) {
  final status = PaintingBinding.instance.imageCache.statusForKey(
    NetworkImage(url),
  );
  return status.live || status.keepAlive;
}

/// Feed and detail can return different signed URLs for the same image.
/// Reuse only an already decoded image, without keeping expired URLs on disk.
Map<String, dynamic> reuseLoadedPostMedia(
  Map<String, dynamic>? previous,
  Map<String, dynamic> next, {
  bool Function(String) isLoaded = _isLoaded,
}) {
  if (previous == null || previous['id'] != next['id']) return next;
  dynamic reuse(dynamic oldValue, dynamic newValue) {
    if (oldValue is String && newValue is String) {
      if (oldValue != newValue &&
          _imageIdentity(oldValue) == _imageIdentity(newValue) &&
          isLoaded(oldValue)) {
        return oldValue;
      }
    } else if (oldValue is List && newValue is List) {
      return [
        for (var i = 0; i < newValue.length; i++)
          reuse(i < oldValue.length ? oldValue[i] : null, newValue[i]),
      ];
    } else if (oldValue is Map && newValue is Map) {
      return <String, dynamic>{
        for (final entry in newValue.entries)
          entry.key.toString():
              const {'url', 'path', 'src', 'uri'}.contains(entry.key)
                  ? reuse(oldValue[entry.key], entry.value)
                  : entry.value,
      };
    }
    return newValue;
  }

  return {
    ...next,
    for (final field in [
      'avatarUrl',
      'mediaCoverUrls',
      if (next['mediaType'] != 'video' && next['mediaType'] != 'audio')
        'mediaUrls',
    ])
      if (next.containsKey(field)) field: reuse(previous[field], next[field]),
  };
}

/// A small image-only warmup; never download video/audio bodies in the background.
Iterable<String> postPreviewUrls(Iterable<Map<String, dynamic>> posts) sync* {
  final seen = <String>{};
  for (final post in posts) {
    final type = post['mediaType']?.toString().toLowerCase();
    final media = type == 'video' || type == 'audio'
        ? post['mediaCoverUrls']
        : post['mediaUrls'];
    for (final raw in [
      post['avatarUrl'],
      if (media is List) ...media.take(1),
    ]) {
      final value = raw is Map
          ? raw['url'] ?? raw['path'] ?? raw['src'] ?? raw['uri']
          : raw;
      if (value is! String) continue;
      final uri = Uri.tryParse(value);
      if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
        continue;
      }
      if (seen.add(value)) yield value;
      if (seen.length >= 6) return;
    }
  }
}
