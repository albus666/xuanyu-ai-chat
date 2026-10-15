import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_client.dart';

/// 登录用户在前台时续期全站统一在线态，用于社区头像和好友状态。
class PresenceHeartbeat with WidgetsBindingObserver {
  PresenceHeartbeat({this.interval = const Duration(seconds: 45)});

  final Duration interval;

  Timer? _timer;
  bool _attached = false;
  bool _foreground = true;
  final _inFlightSessions = <int>{};

  void attach() {
    if (_attached) return;
    _attached = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    apiSessionChanges.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    apiSessionChanges.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  void _armPeriodic() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(_ping()));
  }

  Future<void> _bootstrap() async {
    if (!_attached || !_foreground || !_hasSession) return;
    await _ping();
    if (!_attached || !_foreground || !_hasSession) return;
    _armPeriodic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_onResumed());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _onResumed() async {
    if (!_attached || !_foreground || !_hasSession) return;
    await _ping();
    if (!_attached || !_foreground || !_hasSession) return;
    _armPeriodic();
  }

  bool get _hasSession => apiClient.options.headers['Authorization'] != null;

  void _sessionChanged() {
    _timer?.cancel();
    _timer = null;
    unawaited(_bootstrap());
  }

  Future<void> _ping() async {
    final session = apiSessionChanges.value;
    if (!_attached ||
        !_foreground ||
        !_hasSession ||
        !_inFlightSessions.add(session)) {
      return;
    }
    try {
      await apiClient.post('/api/auth/presence/ping');
    } catch (_) {
    } finally {
      _inFlightSessions.remove(session);
    }
  }
}
