import 'dart:async';

import 'package:flutter/widgets.dart';

/// Refresh live status without replacing the visible page with a loading state.
class ForegroundRefresh with WidgetsBindingObserver {
  ForegroundRefresh({
    required this.refresh,
    required this.isVisible,
    this.interval = const Duration(seconds: 15),
  });

  final Future<void> Function() refresh;
  final bool Function() isVisible;
  final Duration interval;
  Timer? _timer;
  bool _attached = false;
  bool _busy = false;
  bool _foreground = true;

  void attach() {
    if (_attached) return;
    _attached = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (!_attached || !_foreground || _busy || !isVisible()) return;
    _busy = true;
    try {
      await refresh();
    } catch (_) {
      // Keep the last known state on a transient refresh failure.
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_tick());
  }

  void dispose() {
    _attached = false;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
