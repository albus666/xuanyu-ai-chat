import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/settings/app_settings_store.dart';
import '../../core/utils/app_toast.dart';
import 'blocked_users_page.dart';
import 'settings_ui.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  final _store = AppSettingsStore.instance;
  bool _loading = true;
  bool _saving = false;
  bool _privacyLoaded = false;
  bool _loadFailed = false;
  bool _showIntro = true;
  bool _showLocation = true;
  bool _showAge = true;
  bool _showBirthDate = false;
  bool _showBackgroundPreview = true;
  bool _allowFateMatch = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_settingsChanged);
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _privacyLoaded = false;
      _saving = false;
    });
    if (apiClient.options.headers['Authorization'] != null) {
      _load();
    } else {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _store.removeListener(_settingsChanged);
    apiSessionChanges.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final session = apiSessionChanges.value;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    if (!_privacyLoaded) {
      try {
        final response = await apiClient.get('/api/auth/privacy');
        if (!mounted || session != apiSessionChanges.value) return;
        final data = (response.data as Map?)?['data'];
        if (data is! Map) throw StateError('隐私设置响应无效');
        _showIntro = data['showIntro'] == 1 || data['showIntro'] == true;
        _showLocation =
            data['showLocation'] == 1 || data['showLocation'] == true;
        _showAge = data['showAge'] == 1 || data['showAge'] == true;
        _showBirthDate =
            data['showBirthDate'] == 1 || data['showBirthDate'] == true;
        _showBackgroundPreview = data['showBackgroundPreview'] == null ||
            data['showBackgroundPreview'] == 1 ||
            data['showBackgroundPreview'] == true;
        _allowFateMatch =
            data['allowFateMatch'] == 1 || data['allowFateMatch'] == true;
        _privacyLoaded = true;
      } catch (_) {
        if (!mounted || session != apiSessionChanges.value) return;
        _loadFailed = true;
      }
    }
    if (!mounted || session != apiSessionChanges.value) return;
    try {
      await _store.syncFromServer();
    } catch (_) {
      if (!mounted || session != apiSessionChanges.value) return;
      _loadFailed = true;
    } finally {
      if (mounted && session == apiSessionChanges.value) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || !_privacyLoaded) return;
    final session = apiSessionChanges.value;
    setState(() => _saving = true);
    try {
      await apiClient.patch('/api/auth/privacy', data: {
        'showIntro': _showIntro ? 1 : 0,
        'showLocation': _showLocation ? 1 : 0,
        'showAge': _showAge ? 1 : 0,
        'showBirthDate': _showBirthDate ? 1 : 0,
        'showBackgroundPreview': _showBackgroundPreview ? 1 : 0,
        'allowFateMatch': _allowFateMatch ? 1 : 0,
      });
      if (mounted && session == apiSessionChanges.value) {
        showAppToast(context, '隐私设置已保存');
      }
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? (error.response!.data as Map)['message']
          : null;
      if (mounted && session == apiSessionChanges.value) {
        showAppToast(context, message?.toString() ?? '保存失败');
      }
    } finally {
      if (mounted && session == apiSessionChanges.value) {
        setState(() => _saving = false);
      }
    }
  }

  void _localBool(String key, bool value) {
    _store.update({key: value}).then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) showAppToast(context, '设置保存失败');
    });
    setState(() {});
  }

  String _policyLabel(String value) => switch (value) {
        'everyone' => '所有人',
        'following' => '我关注的人',
        'mutual' => '互关好友',
        'none' => '不允许',
        _ => value,
      };

  Future<void> _choosePolicy(String key, List<String> options) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('选择允许范围',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final option in options)
              ListTile(
                title: Text(_policyLabel(option)),
                trailing: _store.stringValue(key) == option
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(ctx, option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    try {
      await _store.update({key: selected});
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showAppToast(context, '设置保存失败');
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '隐私与在线状态',
        loading: _loading,
        actions: [
          TextButton(
            style: settingsTextActionStyle(),
            onPressed: _saving || _loading || !_privacyLoaded ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
        children: [
          if (_loadFailed)
            SettingsRow(
              icon: Icons.refresh_rounded,
              title: '部分设置读取失败，点击重试',
              subtitle: '未读到的隐私设置不会被覆盖',
              onTap: _saving ? null : _load,
            ),
          const SettingsSectionLabel('在线状态'),
          SettingsSwitchRow(
              icon: Icons.circle_outlined,
              title: '显示在线状态',
              subtitle: '关闭后社区头像不显示在线绿点',
              value: _store.boolValue('showOnlineStatus'),
              onChanged: (v) => _localBool('showOnlineStatus', v)),
          const SettingsDivider(),
          SettingsSwitchRow(
              icon: Icons.graphic_eq_rounded,
              title: '显示“在派对中”',
              subtitle: '关闭后好友和最近遇到的人看不到你所在房间',
              value: _store.boolValue('showPartyStatus'),
              onChanged: (v) => _localBool('showPartyStatus', v)),
          const SettingsSectionLabel('社交权限'),
          SettingsRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: '谁可以给我发私信',
              value: _policyLabel(_store.stringValue('allowDirectMessages')),
              onTap: () => _choosePolicy('allowDirectMessages',
                  ['everyone', 'following', 'mutual', 'none'])),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.call_outlined,
              title: '谁可以呼叫我',
              value: _policyLabel(_store.stringValue('allowCalls')),
              onTap: () => _choosePolicy('allowCalls', ['mutual', 'none'])),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.group_add_outlined,
              title: '谁可以邀请我进群',
              value: _policyLabel(_store.stringValue('allowGroupInvites')),
              onTap: () => _choosePolicy('allowGroupInvites',
                  ['everyone', 'following', 'mutual', 'none'])),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.mic_external_on_outlined,
              title: '谁可以邀请我上麦',
              value: _policyLabel(_store.stringValue('allowRoomInvites')),
              onTap: () => _choosePolicy('allowRoomInvites',
                  ['everyone', 'following', 'mutual', 'none'])),
          if (_privacyLoaded) ...[
            const SettingsSectionLabel('主页与匹配'),
            SettingsSwitchRow(
                icon: Icons.description_outlined,
                title: '个人简介',
                value: _showIntro,
                onChanged:
                    _saving ? null : (v) => setState(() => _showIntro = v)),
            const SettingsDivider(),
            SettingsSwitchRow(
                icon: Icons.location_on_outlined,
                title: '所在地区',
                value: _showLocation,
                onChanged:
                    _saving ? null : (v) => setState(() => _showLocation = v)),
            const SettingsDivider(),
            SettingsSwitchRow(
                icon: Icons.cake_outlined,
                title: '年龄',
                value: _showAge,
                onChanged:
                    _saving ? null : (v) => setState(() => _showAge = v)),
            const SettingsDivider(),
            SettingsSwitchRow(
                icon: Icons.calendar_today_outlined,
                title: '具体出生日期与时辰',
                value: _showBirthDate,
                onChanged:
                    _saving ? null : (v) => setState(() => _showBirthDate = v)),
            const SettingsDivider(),
            SettingsSwitchRow(
                icon: Icons.wallpaper_rounded,
                title: '允许放大主页背景',
                value: _showBackgroundPreview,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _showBackgroundPreview = v)),
            const SettingsDivider(),
            SettingsSwitchRow(
                icon: Icons.favorite_border_rounded,
                title: '参与缘分匹配',
                subtitle: '关闭后不出现在其他用户的匹配结果中',
                value: _allowFateMatch,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _allowFateMatch = v)),
          ],
          const SettingsSectionLabel('关系管理'),
          SettingsRow(
              icon: Icons.block_outlined,
              title: '拉黑名单',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const BlockedUsersPage()))),
        ],
      );
}
