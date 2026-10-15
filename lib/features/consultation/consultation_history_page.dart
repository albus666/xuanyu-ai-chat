import 'consultation_call_overlay.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'consultation_after_sales_page.dart';

class ConsultationHistoryPage extends StatefulWidget {
  const ConsultationHistoryPage({super.key});

  @override
  State<ConsultationHistoryPage> createState() =>
      _ConsultationHistoryPageState();
}

class _ConsultationHistoryPageState extends State<ConsultationHistoryPage> {
  ApiSessionScope _scope = ApiSessionScope();
  final _items = <Map<String, dynamic>>[];
  final _appointments = <Map<String, dynamic>>[];
  final _actions = <String>{};
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  Timer? _appointmentPoll;
  bool _pollingAppointments = false;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    _appointmentPoll?.cancel();
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    _appointmentPoll?.cancel();
    final next = ApiSessionScope();
    _scope = next;
    _loadGeneration++;
    if (!mounted) return;
    setState(() {
      _items.clear();
      _appointments.clear();
      _actions.clear();
      _loading = next.authenticated;
      _error = next.authenticated ? null : '请登录后查看咨询记录';
    });
    if (next.authenticated) unawaited(_load());
  }

  bool _current(ApiSessionScope scope, int generation) =>
      mounted && scope.current && generation == _loadGeneration;

  Future<void> _load() async {
    final scope = _scope;
    final generation = ++_loadGeneration;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '请登录后查看咨询记录';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    var failed = false;
    try {
      final response = await scope.get('/api/consultation/sessions');
      final data = (response.data as Map?)?['data'];
      final raw = data is Map ? data['list'] : null;
      if (raw is! List) throw const FormatException('咨询记录返回异常');
      if (_current(scope, generation)) {
        setState(() {
          _items
            ..clear()
            ..addAll(
              raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        });
      }
    } catch (_) {
      failed = true;
    }
    if (!_current(scope, generation)) return;
    try {
      final response = await scope.get('/api/consultation/appointments');
      final data = (response.data as Map?)?['data'];
      final raw = data is Map ? data['list'] : null;
      if (raw is! List) throw const FormatException('预约记录返回异常');
      if (_current(scope, generation)) {
        setState(() {
          _appointments
            ..clear()
            ..addAll(
              raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        });
      }
    } catch (_) {
      failed = true;
    }
    if (_current(scope, generation)) {
      setState(() {
        _loading = false;
        if (failed) _error = '部分记录加载失败，请稍后重试';
      });
      _watchAppointments();
    }
  }

  void _watchAppointments() {
    _appointmentPoll?.cancel();
    if (!_appointments.any((a) => a['status'] == 'accepted')) return;
    _appointmentPoll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted ||
          !_scope.current ||
          _loading ||
          _pollingAppointments ||
          _actions.isNotEmpty) {
        return;
      }
      final scope = _scope;
      final generation = _loadGeneration;
      _pollingAppointments = true;
      try {
        final response = await scope.get('/api/consultation/appointments');
        final raw = (response.data as Map?)?['data'];
        final list = raw is Map ? raw['list'] : null;
        if (_current(scope, generation) && list is List) {
          setState(() => _appointments
            ..clear()
            ..addAll(list
                .whereType<Map>()
                .map((a) => Map<String, dynamic>.from(a))));
          if (!_appointments.any((a) => a['status'] == 'accepted')) {
            _appointmentPoll?.cancel();
          }
        }
      } catch (_) {
        // 保留已有记录，下次继续检查对方签到状态。
      } finally {
        _pollingAppointments = false;
      }
    });
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _hideRecord(ApiSessionScope scope, String path) async {
    try {
      await scope.post(path);
      return true;
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(
          context,
          apiSessionFailureMessage(error, '删除失败'),
        );
      }
      return false;
    }
  }

  Future<void> _deleteAppointment(Map<String, dynamic> appointment) async {
    final scope = _scope;
    if (!await _confirm('删除预约记录', '删除后不再显示，但不会影响平台留存的服务与账务凭证。')) return;
    if (!scope.current) return;
    final id = (appointment['id'] as num?)?.toInt();
    if (id == null) return;
    final key = 'appointment-delete:$id';
    if (!_actions.add(key)) return;
    if (mounted) setState(() {});
    final hidden = await _hideRecord(
      scope,
      '/api/consultation/appointments/$id/delete-record',
    );
    if (hidden && mounted && scope.current) {
      setState(() => _appointments.remove(appointment));
      showAppToast(context, '预约记录已删除');
    }
    if (mounted && scope.current) setState(() => _actions.remove(key));
  }

  Future<void> _deleteSession(Map<String, dynamic> session) async {
    final scope = _scope;
    if (!await _confirm('删除咨询记录', '删除后不再显示，但不会影响平台留存的服务与账务凭证。')) return;
    if (!scope.current) return;
    final id = (session['id'] as num?)?.toInt();
    if (id == null) return;
    final key = 'session-delete:$id';
    if (!_actions.add(key)) return;
    if (mounted) setState(() {});
    final hidden = await _hideRecord(
      scope,
      '/api/consultation/sessions/$id/delete-record',
    );
    if (hidden && mounted && scope.current) {
      setState(() => _items.remove(session));
      showAppToast(context, '咨询记录已删除');
    }
    if (mounted && scope.current) setState(() => _actions.remove(key));
  }

  Future<void> _cleanVisible() async {
    final scope = _scope;
    final appointments =
        _appointments.where((item) => item['canDelete'] == true).toList();
    final sessions = _items.where((item) => item['canDelete'] == true).toList();
    final count = appointments.length + sessions.length;
    if (count == 0) {
      showAppToast(context, '当前没有可清理的记录');
      return;
    }
    if (!await _confirm('清理已结束记录', '将清理$count条已取消、已过期或已结束记录。')) return;
    if (!scope.current) return;
    var removed = 0;
    for (final item in appointments) {
      final id = (item['id'] as num?)?.toInt();
      if (id != null &&
          await _hideRecord(
            scope,
            '/api/consultation/appointments/$id/delete-record',
          )) {
        removed++;
      }
    }
    for (final item in sessions) {
      final id = (item['id'] as num?)?.toInt();
      if (id != null &&
          await _hideRecord(
            scope,
            '/api/consultation/sessions/$id/delete-record',
          )) {
        removed++;
      }
    }
    if (!mounted || !scope.current) return;
    await _load();
    if (mounted) showAppToast(context, '已清理$removed条记录');
  }

  Future<void> _appointmentAction(
    Map<String, dynamic> appointment,
    String action,
  ) async {
    final scope = _scope;
    final id = (appointment['id'] as num?)?.toInt();
    if (id == null) return;
    final key = 'appointment-$action:$id';
    if (!_actions.add(key)) return;
    if (mounted) setState(() {});
    try {
      final response = await scope.post(
        '/api/consultation/appointments/$id/$action',
        data: action == 'start'
            ? {'paymentMethod': 'coin', 'agreementAccepted': true}
            : null,
      );
      final data = (response.data as Map?)?['data'];
      if (action == 'start' && data is Map && data['session'] is Map) {
        final sessionId = (data['session']['id'] as num?)?.toInt();
        if (sessionId != null && mounted && scope.current) {
          await ConsultationCallOverlay.instance.open(sessionId);
        }
      }
      if (scope.current) await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(
          context,
          apiSessionFailureMessage(error, '操作失败'),
        );
      }
    } finally {
      if (mounted && scope.current) setState(() => _actions.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('我的咨询'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (_) => _cleanVisible(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clean', child: Text('清理已结束记录')),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(_error!)),
                            TextButton(
                                onPressed: _load, child: const Text('重试')),
                          ],
                        ),
                      ),
                    if (_appointments.isNotEmpty) ...[
                      Text('预约安排', style: AppTextStyles.titleMedium),
                      const SizedBox(height: 10),
                      ..._appointments.map(_appointmentCard),
                      const SizedBox(height: 12),
                    ],
                    Text('咨询记录', style: AppTextStyles.titleMedium),
                    const SizedBox(height: 10),
                    if (_items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        child: Text(
                          '暂无咨询记录',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      )
                    else
                      ..._items.map(_sessionCard),
                  ],
                ),
              ),
      );

  Widget _appointmentCard(Map<String, dynamic> appointment) {
    final appointmentStatus = appointment['status']?.toString();
    final peer = appointment['peer'] is Map ? appointment['peer'] as Map : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                color: Color(0xFF2C7566),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  peer?['nickname']?.toString() ?? '预约老师',
                  style: AppTextStyles.titleSmall,
                ),
              ),
              Text(
                _appointmentStatusText(appointmentStatus),
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color(0xFF8D621E),
                ),
              ),
              if (appointment['canDelete'] == true)
                IconButton(
                  tooltip: '删除预约记录',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: _actions.contains(
                    'appointment-delete:${appointment['id']}',
                  )
                      ? null
                      : () => _deleteAppointment(appointment),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_dateText(appointment['scheduledAt'])} · 预计 ${appointment['expectedMinutes'] ?? 30} 分钟 · ${_amount(appointment['ratePerMin'])}币/分钟',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if ((appointment['note']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              appointment['note'].toString(),
              style: AppTextStyles.bodySmall,
            ),
          ],
          if ((appointment['teacherRemark']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '老师回复：${appointment['teacherRemark']}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
          if (appointmentStatus == 'accepted') ...[
            const SizedBox(height: 6),
            Text(
              '${appointment['checkedIn'] == true ? '你已到场' : '你尚未签到'} · ${appointment['peerCheckedIn'] == true ? '老师已到场' : '老师尚未签到'}',
              style: AppTextStyles.bodySmall.copyWith(
                color: appointment['peerCheckedIn'] == true
                    ? AppColors.success
                    : AppColors.textHint,
              ),
            ),
          ],
          if (appointmentStatus == 'pending' ||
              appointmentStatus == 'accepted') ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton(
                  onPressed: _actions.any(
                    (key) => key.endsWith(':${appointment['id']}'),
                  )
                      ? null
                      : () => _appointmentAction(appointment, 'cancel'),
                  child: const Text('取消预约'),
                ),
                if (appointment['canCancelCheckIn'] == true)
                  TextButton(
                      onPressed: _actions.any(
                              (key) => key.endsWith(':${appointment['id']}'))
                          ? null
                          : () => _appointmentAction(
                              appointment, 'cancel-check-in'),
                      child: const Text('取消签到')),
                if (appointmentStatus == 'accepted') ...[
                  OutlinedButton(
                    onPressed: appointment['checkedIn'] == true ||
                            _actions.any(
                                (key) => key.endsWith(':${appointment['id']}'))
                        ? null
                        : () {
                            if (appointment['canCheckIn'] != true) {
                              final scheduled = DateTime.tryParse(
                                  '${appointment['scheduledAt']}');
                              showAppToast(
                                  context,
                                  scheduled != null &&
                                          DateTime.now().isAfter(scheduled
                                              .add(const Duration(minutes: 30)))
                                      ? '本次预约签到已结束'
                                      : '预约前30分钟内签到');
                              return;
                            }
                            _appointmentAction(appointment, 'check-in');
                          },
                    child: Text(
                      appointment['checkedIn'] == true ? '已签到' : '到场签到',
                    ),
                  ),
                  FilledButton(
                    onPressed: appointment['canStart'] == true &&
                            !_actions.any(
                                (key) => key.endsWith(':${appointment['id']}'))
                        ? () => _appointmentAction(appointment, 'start')
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF173F3B),
                    ),
                    child: const Text('发起专线'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> session) {
    final active = [
      'waiting',
      'accepted',
      'connecting',
      'active',
    ].contains(session['status']);
    final coinPayment = (session['paymentMethod'] ?? 'coin') == 'coin';
    final mode = switch (session['mode']) {
      'public_mic' => '公开连麦',
      'private_mic' => '私密连麦',
      _ => '私人专线',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        tileColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: AppColors.divider),
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEAF4F0),
          backgroundImage: (session['peer'] is Map &&
                  (session['peer']['avatarUrl']?.toString() ?? '').isNotEmpty)
              ? NetworkImage(session['peer']['avatarUrl'].toString())
              : null,
          child: (session['peer'] is! Map ||
                  (session['peer']['avatarUrl']?.toString() ?? '').isEmpty)
              ? const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFF2C7566),
                )
              : null,
        ),
        title: Text(
          session['peer'] is Map
              ? session['peer']['nickname']?.toString() ?? '咨询记录'
              : '咨询记录',
        ),
        subtitle: Text(
          '$mode · ${_statusText(session['status']?.toString())}\n${_duration(session['billedSeconds'])} · ${_amount(session['chargedAmount'] ?? session['payableAmount'])}${coinPayment ? '玄遇币' : '元'}${session['paymentStatus'] == 'failed' ? ' · 待补缴' : ''}',
        ),
        isThreeLine: true,
        trailing: active
            ? const Icon(Icons.chevron_right_rounded)
            : PopupMenuButton<String>(
                tooltip: '记录操作',
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteSession(session);
                  } else {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => ConsultationAfterSalesPage(
                              initialSession: session,
                            ),
                          ),
                        )
                        .then((_) => _load());
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'after_sale',
                    child: Text(
                      session['status'] == 'refunded' ? '查看售后记录' : '申请售后',
                    ),
                  ),
                  if (session['canDelete'] == true)
                    const PopupMenuItem(value: 'delete', child: Text('删除记录')),
                ],
              ),
        onTap: active
            ? () => ConsultationCallOverlay.instance
                .open((session['id'] as num).toInt())
            : null,
      ),
    );
  }

  String _dateText(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '时间待确认';
    return '${parsed.month}月${parsed.day}日 ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  String _amount(dynamic value) {
    final number = num.tryParse(value?.toString() ?? '') ?? 0;
    var text = number.toStringAsFixed(4);
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return text.isEmpty ? '0' : text;
  }

  String _duration(dynamic value) {
    final seconds = (value as num?)?.toInt() ?? 0;
    if (seconds < 60) return '$seconds秒';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '$minutes分钟' : '$minutes分$rest秒';
  }

  String _appointmentStatusText(String? value) => switch (value) {
        'pending' => '等待老师确认',
        'accepted' => '已确认',
        'rejected' => '未接受',
        'cancelled' => '已取消',
        'started' => '进行中',
        'completed' => '已完成',
        'expired' => '申请已过期',
        'missed' => '未按时开始',
        _ => '处理中',
      };

  String _statusText(String? value) => switch (value) {
        'waiting' => '等待接听',
        'accepted' || 'connecting' => '连接中',
        'active' => '咨询中',
        'ended' => '已完成',
        'cancelled' => '已取消',
        'rejected' => '未接听',
        'refunded' => '已退款',
        _ => '处理中',
      };
}
