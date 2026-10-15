import 'package:get/get.dart';
import 'teacher_workbench_page.dart';
import 'consultation_call_overlay.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/bootstrap/startup_gate.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';

/// 名师在 App 任意页面都能看到的私人专线来电层。
class ConsultationIncomingCallHost extends StatefulWidget {
  const ConsultationIncomingCallHost({super.key, required this.child});

  final Widget child;

  @override
  State<ConsultationIncomingCallHost> createState() =>
      _ConsultationIncomingCallHostState();
}

class _ConsultationIncomingCallHostState
    extends State<ConsultationIncomingCallHost> with WidgetsBindingObserver {
  Timer? _timer;
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _appointment;
  bool _isTeacher = false;
  bool _polling = false;
  bool _acting = false;
  bool _bootstrapping = false;
  bool _foreground = true;
  String? _observedAuthorization;
  int _identityWatchTicks = 0;
  int? _announcedSessionId;
  int? _announcedAppointmentId;
  int? _heldSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapAfterStartup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_bootstrapAfterStartup());
  }

  Future<void> _bootstrapAfterStartup() async {
    if (!StartupGate.isReady) await StartupGate.ready;
    if (mounted && _foreground) await _bootstrap();
  }

  Timer _watchIdentity() => Timer.periodic(const Duration(seconds: 2), (_) {
        final current = apiClient.options.headers['Authorization']?.toString();
        _identityWatchTicks += 1;
        if (current != _observedAuthorization || _identityWatchTicks >= 30) {
          _identityWatchTicks = 0;
          unawaited(_bootstrap());
        }
      });

  Future<void> _bootstrap() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    _observedAuthorization =
        apiClient.options.headers['Authorization']?.toString();
    try {
      final response = await apiClient.get('/api/auth/me');
      final data = (response.data as Map?)?['data'];
      final raw = data is Map ? data['isMaster'] ?? data['is_master'] : null;
      final normalized = raw?.toString().toLowerCase();
      final isTeacher =
          raw == true || raw == 1 || normalized == '1' || normalized == 'true';
      if (!mounted) return;
      _isTeacher = isTeacher;
      _timer?.cancel();
      await _poll();
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_poll()),
      );
    } on DioException catch (_) {
      // 未登录或网络切换时保持安静，恢复前台会自动重试。
      _timer?.cancel();
      _timer = _watchIdentity();
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> _poll() async {
    if (!mounted || !_foreground || _polling || _acting) return;
    _polling = true;
    try {
      final incomingResponse =
          await apiClient.get('/api/consultation/incoming');
      final incomingData = (incomingResponse.data as Map?)?['data'];
      final userSession = incomingData is Map ? incomingData['session'] : null;
      final response = _isTeacher
          ? await apiClient.get('/api/consultation/teacher/incoming')
          : null;
      final data = (response?.data as Map?)?['data'];
      final raw = userSession ?? (data is Map ? data['session'] : null);
      final next = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final appointmentRaw = data is Map ? data['appointment'] : null;
      final nextAppointment = next == null && appointmentRaw is Map
          ? Map<String, dynamic>.from(appointmentRaw)
          : null;
      final id = (next?['id'] as num?)?.toInt();
      if (!mounted) return;
      if ((_heldSessionId != null && !ConsultationCallOverlay.instance.ended) ||
          (id != null && id == ConsultationCallOverlay.instance.sessionId)) {
        if (_session != null || _appointment != null) {
          setState(() {
            _session = null;
            _appointment = null;
          });
        }
        return;
      }
      final appointmentId = (nextAppointment?['id'] as num?)?.toInt();
      final newSession = id != null &&
          next?['status'] == 'waiting' &&
          _announcedSessionId != id;
      final newAppointment = id == null &&
          appointmentId != null &&
          _announcedAppointmentId != appointmentId;
      if (newSession) {
        _announcedSessionId = id;
      }
      if (newAppointment) {
        _announcedAppointmentId = appointmentId;
      }
      if (newSession || newAppointment) {
        unawaited(SystemSound.play(SystemSoundType.alert));
        unawaited(HapticFeedback.heavyImpact());
      }
      setState(() {
        _session = next;
        _appointment = id == null ? nextAppointment : null;
      });
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        _timer?.cancel();
        _isTeacher = false;
        _timer = _watchIdentity();
        if (mounted) {
          setState(() {
            _session = null;
            _appointment = null;
          });
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _reject() async {
    final sessionId = (_session?['id'] as num?)?.toInt();
    final appointmentId = (_appointment?['id'] as num?)?.toInt();
    final id = sessionId ?? appointmentId;
    if (id == null || _acting) return;
    setState(() => _acting = true);
    try {
      await apiClient.post(
        sessionId != null
            ? '/api/consultation/sessions/$id/reject'
            : '/api/consultation/appointments/$id/reject',
      );
      if (mounted) {
        setState(() {
          _session = null;
          _appointment = null;
        });
      }
    } on DioException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('拒接失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
      unawaited(_poll());
    }
  }

  Future<void> _acceptOrEnter() async {
    final current = _session;
    final appointment = _appointment;
    final id = (current?['id'] as num?)?.toInt() ??
        (appointment?['id'] as num?)?.toInt();
    if (id == null || _acting) return;
    setState(() => _acting = true);
    try {
      if (appointment != null) {
        await apiClient.post('/api/consultation/appointments/$id/accept');
        if (mounted) {
          setState(() => _appointment = null);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: GestureDetector(
              onTap: () => Get.key.currentState?.push(MaterialPageRoute<void>(
                  builder: (_) => const TeacherWorkbenchPage())),
              child: const Text('预约已接受，点击查看老师工作台'),
            ),
            action: SnackBarAction(
                label: '查看',
                onPressed: () => Get.key.currentState?.push(
                    MaterialPageRoute<void>(
                        builder: (_) => const TeacherWorkbenchPage()))),
          ));
        }
        return;
      }
      if (current?['status'] == 'waiting') {
        await apiClient.post('/api/consultation/sessions/$id/accept');
      }
      if (!mounted) return;
      setState(() => _session = null);
      _heldSessionId = id;
      setState(() => _acting = false);
      await ConsultationCallOverlay.instance.open(id);
    } on DioException catch (error) {
      if (mounted) {
        final message =
            (error.response?.data as Map?)?['message']?.toString() ??
                '接听失败，请稍后重试';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开专线，请稍后重试')));
      }
    } finally {
      _heldSessionId = null;
      if (mounted) setState(() => _acting = false);
      unawaited(_poll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final appointment = _appointment;
    final waiting = session?['status'] == 'waiting';
    final isAppointment = session == null && appointment != null;
    final peer = session?['peer'] ?? appointment?['peer'];
    final peerMap = peer is Map ? peer : const <String, dynamic>{};
    final avatar = peerMap['avatarUrl']?.toString() ?? '';
    final rate = (session?['ratePerMin'] as num?)?.toDouble() ?? 0;
    final paymentUnit = session?['paymentMethod'] == 'alipay' ? '元' : '玄遇币';
    final callTitle = session?['mode'] == 'private_mic' ? '私密连麦' : '私人专线';
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (session != null || appointment != null)
          Positioned.fill(
            child: Material(
              color: const Color(0x9906111E),
              child: SafeArea(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 360),
                    margin: const EdgeInsets.all(22),
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FFFE),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 36,
                          offset: Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.graphic_eq_rounded,
                          color: AppColors.primary,
                          size: 34,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isAppointment
                              ? '新的私人专线预约'
                              : waiting
                                  ? '$callTitle来电'
                                  : '专线正在等待进入',
                          style: const TextStyle(
                            color: Color(0xFF173F3B),
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        CircleAvatar(
                          radius: 42,
                          backgroundColor: const Color(0xFFE0F7F4),
                          backgroundImage:
                              avatar.isNotEmpty ? NetworkImage(avatar) : null,
                          child: avatar.isEmpty
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: Color(0xFF176762),
                                  size: 40,
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          peerMap['nickname']?.toString() ?? '咨询用户',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF173F3B),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          isAppointment
                              ? '请及时接受或拒绝，可在工作台查看预约时间'
                              : '${rate.toStringAsFixed(2)}$paymentUnit/分钟 · 接通前不计费',
                          style: const TextStyle(
                            color: Color(0xFF6A8582),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 23),
                        Row(
                          children: [
                            if (waiting || isAppointment) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _acting ? null : _reject,
                                  icon: const Icon(Icons.call_end_rounded),
                                  label: Text(
                                      session?['initiatorRole'] == 'teacher'
                                          ? '拒绝'
                                          : '拒接'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFE05C58),
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _acting ? null : _acceptOrEnter,
                                icon: _acting
                                    ? const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.call_rounded),
                                label: Text(
                                  isAppointment
                                      ? '接受预约'
                                      : waiting
                                          ? '接听'
                                          : '进入专线',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  minimumSize: const Size.fromHeight(50),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
