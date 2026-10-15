import 'dart:async';

/// 开屏只承担品牌展示，达到这个时长后立即放行页面和非关键后台任务。
const startupDisplayDuration = Duration(milliseconds: 1200);
const startupTransitionDuration = Duration(milliseconds: 180);

/// 让更新检查、来电轮询等非首屏任务避开冷启动关键路径。
class StartupGate {
  StartupGate._();

  static final Completer<void> _ready = Completer<void>();

  static bool get isReady => _ready.isCompleted;

  static Future<void> get ready => _ready.future;

  static void markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }
}
