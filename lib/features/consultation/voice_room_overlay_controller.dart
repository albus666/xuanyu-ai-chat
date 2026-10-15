import 'package:flutter/foundation.dart';

class VoiceRoomMiniSnapshot {
  const VoiceRoomMiniSnapshot({
    this.title = '正在进入语音房',
    this.subtitle = '正在连接音频',
    this.avatarUrl = '',
    this.canMute = false,
    this.muted = false,
    this.paidActive = false,
  });

  final String title;
  final String subtitle;
  final String avatarUrl;
  final bool canMute;
  final bool muted;
  final bool paidActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceRoomMiniSnapshot &&
          title == other.title &&
          subtitle == other.subtitle &&
          avatarUrl == other.avatarUrl &&
          canMute == other.canMute &&
          muted == other.muted &&
          paidActive == other.paidActive;

  @override
  int get hashCode => Object.hash(
        title,
        subtitle,
        avatarUrl,
        canMute,
        muted,
        paidActive,
      );
}

class VoiceRoomOverlayCallbacks {
  const VoiceRoomOverlayCallbacks({
    required this.onClose,
    required this.onToggleMute,
    required this.onSuspendAudio,
    required this.onResumeAudio,
  });

  final Future<void> Function() onClose;
  final Future<void> Function() onToggleMute;
  final Future<void> Function() onSuspendAudio;
  final Future<void> Function() onResumeAudio;
}

/// 管理 App 内唯一的语音房及其缩小态。
class VoiceRoomOverlayController extends ChangeNotifier {
  VoiceRoomOverlayController._();

  static final VoiceRoomOverlayController instance =
      VoiceRoomOverlayController._();

  int? _roomId;
  int _generation = 0;
  bool _minimized = false;
  VoiceRoomMiniSnapshot _snapshot = const VoiceRoomMiniSnapshot();
  VoiceRoomOverlayCallbacks? _callbacks;
  Object? _systemBackOwner;
  Future<void> Function()? _systemBackHandler;

  int? get roomId => _roomId;
  int get generation => _generation;
  bool get hasActiveRoom => _roomId != null;
  bool get minimized => _minimized;
  VoiceRoomMiniSnapshot get snapshot => _snapshot;

  bool isActiveRoom(int roomId) => _roomId == roomId;

  /// 同一时间只保留一个语音房，防止重复订阅音频。
  bool open(int roomId) {
    if (_roomId != null && _roomId != roomId) return false;
    if (_roomId == roomId) {
      restore();
      return true;
    }
    _roomId = roomId;
    _generation += 1;
    _minimized = false;
    _snapshot = const VoiceRoomMiniSnapshot();
    _callbacks = null;
    notifyListeners();
    return true;
  }

  void attach(int roomId, VoiceRoomOverlayCallbacks callbacks) {
    if (_roomId != roomId) return;
    _callbacks = callbacks;
  }

  void detach(int roomId) {
    if (_roomId == roomId) _callbacks = null;
  }

  /// 根导航返回应先交给语音房处理，避免弹走底层页面或直接退出 App。
  void attachSystemBackHandler(
    Object owner,
    Future<void> Function() handler,
  ) {
    _systemBackOwner = owner;
    _systemBackHandler = handler;
  }

  void detachSystemBackHandler(Object owner) {
    if (!identical(_systemBackOwner, owner)) return;
    _systemBackOwner = null;
    _systemBackHandler = null;
  }

  Future<void> handleSystemBack() async {
    final handler = _systemBackHandler;
    if (handler != null) {
      await handler();
    } else if (hasActiveRoom && !minimized) {
      minimize();
    }
  }

  void updateSnapshot(int roomId, VoiceRoomMiniSnapshot snapshot) {
    if (_roomId != roomId) return;
    if (_snapshot == snapshot) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  void minimize() {
    if (_roomId == null || _minimized) return;
    _minimized = true;
    notifyListeners();
  }

  void restore() {
    if (_roomId == null || !_minimized) return;
    _minimized = false;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    await _callbacks?.onToggleMute();
  }

  Future<void> requestClose() async {
    final roomId = _roomId;
    final callback = _callbacks?.onClose;
    if (roomId == null) return;
    if (callback == null) {
      // 页面异常释放时也不能留下无法关闭的孤儿悬浮窗。
      didClose(roomId);
      return;
    }
    await callback();
  }

  /// 私人专线开始前暂停语音房，避免两个 RTC 实例争用麦克风。
  Future<bool> suspendAudio() async {
    final callback = _callbacks?.onSuspendAudio;
    if (_roomId == null || callback == null) return false;
    await callback();
    return true;
  }

  Future<void> resumeAudio() async {
    await _callbacks?.onResumeAudio();
  }

  void didClose(int roomId) {
    if (_roomId != roomId) return;
    _roomId = null;
    _minimized = false;
    _callbacks = null;
    _snapshot = const VoiceRoomMiniSnapshot();
    notifyListeners();
  }
}
