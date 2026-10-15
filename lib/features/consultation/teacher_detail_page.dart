import 'appointment_date_picker.dart';
import 'consultation_call_overlay.dart';
import '../../core/network/api_session_scope.dart';
import 'dart:async';

import 'teacher_profile_updates.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/foreground_refresh.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_share_more_button.dart';
import 'private_line_checkout_page.dart';

class TeacherDetailPage extends StatefulWidget {
  const TeacherDetailPage({super.key, required this.teacherId});
  final int teacherId;

  @override
  State<TeacherDetailPage> createState() => _TeacherDetailPageState();
}

class _TeacherDetailPageState extends State<TeacherDetailPage> {
  late final ForegroundRefresh _presenceRefresh;
  int _loadGeneration = 0;
  bool _fetching = false;
  Map<String, dynamic>? _teacher;
  final AudioPlayer _voicePlayer = AudioPlayer();
  StreamSubscription<void>? _voiceCompleteSubscription;
  bool _loading = true;
  bool _playingVoice = false;
  bool _followBusy = false;
  String? _error;
  int? _resumeSessionId;
  final _scope = ApiSessionScope();

  void _profileChanged() {
    final update = teacherProfileUpdates.value;
    if (!mounted || update == null || !update.current) return;
    if (update.profile['userId'] != widget.teacherId) return;
    ++_loadGeneration;
    _fetching = false;
    setState(() {
      _teacher = {...?_teacher, ...update.profile};
      _loading = false;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    teacherProfileUpdates.addListener(_profileChanged);
    _presenceRefresh = ForegroundRefresh(
      refresh: () => _load(silent: true),
      isVisible: () =>
          mounted &&
          !_fetching &&
          !_followBusy &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    )..attach();
    _voiceCompleteSubscription = _voicePlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoice = false);
    });
    _load();
  }

  @override
  void dispose() {
    teacherProfileUpdates.removeListener(_profileChanged);
    _presenceRefresh.dispose();
    _voiceCompleteSubscription?.cancel();
    _voicePlayer.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    _fetching = true;
    setState(() {
      if (!silent) {
        _loading = true;
        _error = null;
      }
    });
    try {
      final response = await apiClient.get(
        '/api/consultation/teachers/${widget.teacherId}',
      );
      final raw = (response.data as Map?)?['data'];
      if (raw is Map && mounted && generation == _loadGeneration) {
        int? ownSession;
        if (raw['serviceStatus'] == 'busy') {
          try {
            final sessions = await _scope.get('/api/consultation/sessions');
            final list = sessions.data['data']['list'];
            if (list is List) {
              for (final item in list.whereType<Map>()) {
                if (item['teacherId'] == widget.teacherId &&
                    const {'waiting', 'accepted', 'connecting', 'active'}
                        .contains(item['status'])) {
                  ownSession = (item['id'] as num?)?.toInt();
                  break;
                }
              }
            }
          } catch (_) {}
        }
        if (!mounted || generation != _loadGeneration || !_scope.current) {
          return;
        }
        setState(() {
          _resumeSessionId = ownSession;
          final refreshed = Map<String, dynamic>.from(raw);
          if (silent && _teacher != null) {
            // Polling must not overwrite a follow action that is still saving.
            refreshed.remove('following');
            _teacher!.addAll(refreshed);
          } else {
            _teacher = refreshed;
          }
          _error = null;
        });
      }
    } on DioException catch (e) {
      if (mounted && generation == _loadGeneration && !silent) {
        setState(
          () => _error =
              (e.response?.data as Map?)?['message']?.toString() ?? '老师资料加载失败',
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        _fetching = false;
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startPrivateLine() async {
    final teacher = _teacher;
    if (teacher == null) return;
    if (_resumeSessionId != null) {
      try {
        ConsultationCallOverlay.instance.open(_resumeSessionId!);
      } catch (_) {
        showAppToast(context, '请先结束当前专线');
      }
      return;
    }
    if (teacher['serviceStatus'] != 'online') {
      showAppToast(context, '老师当前不在线，请稍后再试');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PrivateLineCheckoutPage(
        teacherId: widget.teacherId,
        teacher: Map<String, dynamic>.from(teacher),
      ),
    ));
  }

  Future<void> _toggleVoiceIntro() async {
    final url = _teacher?['voiceIntroUrl']?.toString() ?? '';
    if (url.isEmpty) return;
    try {
      if (_playingVoice) {
        await _voicePlayer.stop();
        if (mounted) setState(() => _playingVoice = false);
      } else {
        await _voicePlayer.play(UrlSource(url));
        if (mounted) setState(() => _playingVoice = true);
      }
    } catch (_) {
      if (mounted) showAppToast(context, '语音介绍播放失败');
    }
  }

  Future<void> _toggleFollow() async {
    final teacher = _teacher;
    if (teacher == null || teacher['isSelf'] == true || _followBusy) return;
    final previous = teacher['following'] == true;
    setState(() {
      _followBusy = true;
      teacher['following'] = !previous;
    });
    try {
      final response = await apiClient
          .post('/api/community/user/${widget.teacherId}/follow');
      final data = (response.data as Map?)?['data'];
      if (mounted && data is Map) {
        setState(() => teacher['following'] = data['following'] == true);
        showAppToast(context, teacher['following'] == true ? '已关注老师' : '已取消关注');
      }
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() => teacher['following'] = previous);
      showAppToast(context, '关注操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _bookAppointment() async {
    final teacher = _teacher;
    if (teacher == null || teacher['canPrivate'] == false) return;
    DateTime? selected;
    var expectedMinutes = 30;
    final noteController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 18, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text('预约私人专线', style: AppTextStyles.titleMedium)),
                IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded)),
              ]),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.event_outlined, color: Color(0xFF2C7566)),
                title: Text(
                    selected == null ? '选择预约日期和时间' : _dateTimeText(selected!)),
                subtitle: const Text('无需提前预约，选择服务时间即可'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showAppointmentDatePicker(
                    sheetContext,
                    initialDate:
                        selected ?? now.add(const Duration(minutes: 1)),
                    now: now,
                  );
                  if (date == null || !sheetContext.mounted) return;
                  final time = await showAppointmentTimePicker(
                    sheetContext,
                    initialTime: selected == null
                        ? TimeOfDay.fromDateTime(
                            now.add(const Duration(minutes: 1)))
                        : TimeOfDay.fromDateTime(selected!),
                  );
                  if (time == null) return;
                  setSheetState(() => selected = DateTime(
                      date.year, date.month, date.day, time.hour, time.minute));
                },
              ),
              const SizedBox(height: 8),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('预计时长', style: AppTextStyles.titleSmall)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 30, label: Text('30分钟')),
                  ButtonSegment(value: 60, label: Text('60分钟')),
                  ButtonSegment(value: 90, label: Text('90分钟')),
                ],
                selected: {expectedMinutes},
                onSelectionChanged: (value) =>
                    setSheetState(() => expectedMinutes = value.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '问题和时间备注（选填）',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF173F3B),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('提交预约申请'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    final note = noteController.text.trim();
    noteController.dispose();
    if (confirmed != true || selected == null || !mounted) return;
    try {
      await apiClient.post('/api/consultation/appointments', data: {
        'teacherId': widget.teacherId,
        'scheduledAt': selected!.toUtc().toIso8601String(),
        'expectedMinutes': expectedMinutes,
        'note': note,
      });
      if (mounted) showAppToast(context, '预约已提交，等待老师确认');
    } on DioException catch (e) {
      if (mounted) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '预约提交失败');
      }
    }
  }

  String _dateTimeText(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _teacher == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('老师资料')),
          body: Center(
              child: OutlinedButton(
                  onPressed: _load, child: Text(_error ?? '重新加载'))));
    }
    final t = _teacher!;
    final avatar = t['avatarUrl']?.toString() ?? '';
    final specialties = t['specialties'] is List
        ? (t['specialties'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final credentials = t['credentials'] is List
        ? (t['credentials'] as List).whereType<Map>().toList()
        : <Map>[];
    final reviews = t['reviews'] is List
        ? (t['reviews'] as List).whereType<Map>().toList()
        : <Map>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('老师主页'),
          actions: [
            AppShareMoreButton(
              title: t['nickname']?.toString() ?? '玄遇老师',
              shareText:
                  '我在玄遇发现了「${t['nickname']?.toString() ?? '这位老师'}」的主页，来看看老师的专长与服务。',
            ),
          ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            if (t['isSelf'] != true) ...[
              IconButton.outlined(
                onPressed: _followBusy ? null : _toggleFollow,
                tooltip: t['following'] == true ? '取消关注' : '关注老师',
                style: IconButton.styleFrom(
                  foregroundColor: t['following'] == true
                      ? const Color(0xFFB6812D)
                      : const Color(0xFF173F3B),
                ),
                icon: Icon(t['following'] == true
                    ? Icons.person_add_alt_1
                    : Icons.person_add_alt_1_outlined),
              ),
              const SizedBox(width: 8),
            ],
            OutlinedButton(
                onPressed: t['canPrivate'] == false ? null : _bookAppointment,
                child: const Text('预约')),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _resumeSessionId == null &&
                        (t['canPrivate'] == false ||
                            t['serviceStatus'] != 'online')
                    ? null
                    : _startPrivateLine,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF173F3B),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_resumeSessionId != null
                    ? '继续进入咨询'
                    : t['serviceStatus'] == 'online'
                        ? '私人专线  ${(t['privatePricePerMin'] as num?)?.toStringAsFixed(0) ?? 0}币/分钟'
                        : t['serviceStatus'] == 'busy'
                            ? '老师咨询中'
                            : t['isOnline'] == true
                                ? '老师在线 · 暂不接单'
                                : '老师当前离线'),
              ),
            ),
          ]),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFF3E9D7), Color(0xFFE4F0EB)]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(children: [
                CircleAvatar(
                    radius: 39,
                    backgroundColor: Colors.white54,
                    backgroundImage:
                        avatar.isNotEmpty ? NetworkImage(avatar) : null,
                    child: avatar.isEmpty
                        ? const Icon(Icons.person,
                            size: 38, color: Color(0xFF173F3B))
                        : null),
                const SizedBox(width: 15),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Flexible(
                            child: Text(t['nickname']?.toString() ?? '认证老师',
                                style: AppTextStyles.titleMedium,
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            color: Color(0xFFB6812D), size: 19)
                      ]),
                      const SizedBox(height: 4),
                      Text(t['displayTitle']?.toString() ?? '平台认证老师',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _Stat(
                            (t['rating'] as num?)?.toStringAsFixed(1) ?? '5.0',
                            '评分'),
                        _Stat('${t['completedSessions'] ?? 0}', '已服务'),
                        _Stat('${t['responseMinutes'] ?? 0}分', '响应'),
                      ]),
                    ])),
              ]),
            ),
            const SizedBox(height: 16),
            _Section(
                title: '擅长领域',
                child: specialties.isEmpty
                    ? Text('暂未填写',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: specialties
                            .map((e) => Chip(
                                label: Text(e),
                                backgroundColor: const Color(0xFFF6F1E7),
                                side: BorderSide.none))
                            .toList())),
            _Section(
                title: '服务介绍',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['intro']?.toString() ?? '暂无介绍',
                          style:
                              AppTextStyles.bodyMedium.copyWith(height: 1.65)),
                      if ((t['education']?.toString() ?? '').isNotEmpty ||
                          (t['experienceYears'] as num?) != null) ...[
                        const SizedBox(height: 10),
                        Text(
                            '${t['education'] ?? '从业资料已备案'} · ${t['experienceYears'] ?? 0}年相关经验',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary)),
                      ],
                      if ((t['voiceIntroUrl']?.toString() ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                            onPressed: _toggleVoiceIntro,
                            icon: Icon(_playingVoice
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline_rounded),
                            label: Text(_playingVoice ? '停止播放' : '试听语音介绍')),
                      ],
                    ])),
            _Section(
              title: '资质与服务边界',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.verified_user_outlined,
                          size: 18, color: Color(0xFF2C7566)),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Text(
                              t['credentialBadge']?.toString() ?? '平台已核验',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(fontWeight: FontWeight.w600)))
                    ]),
                    if (credentials.isNotEmpty)
                      ...credentials.map((c) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '${c['credential_name'] ?? ''} · ${c['issuer'] ?? '发证机构已备案'}',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary)))),
                    const SizedBox(height: 10),
                    Text(t['serviceNotice']?.toString() ?? '',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint, height: 1.55)),
                  ]),
            ),
            _Section(
              title: '真实服务评价 ${t['reviewCount'] ?? 0}',
              child: reviews.isEmpty
                  ? Text('暂无已完成订单评价',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textHint))
                  : Column(
                      children: reviews
                          .take(5)
                          .map((r) => Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: AppColors.cardBackground,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          List.filled(
                                                  (r['rating'] as num?)
                                                          ?.toInt() ??
                                                      5,
                                                  '★')
                                              .join(),
                                          style: const TextStyle(
                                              color: Color(0xFFB6812D),
                                              letterSpacing: 2)),
                                      if ((r['content']?.toString() ?? '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Text(r['content'].toString(),
                                            style: AppTextStyles.bodySmall)
                                      ],
                                    ]),
                              ))
                          .toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFF173F3B))),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textHint))
      ]));
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.divider.withValues(alpha: .7))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.titleSmall),
          const SizedBox(height: 12),
          child
        ]),
      );
}
