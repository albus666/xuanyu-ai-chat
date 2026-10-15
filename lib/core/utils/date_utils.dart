/// 时间工具：统一按北京时间（UTC+8）展示
class AppDateUtils {
  AppDateUtils._();

  static const int _beijingOffsetHours = 8;

  /// 将服务器返回的 ISO 时间转为北京时间（统一按 UTC 解析后加 8 小时）
  static DateTime toBeijing(DateTime dt) {
    final utc = dt.toUtc();
    return utc.add(const Duration(hours: _beijingOffsetHours));
  }

  /// 获取当前北京时间
  static DateTime get beijingNow =>
      DateTime.now().toUtc().add(const Duration(hours: _beijingOffsetHours));

  /// 解析 ISO 字符串并转为北京时间
  static DateTime parseBeijing(String iso) {
    final d = DateTime.parse(iso);
    return toBeijing(d);
  }

  /// 格式化为 上午/下午 H:mm（聊天时间分隔）
  static String formatChatSection(String iso) {
    try {
      final d = parseBeijing(iso);
      final h = d.hour;
      final m = d.minute;
      final ampm = h < 12 ? '上午' : '下午';
      final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$ampm$hour12:${m.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  /// 格式化为 HH:mm（聊天气泡等）
  static String formatTime(String iso) {
    try {
      final d = parseBeijing(iso);
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  /// 格式化为相对时间（刚刚、x分钟前、x小时前、x天前、M/d）
  static String formatRelative(String iso) {
    try {
      final d = parseBeijing(iso);
      final n = beijingNow;
      final diff = n.difference(d);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${d.month}/${d.day}';
    } catch (_) {
      return iso;
    }
  }

  /// 格式化为相对时间，日期用 M-d
  static String formatRelativeMD(String iso) {
    try {
      final d = parseBeijing(iso);
      final n = beijingNow;
      final diff = n.difference(d);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${d.month}-${d.day}';
    } catch (_) {
      return iso;
    }
  }

  /// 评论时间：当天展示到分钟，非当天只展示日期
  static String formatCommentTime(String iso) {
    try {
      final d = parseBeijing(iso);
      final n = beijingNow;
      final isToday = d.year == n.year && d.month == n.month && d.day == n.day;
      if (isToday) {
        return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  /// 个人主页瞬间时间：始终精确到分钟。
  static String formatPostDateTime(String iso) {
    try {
      final d = parseBeijing(iso);
      final n = beijingNow;
      final time =
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      final isToday = d.year == n.year && d.month == n.month && d.day == n.day;
      if (isToday) return '今天 $time';
      final yesterday = n.subtract(const Duration(days: 1));
      final isYesterday = d.year == yesterday.year &&
          d.month == yesterday.month &&
          d.day == yesterday.day;
      if (isYesterday) return '昨天 $time';
      if (d.year == n.year) {
        return '${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日 $time';
      }
      return '${d.year}年${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日 $time';
    } catch (_) {
      return iso;
    }
  }
}
