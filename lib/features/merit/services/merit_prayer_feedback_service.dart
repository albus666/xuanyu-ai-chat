import 'package:xuanyu/core/config/app_content_config.dart';

const List<String> meritPrayerFeedbackTexts = <String>[
  '平安顺遂',
  '所愿皆安',
  '心安自在',
  '福气常伴',
  '诸事顺意',
  '烦恼渐远',
  '喜乐常在',
  '万事从容',
];

/// 读取后台“敲击弹出文案”。
///
/// 后台列表不限制条数；这里只过滤停用项与空文案，并按 sortOrder 排序。
/// 同时兼容早期直接配置字符串数组的格式。
List<String> parseMeritPrayerFeedbackTexts(
  dynamic raw, {
  List<String> fallback = meritPrayerFeedbackTexts,
}) {
  if (raw is! List) return List<String>.from(fallback);

  final rows = <({int index, int order, String content})>[];
  for (var index = 0; index < raw.length; index++) {
    final item = raw[index];
    if (item is String) {
      final content = item.trim();
      if (content.isNotEmpty) {
        rows.add((index: index, order: index, content: content));
      }
      continue;
    }
    if (item is! Map || item['enabled'] == false) continue;
    final content = (item['content'] ?? '').toString().trim();
    if (content.isEmpty) continue;
    rows.add((
      index: index,
      order: (item['sortOrder'] as num?)?.toInt() ?? index,
      content: content,
    ));
  }
  rows.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.index.compareTo(b.index);
  });
  if (rows.isEmpty) return List<String>.from(fallback);
  return rows.map((row) => row.content).toList(growable: false);
}

Future<List<String>> loadMeritPrayerFeedbackTexts() async {
  await AppContentConfig.load();
  return parseMeritPrayerFeedbackTexts(
    AppContentConfig.section('merit')['prayerFeedbackTexts'],
  );
}
