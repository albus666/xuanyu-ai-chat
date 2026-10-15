import '../../app/common/routers/names.dart';

/// Tool introductions use normal text messages so older clients can still read them.
class ToolShareMessage {
  const ToolShareMessage(
      {required this.title, required this.text, required this.route});

  final String title;
  final String text;
  final String route;

  static const routes = {
    RouteNames.homeBazi,
    RouteNames.homeZiwei,
    RouteNames.homeAstrology,
    RouteNames.homeQizheng,
    RouteNames.partnerPortrait,
  };

  String encode() {
    if (!routes.contains(route)) throw ArgumentError.value(route, 'route');
    return '【玄遇工具】$title\n$text\n${Uri(scheme: 'xuanyu', host: 'tool', path: route)}';
  }

  static ToolShareMessage? tryParse(String content) {
    final lines = content.trim().split('\n');
    if (lines.length < 3 || !lines.first.startsWith('【玄遇工具】')) return null;
    final uri = Uri.tryParse(lines.last);
    if (uri == null ||
        uri.scheme != 'xuanyu' ||
        uri.host != 'tool' ||
        uri.hasQuery ||
        uri.hasFragment ||
        !routes.contains(uri.path)) {
      return null;
    }
    final title = lines.first.substring('【玄遇工具】'.length).trim();
    if (title.isEmpty || title.length > 100) return null;
    return ToolShareMessage(
        title: title,
        text: lines.sublist(1, lines.length - 1).join('\n'),
        route: uri.path);
  }
}
