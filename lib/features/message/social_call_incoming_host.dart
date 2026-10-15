import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/bootstrap/startup_gate.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import 'social_call_overlay.dart';
import 'social_call_sound.dart';

/// 全局互关好友来电层；登录后轮询，接听后进入真实 RTC 通话页。
class SocialCallIncomingHost extends StatefulWidget {
  const SocialCallIncomingHost({super.key, required this.child});

  final Widget child;

  @override
  State<SocialCallIncomingHost> createState() => _SocialCallIncomingHostState();
}

class _SocialCallIncomingHostState extends State<SocialCallIncomingHost>
    with WidgetsBindingObserver {
  ApiSessionScope _scope = ApiSessionScope();
  Timer? _timer;
  final _sound = SocialCallSound();
  Map<String, dynamic>? _call;
  bool _polling = false;
  bool _acting = false;
  bool _foreground = true;
  int? _announcedId;
  int? _heldId;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_accountChanged);
    unawaited(_startAfterStartup());
  }

  void _accountChanged() {
    if (!mounted) return;
    unawaited(_sound.stop());
    _scope = ApiSessionScope();
    setState(() {
      _call = null;
      _heldId = null;
      _announcedId = null;
      _polling = false;
      _acting = false;
    });
    if (_started) unawaited(_poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      if (_call != null) _sound.start(incoming: true);
      unawaited(_pollAfterStartup());
    } else {
      unawaited(_sound.stop());
    }
  }

  Future<void> _startAfterStartup() async {
    if (!StartupGate.isReady) await StartupGate.ready;
    if (!mounted || _started) return;
    _started = true;
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_poll()),
    );
    await _poll();
  }

  Future<void> _pollAfterStartup() async {
    if (!StartupGate.isReady) await StartupGate.ready;
    if (mounted) await _poll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiSessionChanges.removeListener(_accountChanged);
    _timer?.cancel();
    unawaited(_sound.dispose());
    super.dispose();
  }

  Future<void> _poll() async {
    final scope = _scope;
    if (!_foreground || _polling || _acting || !scope.authenticated) return;
    _polling = true;
    try {
      final response = await scope.get('/api/im/social-call/incoming');
      final data = (response.data as Map?)?['data'];
      final raw = data is Map ? data['call'] : null;
      final next = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final nextId = (next?['id'] as num?)?.toInt();
      if (!mounted || !scope.current) return;
      if (_heldId != null) {
        if (_call != null) setState(() => _call = null);
        return;
      }
      if (nextId != null && nextId != _announcedId) {
        _announcedId = nextId;
        _sound.start(incoming: true);
        unawaited(HapticFeedback.heavyImpact());
      }
      if (nextId == null) await _sound.stop();
      if (_call.toString() != next.toString()) setState(() => _call = next);
    } on ApiSessionChangedException {
      return;
    } on DioException catch (_) {
      // 未登录、切网或旧后端升级过程保持安静，下次自动重试。
    } finally {
      if (scope.current) _polling = false;
    }
  }

  Future<void> _reject() async {
    final scope = _scope;
    final id = (_call?['id'] as num?)?.toInt();
    if (id == null || _acting) return;
    setState(() => _acting = true);
    await _sound.stop();
    try {
      await scope.post('/api/im/social-call/$id/reject');
      if (mounted && scope.current) setState(() => _call = null);
    } on ApiSessionChangedException {
      return;
    } on DioException catch (_) {
    } finally {
      if (mounted && scope.current) {
        setState(() => _acting = false);
        if (_call != null && _foreground) _sound.start(incoming: true);
      }
    }
  }

  Future<void> _accept() async {
    final scope = _scope;
    final id = (_call?['id'] as num?)?.toInt();
    if (id == null || _acting) return;
    setState(() => _acting = true);
    await _sound.stop();
    try {
      final response = await scope.post('/api/im/social-call/$id/accept');
      final data = (response.data as Map?)?['data'];
      final call = data is Map ? Map<String, dynamic>.from(data) : _call;
      if (!mounted || !scope.current || call == null) return;
      _heldId = id;
      setState(() => _call = null);
      await SocialCallOverlay.instance.open(id, call: call);
    } on ApiSessionChangedException {
      return;
    } on DioException catch (_) {
      if (mounted && scope.current) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('接听失败，请稍后重试')));
      }
    } finally {
      if (scope.current) {
        _heldId = null;
        if (mounted) setState(() => _acting = false);
        unawaited(_poll());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final peer = call?['peer'] is Map
        ? Map<String, dynamic>.from(call!['peer'] as Map)
        : const <String, dynamic>{};
    final nickname = peer['nickname']?.toString() ?? '好友';
    final avatar = peer['avatarUrl']?.toString() ?? '';
    return Stack(
      children: [
        widget.child,
        if (call != null)
          Positioned.fill(
            child: Material(
              color: const Color(0xE6152D32),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 80, 28, 54),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: const Color(0xFFE6FAF7),
                        backgroundImage:
                            avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty
                            ? Text(
                                nickname.isEmpty ? '?' : nickname[0],
                                style: const TextStyle(fontSize: 34),
                              )
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        nickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        call['mode'] == 'video' ? '邀请你视频通话' : '邀请你语音通话',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _action(
                            Icons.call_end_rounded,
                            '拒接',
                            const Color(0xFFFF5964),
                            _reject,
                          ),
                          _action(
                            call['mode'] == 'video'
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            '接听',
                            const Color(0xFF2EC9A7),
                            _accept,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _action(
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: _acting ? null : onPressed,
      customBorder: const CircleBorder(),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
