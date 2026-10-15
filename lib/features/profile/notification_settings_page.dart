import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/notification/app_notifications.dart';
import '../../core/settings/app_settings_store.dart';
import '../../core/utils/app_toast.dart';
import 'settings_ui.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  final _store = AppSettingsStore.instance;
  bool _loading = true;
  bool _publishResult = true;
  PermissionStatus? _systemStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _load() async {
    try {
      await _store.syncFromServer();
    } catch (_) {}
    _publishResult = await isPostPublishNotificationEnabled();
    _systemStatus = await Permission.notification.status;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshPermission() async {
    final value = await Permission.notification.status;
    if (mounted) setState(() => _systemStatus = value);
  }

  Future<void> _managePermission() async {
    final current = await Permission.notification.status;
    if (current.isPermanentlyDenied || current.isRestricted) {
      await openAppSettings();
    } else {
      await Permission.notification.request();
    }
    await _refreshPermission();
  }

  Future<void> _serverSetting(String key, bool value) async {
    try {
      await _store.update({key: value});
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showAppToast(context, '设置保存失败');
    }
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
        hour: int.tryParse(parts.first) ?? 0,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0);
  }

  Future<void> _chooseTime(String key) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _parseTime(_store.stringValue(key)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF24272D),
            brightness: Theme.of(context).brightness,
          ),
        ),
        child: child!,
      ),
    );
    if (selected == null) return;
    final value =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    try {
      await _store.update({key: value});
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showAppToast(context, '时间保存失败');
    }
  }

  String get _systemText {
    final status = _systemStatus;
    if (status == null) return '正在读取';
    return status.isGranted || status.isLimited ? '已允许' : '未允许';
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '消息通知',
        loading: _loading,
        children: [
          const SettingsSectionLabel('系统通知'),
          SettingsRow(
              icon: Icons.notifications_active_outlined,
              title: '系统通知权限',
              value: _systemText,
              onTap: _managePermission),
          const SettingsDivider(),
          SettingsSwitchRow(
            icon: Icons.publish_outlined,
            title: '发布结果提醒',
            subtitle: '动态在后台发布完成或失败时提醒',
            value: _publishResult,
            onChanged: (value) async {
              await setPostPublishNotificationEnabled(value);
              if (!mounted) return;
              setState(() => _publishResult = value);
              if (value) await _managePermission();
            },
          ),
          const SettingsDivider(),
          SettingsSwitchRow(
            icon: Icons.call_outlined,
            title: '语音和视频通话提醒',
            subtitle: '关闭后不会弹出来电界面',
            value: _store.boolValue('notifySocialCalls'),
            onChanged: (v) => _serverSetting('notifySocialCalls', v),
          ),
          const SettingsSectionLabel('免打扰'),
          SettingsSwitchRow(
            icon: Icons.bedtime_outlined,
            title: '定时免打扰',
            subtitle: '期间不弹出语音和视频来电',
            value: _store.boolValue('quietHoursEnabled'),
            onChanged: (v) => _serverSetting('quietHoursEnabled', v),
          ),
          if (_store.boolValue('quietHoursEnabled')) ...[
            const SettingsDivider(),
            SettingsRow(
                icon: Icons.schedule_rounded,
                title: '开始时间',
                value: _store.stringValue('quietHoursStart'),
                onTap: () => _chooseTime('quietHoursStart')),
            const SettingsDivider(),
            SettingsRow(
                icon: Icons.schedule_rounded,
                title: '结束时间',
                value: _store.stringValue('quietHoursEnd'),
                onTap: () => _chooseTime('quietHoursEnd')),
          ],
        ],
      );
}
