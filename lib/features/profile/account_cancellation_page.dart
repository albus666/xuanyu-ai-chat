import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import 'settings_ui.dart';

/// 账号注销采用“资格检查 → 身份验证 → 明示确认 → 冷静期可撤销”的完整流程。
class AccountCancellationPage extends StatefulWidget {
  const AccountCancellationPage({super.key});

  @override
  State<AccountCancellationPage> createState() =>
      _AccountCancellationPageState();
}

class _AccountCancellationPageState extends State<AccountCancellationPage> {
  final _codeController = TextEditingController();
  final _confirmationController = TextEditingController();
  Timer? _timer;
  bool _acknowledged = false;
  bool _submitting = false;
  bool _withdrawing = false;
  bool _checking = true;
  bool _sendingCode = false;
  bool _eligible = false;
  int _countdown = 0;
  String _maskedMobile = '当前绑定手机';
  Map<String, dynamic>? _pendingRequest;
  List<Map<String, dynamic>> _blockers = [];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  String _message(Object error, String fallback) {
    if (error is DioException && error.response?.data is Map) {
      return '${(error.response!.data as Map)['message'] ?? fallback}';
    }
    return fallback;
  }

  Future<void> _loadStatus() async {
    if (mounted) setState(() => _checking = true);
    try {
      final responses = await Future.wait([
        apiClient.get('/api/auth/privacy/requests'),
        apiClient.get('/api/auth/privacy/cancellation-check'),
      ]);
      final requests = _maps((responses[0].data as Map?)?['data']?['list']);
      final check = (responses[1].data as Map?)?['data'];
      Map<String, dynamic>? pending;
      for (final item in requests) {
        final status = '${item['status']}';
        if (const {'cancel', 'delete'}.contains('${item['type']}') &&
            const {'pending', 'processing'}.contains(status)) {
          pending = item;
          break;
        }
      }
      if (check is Map) {
        _eligible = check['eligible'] == true;
        _maskedMobile = check['maskedMobile']?.toString() ?? '当前绑定手机';
        _blockers = _maps(check['blockers']);
      }
      _pendingRequest = pending;
    } catch (error) {
      if (mounted) {
        showAppToast(context, _message(error, '注销状态核验失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _sendCode() async {
    if (_sendingCode || _countdown > 0 || !_eligible) return;
    setState(() => _sendingCode = true);
    try {
      await apiClient.post(
        '/api/auth/sendCode',
        data: const {'scene': 'cancelAccount'},
      );
      if (!mounted) return;
      showAppToast(context, '验证码已发送至 $_maskedMobile');
      setState(() => _countdown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _countdown--);
        if (_countdown <= 0) timer.cancel();
      });
    } catch (error) {
      if (mounted) showAppToast(context, _message(error, '验证码发送失败'));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _submit() async {
    if (!_acknowledged || _submitting || !_eligible) return;
    if (_codeController.text.trim().isEmpty) {
      showAppToast(context, '请输入短信验证码');
      return;
    }
    if (_confirmationController.text.trim() != '确认注销') {
      showAppToast(context, '请完整输入“确认注销”');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('最后确认注销账号？'),
        content: const Text(
          '提交后进入 15 天冷静期，账号仍可正常登录和使用。冷静期内可随时撤销；到期后才会执行不可恢复的数据处理。',
        ),
        actions: [
          TextButton(
            style: settingsTextActionStyle(),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          TextButton(
            style: settingsTextActionStyle(destructive: true),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final response = await apiClient.post(
        '/api/auth/privacy/requests',
        data: {
          'type': 'cancel',
          'remark': '用户从设置页完成身份验证并主动提交注销申请',
          'confirmed': true,
          'confirmationText': _confirmationController.text.trim(),
          'verificationCode': _codeController.text.trim(),
        },
      );
      if (!mounted) return;
      showAppToast(
        context,
        (response.data as Map?)?['message']?.toString() ?? '注销申请已提交',
      );
      _acknowledged = false;
      _codeController.clear();
      _confirmationController.clear();
      await _loadStatus();
    } on DioException catch (error) {
      final blockers =
          _maps((error.response?.data as Map?)?['data']?['blockers']);
      if (blockers.isNotEmpty) {
        _blockers = blockers;
        _eligible = false;
        if (mounted) setState(() {});
      }
      if (mounted) {
        showAppToast(context, _message(error, '暂时无法提交，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _withdraw() async {
    final requestId = _pendingRequest?['id'];
    if (requestId == null || _withdrawing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销注销申请？'),
        content: const Text('撤销后账号和现有资料继续保留，之后仍可重新发起注销。'),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: settingsFilledActionStyle(),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认撤销')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _withdrawing = true);
    try {
      final response = await apiClient
          .post('/api/auth/privacy/requests/$requestId/withdraw');
      if (!mounted) return;
      showAppToast(
        context,
        (response.data as Map?)?['message']?.toString() ?? '注销申请已撤销',
      );
      await _loadStatus();
    } catch (error) {
      if (mounted) showAppToast(context, _message(error, '撤销失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  String _date(Object? raw) {
    final value = DateTime.tryParse('$raw')?.toLocal();
    if (value == null) return '处理完成前';
    return '${value.year}年${value.month}月${value.day}日 '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '注销账号',
        loading: _checking,
        actions: [
          IconButton(
            tooltip: '重新核验',
            onPressed: _checking ? null : _loadStatus,
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
        ],
        children: _pendingRequest != null
            ? [
                const SettingsSectionLabel('申请状态'),
                const SettingsRow(
                  icon: Icons.schedule_outlined,
                  title: '注销冷静期进行中',
                  value: '15天内可撤销',
                ),
                const SettingsDivider(),
                SettingsHint(
                  '预计 ${_date(_pendingRequest!['eligibleAt'])} 后执行最终注销。冷静期内账号可正常登录和使用，撤销不会丢失资料。',
                ),
                SettingsPrimaryButton(
                  label: '撤销注销申请',
                  onPressed: _withdraw,
                  loading: _withdrawing,
                ),
              ]
            : [
                const SettingsSectionLabel('注销须知'),
                const SettingsHint(
                  '• 未完成订单、退款、售后或争议处理完成后，才能申请注销。\n'
                  '• 提交后进入15天冷静期，期间不会封禁账号或强制退出。\n'
                  '• 冷静期内可随时撤销；到期执行后，账号资料无法恢复。\n'
                  '• 依法需要保存的交易与安全记录会在法定期限内限制保存。',
                ),
                if (_blockers.isNotEmpty) ...[
                  const SettingsSectionLabel('暂不满足注销条件'),
                  for (var i = 0; i < _blockers.length; i++) ...[
                    SettingsRow(
                      icon: Icons.info_outline_rounded,
                      title: '${_blockers[i]['title'] ?? '存在未完成事项'}',
                      subtitle: '${_blockers[i]['action'] ?? '请处理后重试'}',
                      destructive: true,
                    ),
                    if (i != _blockers.length - 1) const SettingsDivider(),
                  ],
                  SettingsPrimaryButton(
                    label: '重新核验',
                    onPressed: _loadStatus,
                  ),
                ] else ...[
                  const SettingsSectionLabel('身份验证'),
                  CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF24272D),
                    value: _acknowledged,
                    onChanged: (value) =>
                        setState(() => _acknowledged = value == true),
                    title: const Text('我已阅读并理解上述影响',
                        style: TextStyle(fontSize: 15)),
                  ),
                  const SettingsDivider(indent: 24),
                  SettingsFormField(
                    label: '短信验证码',
                    controller: _codeController,
                    hint: '发送至 $_maskedMobile',
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    suffix: TextButton(
                      onPressed:
                          _acknowledged && _countdown <= 0 ? _sendCode : null,
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF24272D)),
                      child: Text(_sendingCode
                          ? '发送中'
                          : _countdown > 0
                              ? '${_countdown}s'
                              : '获取验证码'),
                    ),
                  ),
                  const SettingsDivider(indent: 24),
                  SettingsFormField(
                    label: '确认文字',
                    controller: _confirmationController,
                    hint: '请输入“确认注销”',
                    textInputAction: TextInputAction.done,
                  ),
                  const SettingsHint('系统还会在提交前再次询问确认；提交成功后可以在本页撤销。'),
                  SettingsPrimaryButton(
                    label: '提交注销申请',
                    onPressed: _acknowledged ? _submit : null,
                    loading: _submitting,
                    destructive: true,
                  ),
                ],
              ],
      );
}
