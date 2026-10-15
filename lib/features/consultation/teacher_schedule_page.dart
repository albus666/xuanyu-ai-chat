import 'appointment_date_picker.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

class TeacherSchedulePage extends StatefulWidget {
  const TeacherSchedulePage({super.key});

  @override
  State<TeacherSchedulePage> createState() => _TeacherSchedulePageState();
}

class _TeacherSchedulePageState extends State<TeacherSchedulePage> {
  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _enabled = false;
  final Set<int> _days = {};
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 21, minute: 0);
  final _notice = TextEditingController();

  final _scope = ApiSessionScope();

  void _accountChanged() {
    if (mounted && !_scope.current) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _notice.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(Object? value, TimeOfDay fallback) {
    final parts = '$value'.split(':');
    if (parts.length < 2) return fallback;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? fallback.hour,
      minute: int.tryParse(parts[1]) ?? fallback.minute,
    );
  }

  Future<void> _load() async {
    if (!mounted || !_scope.current) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response =
          await _scope.get('/api/consultation/teacher/availability');
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException();
      if (mounted && _scope.current) {
        final weekly =
            data['weekly'] is List ? data['weekly'] as List : const [];
        setState(() {
          _enabled = data['enabled'] == true;
          _notice.text = data['notice']?.toString() ?? '';
          _days
            ..clear()
            ..addAll(weekly
                .whereType<Map>()
                .map((e) => (e['weekday'] as num).toInt()));
          if (weekly.isNotEmpty && weekly.first is Map) {
            _start = _parseTime((weekly.first as Map)['start'], _start);
            _end = _parseTime((weekly.first as Map)['end'], _end);
          }
        });
      }
    } catch (error) {
      if (mounted && _scope.current) {
        setState(() => _loadError = apiSessionFailureMessage(error, '时段加载失败'));
        showAppToast(context, apiSessionFailureMessage(error, '时段加载失败'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _loading = false);
    }
  }

  String _encoded(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (!mounted ||
        !_scope.current ||
        _saving ||
        _loading ||
        _loadError != null) {
      return;
    }
    if (_enabled && _days.isEmpty) {
      showAppToast(context, '请至少选择一天');
      return;
    }
    final startMinutes = _start.hour * 60 + _start.minute;
    final endMinutes = _end.hour * 60 + _end.minute;
    if (startMinutes >= endMinutes) {
      showAppToast(context, '结束时间需要晚于开始时间');
      return;
    }
    setState(() => _saving = true);
    try {
      await _scope.put('/api/consultation/teacher/availability', data: {
        'enabled': _enabled,
        'weekly': _days
            .map((day) => {
                  'weekday': day,
                  'start': _encoded(_start),
                  'end': _encoded(_end),
                })
            .toList(),
        'notice': _notice.text.trim(),
        'minNoticeHours': 0,
      });
      if (mounted && _scope.current) {
        showAppToast(context, '可预约时段已保存');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '保存失败'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(bool start) async {
    final value = await showAppointmentTimePicker(
      context,
      initialTime: start ? _start : _end,
    );
    if (value != null && mounted && _scope.current) {
      setState(() => start ? _start = value : _end = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('账号已切换')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('可预约时间')),
      body: _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  TextButton(onPressed: _load, child: const Text('重新加载')),
                ],
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _enabled,
                      title: const Text('开放预约'),
                      subtitle: const Text('用户可随时提交预约，服务时间按下方时段安排'),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const SizedBox(height: 18),
                    Text('每周服务日', style: AppTextStyles.titleSmall),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (index) {
                        final day = index + 1;
                        return FilterChip(
                          label: Text(_weekdays[index]),
                          selected: _days.contains(day),
                          onSelected: (selected) => setState(() =>
                              selected ? _days.add(day) : _days.remove(day)),
                        );
                      }),
                    ),
                    const SizedBox(height: 22),
                    Row(children: [
                      Expanded(
                          child:
                              _timeTile('开始', _start, () => _pickTime(true))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _timeTile('结束', _end, () => _pickTime(false))),
                    ]),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _notice,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: '预约须知',
                        hintText: '例如：请提前准备好想沟通的问题；不提供医疗、投资等专业意见。',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存设置'),
                    ),
                  ],
                ),
    );
  }

  Widget _timeTile(String title, TimeOfDay value, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint)),
            const SizedBox(height: 5),
            Text(_encoded(value), style: AppTextStyles.titleSmall),
          ]),
        ),
      );
}
