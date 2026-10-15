import 'identity_verification_page.dart';
import '../../core/cache/page_snapshot_cache.dart';
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/bootstrap/auth_state.dart';
import '../../core/constants/agora_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/settings/app_settings_store.dart';
import '../../core/utils/app_toast.dart';
import '../../core/update/app_update_host.dart';
import '../consultation/consultation_payment_setting_page.dart';
import '../consultation/teacher_workbench_page.dart';
import '../virtual_goods/virtual_avatar_studio_page.dart';
import 'account_cancellation_page.dart';
import 'balance_page.dart';
import 'blocked_users_page.dart';
import 'change_password_page.dart';
import 'change_phone_page.dart';
import 'legal_document_page.dart';
import 'orders_page.dart';
import 'privacy_rights_page.dart';
import 'recharge_page.dart';
import 'settings_ui.dart';
import 'teacher_apply_page.dart';

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

String _apiMessage(Object error, String fallback) {
  if (error is DioException && error.response?.data is Map) {
    return ((error.response!.data as Map)['message'] ?? fallback).toString();
  }
  return fallback;
}

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  String _mobile = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/api/auth/me');
      final value =
          (response.data as Map?)?['data']?['mobile']?.toString() ?? '';
      if (mounted) setState(() => _mobile = value);
    } catch (_) {}
  }

  String get _maskedMobile => _mobile.length == 11
      ? '${_mobile.substring(0, 3)}****${_mobile.substring(7)}'
      : '未读取';

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '账号与安全',
        children: [
          const SettingsSectionLabel('账号信息'),
          SettingsRow(
            icon: Icons.verified_user_outlined,
            title: '实名认证',
            onTap: () => _push(context, const IdentityVerificationPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.phone_iphone_rounded,
            title: '绑定手机号',
            value: _maskedMobile,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ChangePhonePage()));
              _load();
            },
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.password_rounded,
            title: '修改密码',
            onTap: () => _push(context, const ChangePasswordPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.devices_rounded,
            title: '登录设备管理',
            subtitle: '查看设备并退出可疑登录',
            onTap: () => _push(context, const LoginDevicesPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.shield_outlined,
            title: '账号安全记录',
            subtitle: '查看新设备登录和账号重要变更',
            onTap: () => _push(context, const AccountSecurityEventsPage()),
          ),
          const SettingsSectionLabel('数据与账号'),
          SettingsRow(
            icon: Icons.admin_panel_settings_outlined,
            title: '个人信息权利中心',
            subtitle: '查询、复制、更正、撤回授权与账号申诉',
            onTap: () => _push(context, const PrivacyRightsPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.person_off_outlined,
            title: '注销账号',
            destructive: true,
            onTap: () => _push(context, const AccountCancellationPage()),
          ),
        ],
      );
}

class AccountSecurityEventsPage extends StatefulWidget {
  const AccountSecurityEventsPage({super.key});

  @override
  State<AccountSecurityEventsPage> createState() =>
      _AccountSecurityEventsPageState();
}

class _AccountSecurityEventsPageState extends State<AccountSecurityEventsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await apiClient.get('/api/auth/security-events');
      final list = (response.data as Map?)?['data']?['list'];
      _items = list is List
          ? list.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : [];
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '安全记录加载失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await apiClient.post('/api/auth/security-events');
      for (final item in _items) {
        item['read'] = true;
      }
      if (mounted) {
        setState(() {});
        showAppToast(context, '安全记录已全部标记为已读');
      }
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '操作失败'));
    }
  }

  String _time(Object? raw) {
    final value = DateTime.tryParse('$raw')?.toLocal();
    if (value == null) return '';
    return '${value.month}月${value.day}日 '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '账号安全记录',
        loading: _loading,
        actions: [
          TextButton(
            onPressed: _items.any((item) => item['read'] != true)
                ? _markAllRead
                : null,
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFF24272D)),
            child: const Text('全部已读'),
          ),
        ],
        children: [
          const SettingsSectionLabel('最近50条'),
          for (var i = 0; i < _items.length; i++) ...[
            SettingsRow(
              icon: _items[i]['type'] == 'security_login'
                  ? Icons.devices_outlined
                  : Icons.security_outlined,
              title:
                  '${_items[i]['read'] == true ? '' : '● '}${_items[i]['title'] ?? '账号安全提醒'}',
              subtitle: '${_items[i]['content'] ?? ''}',
              value: _time(_items[i]['createdAt']),
            ),
            if (i != _items.length - 1) const SettingsDivider(),
          ],
          if (_items.isEmpty) ...[
            const SettingsHint('暂无账号安全事件。新设备登录、修改密码或更换手机号后会在这里留下记录。'),
            SettingsPrimaryButton(label: '重新加载', onPressed: _load),
          ],
        ],
      );
}

class LoginDevicesPage extends StatefulWidget {
  const LoginDevicesPage({super.key});

  @override
  State<LoginDevicesPage> createState() => _LoginDevicesPageState();
}

class _LoginDevicesPageState extends State<LoginDevicesPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/api/auth/sessions');
      final list = (response.data as Map?)?['data']?['list'];
      if (list is List && mounted) {
        _items = list.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '设备列表加载失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出该设备？'),
        content: Text('${item['deviceName'] ?? '该设备'} 将需要重新登录。'),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: settingsFilledActionStyle(),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认退出')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final sessionId = '${item['sessionId'] ?? ''}'.trim();
      final deviceId = '${item['deviceId'] ?? ''}'.trim();
      final identifier = sessionId.isNotEmpty ? sessionId : deviceId;
      if (identifier.isEmpty) {
        showAppToast(context, '会话信息不完整，请刷新后重试');
        return;
      }
      await apiClient
          .delete('/api/auth/sessions/${Uri.encodeComponent(identifier)}');
      if (mounted) showAppToast(context, '设备已退出');
      await _load();
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '移除失败'));
    }
  }

  Future<void> _logoutOthers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出其他设备？'),
        content: const Text('除当前设备外，其他所有设备都需要重新登录。'),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: settingsFilledActionStyle(),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认退出')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final response = await apiClient.post('/api/auth/sessions/logout-others');
      final removed = (response.data as Map?)?['data']?['removed'] ?? 0;
      if (mounted) showAppToast(context, '已退出 $removed 个其他会话');
      await _load();
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '操作失败'));
    }
  }

  String _time(Object? raw) {
    final value = DateTime.tryParse('$raw')?.toLocal();
    if (value == null) return '时间未知';
    return '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '登录设备',
        loading: _loading,
        actions: [
          TextButton(
            style: settingsTextActionStyle(),
            onPressed: _logoutOthers,
            child: const Text('退出其他设备'),
          ),
        ],
        children: [
          const SettingsSectionLabel('当前有效会话'),
          for (var i = 0; i < _items.length; i++) ...[
            SettingsRow(
              icon: _items[i]['platform'] == 'ios'
                  ? Icons.phone_iphone_rounded
                  : Icons.phone_android_rounded,
              title:
                  '${_items[i]['deviceName'] ?? '设备'}${_items[i]['isCurrent'] == true ? '（当前）' : ''}',
              subtitle: '最近活跃 ${_time(_items[i]['lastActiveAt'])}',
              value: _items[i]['isCurrent'] == true ? '正在使用' : null,
              onTap: _items[i]['isCurrent'] == true
                  ? null
                  : () => _remove(_items[i]),
            ),
            if (i != _items.length - 1) const SettingsDivider(),
          ],
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无设备记录')),
            ),
        ],
      );
}

class MinorProtectionPage extends StatefulWidget {
  const MinorProtectionPage({super.key});

  @override
  State<MinorProtectionPage> createState() => _MinorProtectionPageState();
}

class _MinorProtectionPageState extends State<MinorProtectionPage> {
  bool _loading = true;
  bool _enabled = false;
  bool _hasPin = false;
  bool _ageLocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/api/auth/minor-mode');
      final data = (response.data as Map?)?['data'];
      if (data is Map) {
        _enabled = data['enabled'] == true;
        _hasPin = data['hasGuardianPin'] == true;
        _ageLocked = data['ageLocked'] == true;
      }
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '保护状态读取失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askPin(String title, {String? hint}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(hintText: hint ?? '输入4至6位数字'),
        ),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            style: settingsFilledActionStyle(),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _toggle(bool value) async {
    if (!value && _ageLocked) {
      showAppToast(context, '账号年龄未满18岁，保护模式不能关闭');
      return;
    }
    final pin = (!_hasPin || !value)
        ? await _askPin(value ? '设置监护密码' : '验证监护密码')
        : null;
    if ((!_hasPin || !value) && (pin == null || pin.isEmpty)) return;
    try {
      final response = await apiClient.post('/api/auth/minor-mode', data: {
        'enabled': value,
        if (pin != null) 'guardianPin': pin,
      });
      final data = (response.data as Map?)?['data'];
      _enabled = data?['enabled'] == true;
      _hasPin = data?['hasGuardianPin'] == true;
      if (Get.isRegistered<AuthState>()) {
        await Get.find<AuthState>()
            .prefs
            .setBool(AppConstants.keyMinorMode, _enabled);
        Get.find<AuthState>().update();
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '设置失败'));
    }
  }

  Future<void> _changePin() async {
    final current = _hasPin ? await _askPin('验证当前监护密码') : '';
    if (_hasPin && (current == null || current.isEmpty)) return;
    final next = await _askPin(_hasPin ? '设置新监护密码' : '设置监护密码');
    if (next == null || next.isEmpty) return;
    try {
      await apiClient.post('/api/auth/minor-mode', data: {
        'action': 'set_pin',
        'currentPin': current,
        'newPin': next,
      });
      _hasPin = true;
      if (mounted) setState(() {});
      if (mounted) showAppToast(context, '监护密码已更新');
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '密码设置失败'));
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '未成年人保护',
        loading: _loading,
        children: [
          const SettingsSectionLabel('保护模式'),
          SettingsSwitchRow(
            icon: Icons.child_care_rounded,
            title: '未成年人保护模式',
            subtitle: _ageLocked ? '已根据账号年龄强制开启' : '限制支付、付费咨询和成人社交能力',
            value: _enabled,
            onChanged: _toggle,
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.pin_outlined,
            title: _hasPin ? '修改监护密码' : '设置监护密码',
            subtitle: '关闭保护或修改规则时需要验证',
            onTap: _changePin,
          ),
          const SettingsSectionLabel('开启后自动限制'),
          const SettingsRow(icon: Icons.payments_outlined, title: '充值、礼物与付费咨询'),
          const SettingsDivider(),
          const SettingsRow(icon: Icons.mic_none_rounded, title: '语音匹配与陌生人强互动'),
          const SettingsDivider(),
          const SettingsRow(icon: Icons.schedule_rounded, title: '夜间使用提醒与内容保护'),
          const Padding(
            padding: EdgeInsets.fromLTRB(66, 12, 24, 28),
            child: Text('保护规则由服务端执行，重新安装或更换设备不会绕过。',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: Color(0xFF9CA3AF))),
          ),
        ],
      );
}

class SafetyCenterPage extends StatefulWidget {
  const SafetyCenterPage({super.key});

  @override
  State<SafetyCenterPage> createState() => _SafetyCenterPageState();
}

class _SafetyCenterPageState extends State<SafetyCenterPage> {
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _safety = {};
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final responses = await Future.wait([
        apiClient.get('/api/config/safety-center'),
        apiClient.get('/api/community/report'),
      ]);
      final safetyData = (responses[0].data as Map?)?['data'];
      final reportList = (responses[1].data as Map?)?['data']?['list'];
      if (safetyData is Map) {
        _safety = Map<String, dynamic>.from(safetyData);
      }
      if (reportList is List) {
        _reports =
            reportList.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    } catch (error) {
      _loadError = _apiMessage(error, '安全数据加载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _items(String key) {
    final value = _safety[key];
    if (value is! List) return [];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  String _status(Object? value) => switch ('$value') {
        'resolved' || 'handled' => '已处理',
        'approved' => '申诉通过',
        'rejected' => '未通过',
        _ => '处理中',
      };

  String _accountStatus(Object? value) => switch ('$value') {
        'suspended' => '已封禁',
        'restricted' => '功能受限',
        _ => '正常',
      };

  String _severity(Object? value) => switch ('$value') {
        'critical' => '严重',
        'high' => '高风险',
        'low' => '低风险',
        _ => '中风险',
      };

  String _penalty(Object? value) => switch ('$value') {
        'ban' => '账号封禁',
        'mute' => '禁止发言',
        _ => '安全警告',
      };

  String _date(Object? value) {
    final text = '$value';
    if (text.isEmpty || text == 'null') return '';
    final normalized = text.replaceFirst('T', ' ');
    return normalized.length > 16 ? normalized.substring(0, 16) : normalized;
  }

  void _showRule(Map<String, dynamic> rule) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${rule['title'] ?? '平台安全规则'}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Text('${rule['description'] ?? ''}',
                    style: const TextStyle(fontSize: 15, height: 1.7)),
                const SizedBox(height: 14),
                const Text('平台会根据内容语境、发布场景和账号行为综合判断。科普、新闻和劝阻类正常表达不会仅因单个词语受到处罚。',
                    style: TextStyle(
                        fontSize: 13, height: 1.6, color: Color(0xFF7B8088))),
              ],
            ),
          ),
        ),
      );

  Future<void> _submitAppeal(int violationId) async {
    var draft = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提交内容申诉'),
        content: TextField(
          onChanged: (value) => draft = value,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: '请说明内容用途、语境及认为判定有误的原因（不少于10个字）',
          ),
        ),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            style: settingsTextActionStyle(),
            onPressed: () {
              final value = draft.trim();
              if (value.replaceAll(RegExp(r'\s'), '').length < 10) {
                showAppToast(ctx, '申诉说明不少于10个字');
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await apiClient.post('/api/config/safety-center/appeals', data: {
        'violationId': violationId,
        'reason': reason,
      });
      if (!mounted) return;
      Navigator.maybePop(context);
      showAppToast(context, '申诉已提交，处理结果会在安全中心更新');
      await _load();
    } catch (error) {
      if (mounted) showAppToast(context, _apiMessage(error, '申诉提交失败'));
    }
  }

  void _showViolation(Map<String, dynamic> item) {
    final appeals = _items('appeals');
    final pendingAppeal = appeals.any((appeal) =>
        '${appeal['violationId']}' == '${item['id']}' &&
        const {'pending', 'processing'}.contains('${appeal['status']}'));
    final approvedAppeal = appeals.any((appeal) =>
        '${appeal['violationId']}' == '${item['id']}' &&
        '${appeal['status']}' == 'approved');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('违规拦截详情',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Text(
                  '${item['category'] ?? '平台安全规则'} · ${_severity(item['severity'])}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text('${item['excerpt'] ?? ''}',
                  style: const TextStyle(fontSize: 15, height: 1.6)),
              const SizedBox(height: 8),
              Text(
                  '${item['decision'] == 'overturned' ? '处理结果：申诉通过，原判定已撤销' : '处理结果：内容已拦截，未发送或公开'}\n时间：${_date(item['createdAt'])}',
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: Color(0xFF7B8088))),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: pendingAppeal || approvedAppeal
                      ? null
                      : () => _submitAppeal((item['id'] as num).toInt()),
                  child: Text(approvedAppeal
                      ? '判定已撤销'
                      : pendingAppeal
                          ? '申诉处理中'
                          : '对本次判定申诉'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _safetyTips() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Text(
              '不要向任何人提供验证码、身份证、银行卡或详细住址；不要因语音房、私信或命理咨询要求而转到站外付款。遇到辱骂、色情、诈骗和私下引流，请保留证据后举报并拉黑。',
              style: TextStyle(fontSize: 15, height: 1.7),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final violations = _items('violations');
    final penalties = _items('penalties');
    final appeals = _items('appeals');
    final guidelines = _items('guidelines');
    final accountStatus = _accountStatus(_safety['accountStatus']);
    final violationCount = (_safety['violationCount30d'] as num?)?.toInt() ?? 0;
    final protection = _safety['protectionStatus'] is Map
        ? Map<String, dynamic>.from(_safety['protectionStatus'] as Map)
        : <String, dynamic>{};
    final mediaProtected = const ['image', 'video', 'audio'].every(
      (key) => const {'active', 'fail_closed'}.contains('${protection[key]}'),
    );
    return SettingsScaffold(
      title: '安全中心',
      loading: _loading,
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      children: [
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Text(_loadError!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFB42318))),
          ),
        const SettingsSectionLabel('账号安全状态'),
        SettingsRow(
          key: const ValueKey('safety-account-status'),
          icon: accountStatus == '正常'
              ? Icons.verified_user_outlined
              : Icons.gpp_maybe_outlined,
          title: '账号状态',
          subtitle: '近30天拦截记录 $violationCount 条',
          value: accountStatus,
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.policy_outlined,
          title: '当前处罚',
          subtitle:
              penalties.isEmpty ? '暂无禁言或封禁处罚' : '${penalties.length} 项处罚正在生效',
          value: penalties.isEmpty ? '无' : '查看',
          onTap: penalties.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (ctx) => SafeArea(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                        itemCount: penalties.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, index) {
                          final item = penalties[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_penalty(item['type'])),
                            subtitle: Text('${item['reason'] ?? '违反平台安全规则'}'),
                            trailing: Text(item['expireAt'] == null
                                ? '长期'
                                : '至 ${_date(item['expireAt'])}'),
                          );
                        },
                      ),
                    ),
                  ),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.shield_outlined,
          title: '内容安全防护',
          subtitle: mediaProtected ? '文字、图片、视频、语音均执行安全审核' : '文字审核已开启，媒体审核维护中',
          value: mediaProtected ? '已开启' : '维护中',
        ),
        const SettingsSectionLabel('平台安全规则'),
        for (var i = 0; i < guidelines.length; i++) ...[
          SettingsRow(
            icon: const [
              Icons.no_drinks_outlined,
              Icons.child_care_outlined,
              Icons.security_outlined,
              Icons.front_hand_outlined,
              Icons.privacy_tip_outlined,
            ][i % 5],
            title: '${guidelines[i]['title'] ?? '平台安全规则'}',
            subtitle: '${guidelines[i]['description'] ?? ''}',
            onTap: () => _showRule(guidelines[i]),
          ),
          if (i != guidelines.length - 1) const SettingsDivider(),
        ],
        const SettingsSectionLabel('我的违规与处罚'),
        if (violations.isEmpty && penalties.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(66, 14, 24, 24),
            child: Text('暂无违规或处罚记录',
                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ),
        for (var i = 0; i < violations.length; i++) ...[
          SettingsRow(
            key: ValueKey('safety-violation-${violations[i]['id']}'),
            icon: Icons.report_gmailerrorred_outlined,
            title: '${violations[i]['category'] ?? '内容违规'}',
            subtitle: '${violations[i]['excerpt'] ?? '内容已被平台拦截'}',
            value: _date(violations[i]['createdAt']),
            onTap: () => _showViolation(violations[i]),
          ),
          if (i != violations.length - 1) const SettingsDivider(),
        ],
        if (appeals.isNotEmpty) ...[
          const SettingsSectionLabel('我的内容申诉'),
          for (var i = 0; i < appeals.length; i++) ...[
            SettingsRow(
              icon: Icons.rate_review_outlined,
              title: '违规记录 #${appeals[i]['violationId']}',
              subtitle:
                  '${appeals[i]['handleResult'] ?? appeals[i]['reason'] ?? ''}',
              value: _status(appeals[i]['status']),
            ),
            if (i != appeals.length - 1) const SettingsDivider(),
          ],
        ],
        const SettingsSectionLabel('举报与安全工具'),
        const SettingsRow(
          icon: Icons.schedule_outlined,
          title: '举报处理时限：24小时',
          subtitle: '收到违规举报后24小时内审核并采取行动；核实后下架内容，限制或封禁违规账号。',
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.email_outlined,
          title: '联系内容安全团队',
          subtitle: '${LegalDocumentPage.contactEmail} · 点击复制，投诉违规内容或滥用行为',
          onTap: () async {
            await Clipboard.setData(
              const ClipboardData(text: LegalDocumentPage.contactEmail),
            );
            if (context.mounted) showAppToast(context, '内容安全联系邮箱已复制');
          },
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.description_outlined,
          title: '社区规则与用户协议',
          subtitle: '对违规内容、骚扰及欺凌零容忍',
          onTap: () => _push(
            context,
            const LegalDocumentPage(type: LegalDocumentType.userAgreement),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.outlined_flag_rounded,
          title: '我的举报记录',
          subtitle: _reports.isEmpty ? '暂无举报记录' : '${_reports.length} 条记录',
          onTap: _reports.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (ctx) => SafeArea(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, index) {
                          final item = _reports[index];
                          return ListTile(
                            title: Text('${item['reason'] ?? '举报'}'),
                            subtitle:
                                Text('${item['handleResult'] ?? '平台正在核实'}'),
                            trailing: Text(_status(item['status'])),
                          );
                        },
                      ),
                    ),
                  ),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.health_and_safety_outlined,
          title: '防诈骗与隐私安全指南',
          onTap: _safetyTips,
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.block_outlined,
          title: '拉黑名单',
          onTap: () => _push(context, const BlockedUsersPage()),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.support_agent_rounded,
          title: '账号与隐私申诉',
          onTap: () => _push(context, const PrivacyRightsPage()),
        ),
      ],
    );
  }
}

class MessageDiagnosticsPage extends StatefulWidget {
  const MessageDiagnosticsPage({super.key});

  @override
  State<MessageDiagnosticsPage> createState() => _MessageDiagnosticsPageState();
}

class _MessageDiagnosticsPageState extends State<MessageDiagnosticsPage> {
  static const _recorder = MethodChannel('xuanyu/audio_recorder');
  final Map<String, String> _results = {};
  bool _checking = false;
  bool _recording = false;

  Future<void> _runChecks() async {
    if (_checking) return;
    setState(() => _checking = true);
    final next = <String, String>{};
    try {
      await apiClient.get('/health');
      next['网络与服务'] = '正常';
    } catch (_) {
      next['网络与服务'] = '连接失败';
    }
    try {
      await apiClient.get('/api/auth/me');
      next['账号会话'] = '正常';
    } catch (_) {
      next['账号会话'] = '需要重新登录';
    }
    next['麦克风权限'] =
        (await Permission.microphone.status).isGranted ? '已允许' : '未允许';
    next['相机权限'] = (await Permission.camera.status).isGranted ? '已允许' : '未允许';
    next['通知权限'] =
        (await Permission.notification.status).isGranted ? '已允许' : '未允许';
    next['语音服务配置'] = AgoraConstants.appId.trim().isNotEmpty ? '已配置' : '未配置';
    if (mounted) {
      setState(() {
        _results
          ..clear()
          ..addAll(next);
        _checking = false;
      });
    }
  }

  Future<void> _microphoneTest() async {
    if (_recording) return;
    if (!await Permission.microphone.request().isGranted) {
      if (mounted) showAppToast(context, '请先允许麦克风权限');
      return;
    }
    setState(() => _recording = true);
    try {
      await _recorder.invokeMethod<void>('startRecording');
      if (mounted) showAppToast(context, '请讲话，3秒后自动回放');
      await Future<void>.delayed(const Duration(seconds: 3));
      final path = await _recorder.invokeMethod<String>('stopRecording');
      if (path == null) throw const FormatException();
      final player = AudioPlayer();
      await player.play(DeviceFileSource(path));
      await player.onPlayerComplete.first.timeout(const Duration(seconds: 10));
      await player.dispose();
      await File(path).delete().catchError((_) => File(path));
      if (mounted) showAppToast(context, '麦克风录音与回放正常');
    } catch (_) {
      try {
        await _recorder.invokeMethod<void>('cancelRecording');
      } catch (_) {}
      if (mounted) showAppToast(context, '测试失败，请检查麦克风或音量');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _copy() async {
    if (_results.isEmpty) await _runChecks();
    final report =
        _results.entries.map((e) => '${e.key}：${e.value}').join('\n');
    await Clipboard.setData(ClipboardData(text: '玄遇消息与语音诊断\n$report'));
    if (mounted) showAppToast(context, '诊断结果已复制（不包含账号凭据）');
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '消息与语音诊断',
        children: [
          const SettingsSectionLabel('自动检测'),
          SettingsRow(
            icon: Icons.troubleshoot_rounded,
            title: _checking ? '正在检测' : '开始检测',
            subtitle: '检查网络、会话、权限与语音服务配置',
            onTap: _checking ? null : _runChecks,
          ),
          for (final entry in _results.entries) ...[
            const SettingsDivider(),
            SettingsRow(
                icon: Icons.check_circle_outline_rounded,
                title: entry.key,
                value: entry.value),
          ],
          const SettingsSectionLabel('设备测试'),
          SettingsRow(
            icon: Icons.mic_none_rounded,
            title: _recording ? '正在录音测试' : '麦克风录音与回放',
            subtitle: '录制3秒并在本机回放，不会上传',
            onTap: _recording ? null : _microphoneTest,
          ),
          const SettingsDivider(),
          const SettingsRow(
              icon: Icons.settings_outlined,
              title: '系统权限设置',
              onTap: openAppSettings),
          const SettingsDivider(),
          SettingsRow(icon: Icons.copy_rounded, title: '复制诊断结果', onTap: _copy),
        ],
      );
}

class WalletSecurityPage extends StatefulWidget {
  const WalletSecurityPage({super.key});

  @override
  State<WalletSecurityPage> createState() => _WalletSecurityPageState();
}

class _WalletSecurityPageState extends State<WalletSecurityPage> {
  AppSettingsStore get store => AppSettingsStore.instance;

  Future<void> _giftConfirm(bool value) async {
    try {
      await store.update({'giftConfirmation': value});
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '玄遇币与支付安全',
        children: [
          const SettingsSectionLabel('资产'),
          SettingsRow(
              icon: Icons.account_balance_wallet_outlined,
              title: '余额与消费记录',
              onTap: () => _push(context, const BalancePage())),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.add_card_rounded,
              title: '充值玄遇币',
              onTap: () => _push(context, const RechargePage())),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.receipt_long_outlined,
              title: '订单记录',
              onTap: () => _push(context, const OrdersPage())),
          const SettingsSectionLabel('支付保护'),
          SettingsSwitchRow(
            icon: Icons.card_giftcard_rounded,
            title: '送礼前二次确认',
            subtitle: '开启后每次送礼都会确认礼物、数量和金额',
            value: store.boolValue('giftConfirmation'),
            onChanged: _giftConfirm,
          ),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.payment_rounded,
              title: '连线支付设置',
              subtitle: '管理玄遇币与支付宝免密',
              onTap: () =>
                  _push(context, const ConsultationPaymentSettingPage())),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.rule_rounded,
              title: '玄遇币与支付规则',
              onTap: () => _push(context,
                  const LegalDocumentPage(type: LegalDocumentType.coinRules))),
        ],
      );
}

class CreatorServicesPage extends StatefulWidget {
  const CreatorServicesPage({super.key});

  @override
  State<CreatorServicesPage> createState() => _CreatorServicesPageState();
}

class _CreatorServicesPageState extends State<CreatorServicesPage> {
  String _teacherStatus = '正在读取';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/api/auth/teacher/status');
      final value = '${(response.data as Map?)?['data']?['status'] ?? 'none'}';
      if (mounted) {
        setState(() => _teacherStatus = switch (value) {
              'approved' => '已认证',
              'pending' => '审核中',
              'rejected' => '需补充资料',
              _ => '未认证',
            });
      }
    } catch (_) {
      if (mounted) setState(() => _teacherStatus = '读取失败');
    }
  }

  void _teacher() {
    _push(
        context,
        _teacherStatus == '已认证'
            ? const TeacherWorkbenchPage()
            : const TeacherApplyPage());
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '创作者与认证',
        children: [
          const SettingsSectionLabel('身份与服务'),
          SettingsRow(
              icon: Icons.workspace_premium_outlined,
              title: '认证老师',
              value: _teacherStatus,
              onTap: _teacher),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.dashboard_customize_outlined,
              title: '老师服务工作台',
              subtitle: '已认证用户可管理价格、排班和服务',
              onTap: _teacher),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.face_retouching_natural_rounded,
              title: '虚拟头像工作室',
              onTap: () => _push(context, const VirtualAvatarStudioPage())),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.rule_folder_outlined,
              title: '老师入驻与结算规则',
              onTap: () => _push(
                  context,
                  const LegalDocumentPage(
                      type: LegalDocumentType.teacherServiceRules))),
        ],
      );
}

class GeneralAccessibilityPage extends StatefulWidget {
  const GeneralAccessibilityPage({super.key});

  @override
  State<GeneralAccessibilityPage> createState() =>
      _GeneralAccessibilityPageState();
}

class _GeneralAccessibilityPageState extends State<GeneralAccessibilityPage> {
  final store = AppSettingsStore.instance;
  bool _clearing = false;

  Future<void> _setting(String key, bool value) async {
    try {
      await store.update({key: value});
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，请稍后重试');
    }
  }

  Future<void> _clearCache() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await PageSnapshotCache.clearAll();
      final directory = await getTemporaryDirectory();
      if (await directory.exists()) {
        await for (final entity in directory.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
      if (mounted) showAppToast(context, '缓存已清理');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '通用与辅助功能',
        children: [
          const SettingsSectionLabel('显示与动效'),
          SettingsSwitchRow(
              icon: Icons.text_fields_rounded,
              title: '大号文字',
              subtitle: '全局文字放大，适合阅读',
              value: store.boolValue('largerText'),
              onChanged: (v) => _setting('largerText', v)),
          const SettingsDivider(),
          SettingsSwitchRow(
              icon: Icons.motion_photos_off_outlined,
              title: '减少动态效果',
              subtitle: '降低页面切换与装饰动画',
              value: store.boolValue('reduceMotion'),
              onChanged: (v) => _setting('reduceMotion', v)),
          const SettingsSectionLabel('存储与系统'),
          SettingsRow(
              icon: Icons.cleaning_services_outlined,
              title: _clearing ? '正在清理缓存' : '清理缓存',
              subtitle: '不删除聊天、订单或账号数据',
              onTap: _clearing ? null : _clearCache),
          const SettingsDivider(),
          const SettingsRow(
              icon: Icons.tune_rounded,
              title: '系统权限管理',
              subtitle: '相机、相册、麦克风、定位和通知',
              onTap: openAppSettings),
        ],
      );
}

class AboutSettingsPage extends StatefulWidget {
  const AboutSettingsPage({super.key});

  @override
  State<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends State<AboutSettingsPage> {
  String _version = AppConstants.appVersion;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    });
  }

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(
        const ClipboardData(text: LegalDocumentPage.contactEmail));
    if (context.mounted) showAppToast(context, '联系邮箱已复制');
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '关于玄遇',
        children: [
          const SettingsSectionLabel('版本与信息'),
          SettingsRow(
              icon: Icons.info_outline_rounded,
              title: '检查更新',
              subtitle: '当前版本 $_version',
              onTap: () => AppUpdateHost.checkNow(context)),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.email_outlined,
              title: '联系我们',
              value: LegalDocumentPage.contactEmail,
              onTap: () => _copyEmail(context)),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.verified_user_outlined,
              title: '备案信息',
              value: LegalDocumentPage.icpNumber,
              onTap: () => launchUrl(Uri.parse(LegalDocumentPage.beianUrl),
                  mode: LaunchMode.externalApplication)),
          const SettingsSectionLabel('协议与透明度'),
          SettingsRow(
              icon: Icons.description_outlined,
              title: '用户协议',
              onTap: () => _push(
                  context,
                  const LegalDocumentPage(
                      type: LegalDocumentType.userAgreement))),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: '隐私政策',
              onTap: () => _push(
                  context,
                  const LegalDocumentPage(
                      type: LegalDocumentType.privacyPolicy))),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.hub_outlined,
              title: '第三方信息共享清单',
              onTap: () => _push(
                  context,
                  const LegalDocumentPage(
                      type: LegalDocumentType.thirdPartyList))),
        ],
      );
}
