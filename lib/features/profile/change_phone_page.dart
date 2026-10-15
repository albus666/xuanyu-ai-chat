import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import 'settings_ui.dart';

/// 修改绑定手机：原手机验证码 + 新手机号 + 新手机验证码。
class ChangePhonePage extends StatefulWidget {
  const ChangePhonePage({super.key, this.currentMobile});

  final String? currentMobile;

  @override
  State<ChangePhonePage> createState() => _ChangePhonePageState();
}

class _ChangePhonePageState extends State<ChangePhonePage> {
  final _oldCodeController = TextEditingController();
  final _newMobileController = TextEditingController();
  final _newCodeController = TextEditingController();
  Timer? _oldTimer;
  Timer? _newTimer;
  String? _currentMobile;
  String? _loadError;
  bool _loadingMobile = false;
  bool _loadingOldCode = false;
  bool _loadingNewCode = false;
  bool _loadingSubmit = false;
  int _countdownOld = 0;
  int _countdownNew = 0;

  @override
  void initState() {
    super.initState();
    _currentMobile = widget.currentMobile?.trim();
    if ((_currentMobile ?? '').isEmpty) _fetchCurrentMobile();
  }

  @override
  void dispose() {
    _oldTimer?.cancel();
    _newTimer?.cancel();
    _oldCodeController.dispose();
    _newMobileController.dispose();
    _newCodeController.dispose();
    super.dispose();
  }

  String _message(Object error, String fallback) {
    if (error is DioException && error.response?.data is Map) {
      return '${(error.response!.data as Map)['message'] ?? fallback}';
    }
    return fallback;
  }

  Future<void> _fetchCurrentMobile() async {
    setState(() {
      _loadingMobile = true;
      _loadError = null;
    });
    try {
      final response = await apiClient.get('/api/auth/me');
      final mobile =
          '${(response.data as Map?)?['data']?['mobile'] ?? ''}'.trim();
      if (mobile.length != 11) throw const FormatException();
      _currentMobile = mobile;
    } catch (_) {
      _loadError = '无法读取当前绑定手机号，请检查网络后重试。';
    } finally {
      if (mounted) setState(() => _loadingMobile = false);
    }
  }

  bool _validMobile(String value) => RegExp(r'^1[3-9]\d{9}$').hasMatch(value);

  Future<void> _sendCode({required bool oldMobile}) async {
    final mobile =
        oldMobile ? (_currentMobile ?? '') : _newMobileController.text.trim();
    if (!_validMobile(mobile)) {
      showAppToast(context, oldMobile ? '当前手机号无效' : '请输入正确的新手机号');
      return;
    }
    if (!oldMobile && mobile == _currentMobile) {
      showAppToast(context, '新手机号不能与当前手机号相同');
      return;
    }
    setState(() {
      if (oldMobile) {
        _loadingOldCode = true;
      } else {
        _loadingNewCode = true;
      }
    });
    try {
      await apiClient.post('/api/auth/sendCode',
          data: {'mobile': mobile, 'scene': 'changePhone'});
      if (!mounted) return;
      showAppToast(context, oldMobile ? '验证码已发送至当前手机' : '验证码已发送至新手机');
      _startCountdown(oldMobile: oldMobile);
    } catch (error) {
      if (mounted) showAppToast(context, _message(error, '验证码发送失败'));
    } finally {
      if (mounted) {
        setState(() {
          if (oldMobile) {
            _loadingOldCode = false;
          } else {
            _loadingNewCode = false;
          }
        });
      }
    }
  }

  void _startCountdown({required bool oldMobile}) {
    final previous = oldMobile ? _oldTimer : _newTimer;
    previous?.cancel();
    setState(() {
      if (oldMobile) {
        _countdownOld = 60;
      } else {
        _countdownNew = 60;
      }
    });
    final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (oldMobile) {
          _countdownOld--;
          if (_countdownOld <= 0) timer.cancel();
        } else {
          _countdownNew--;
          if (_countdownNew <= 0) timer.cancel();
        }
      });
    });
    if (oldMobile) {
      _oldTimer = timer;
    } else {
      _newTimer = timer;
    }
  }

  Future<void> _submit() async {
    final oldCode = _oldCodeController.text.trim();
    final newMobile = _newMobileController.text.trim();
    final newCode = _newCodeController.text.trim();
    if (oldCode.length != 6) {
      showAppToast(context, '请输入当前手机收到的6位验证码');
      return;
    }
    if (!_validMobile(newMobile)) {
      showAppToast(context, '请输入正确的新手机号');
      return;
    }
    if (newMobile == _currentMobile) {
      showAppToast(context, '新手机号不能与当前手机号相同');
      return;
    }
    if (newCode.length != 6) {
      showAppToast(context, '请输入新手机收到的6位验证码');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认更换绑定手机？'),
        content: Text('更换后将使用 ${_maskMobile(newMobile)} 登录，其他设备会退出登录。'),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: settingsFilledActionStyle(),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认更换')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loadingSubmit = true);
    try {
      await apiClient.post('/api/auth/changePhone', data: {
        'oldCode': oldCode,
        'newMobile': newMobile,
        'newCode': newCode,
      });
      if (!mounted) return;
      showAppToast(context, '绑定手机已修改，其他设备已安全退出');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showAppToast(context, _message(error, '修改失败'));
    } finally {
      if (mounted) setState(() => _loadingSubmit = false);
    }
  }

  String _maskMobile(String mobile) => mobile.length == 11
      ? '${mobile.substring(0, 3)}****${mobile.substring(7)}'
      : mobile;

  Widget _sendButton({required bool oldMobile}) {
    final loading = oldMobile ? _loadingOldCode : _loadingNewCode;
    final countdown = oldMobile ? _countdownOld : _countdownNew;
    return TextButton(
      onPressed: loading || countdown > 0
          ? null
          : () => _sendCode(oldMobile: oldMobile),
      style: TextButton.styleFrom(foregroundColor: const Color(0xFF24272D)),
      child: Text(loading
          ? '发送中'
          : countdown > 0
              ? '${countdown}s'
              : '获取验证码'),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '修改绑定手机',
        loading: _loadingMobile,
        children: _loadError != null
            ? [
                SettingsHint(_loadError!),
                SettingsPrimaryButton(
                    label: '重新加载', onPressed: _fetchCurrentMobile),
              ]
            : [
                const SettingsSectionLabel('验证当前手机'),
                SettingsRow(
                  icon: Icons.phone_iphone_rounded,
                  title: '当前绑定',
                  value: _maskMobile(_currentMobile ?? ''),
                ),
                const SettingsDivider(),
                SettingsFormField(
                  label: '当前手机验证码',
                  controller: _oldCodeController,
                  hint: '请输入6位数字',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  suffix: _sendButton(oldMobile: true),
                ),
                const SettingsSectionLabel('绑定新手机'),
                SettingsFormField(
                  label: '新手机号',
                  controller: _newMobileController,
                  hint: '请输入11位手机号',
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                ),
                const SettingsDivider(),
                SettingsFormField(
                  label: '新手机验证码',
                  controller: _newCodeController,
                  hint: '请输入6位数字',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  suffix: _sendButton(oldMobile: false),
                ),
                const SettingsHint('更换成功后，当前设备保持登录，其他设备将被安全退出。'),
                SettingsPrimaryButton(
                  label: '确认修改',
                  onPressed: _submit,
                  loading: _loadingSubmit,
                ),
              ],
      );
}
