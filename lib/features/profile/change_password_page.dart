import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/bootstrap/auth_state.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import 'settings_ui.dart';

/// 已登录用户修改密码：验证原密码后让所有设备会话失效。
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loadingSubmit = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _message(Object error, String fallback) {
    if (error is DioException && error.response?.data is Map) {
      return '${(error.response!.data as Map)['message'] ?? fallback}';
    }
    return fallback;
  }

  Widget _visibilityButton(bool hidden, VoidCallback onPressed) => IconButton(
        tooltip: hidden ? '显示密码' : '隐藏密码',
        onPressed: onPressed,
        icon: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: const Color(0xFF6B7280),
        ),
      );

  Future<void> _submit() async {
    final oldPassword = _oldPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmation = _confirmPasswordController.text;
    if (oldPassword.isEmpty) {
      showAppToast(context, '请输入原密码');
      return;
    }
    if (newPassword.length < 8 || newPassword.length > 64) {
      showAppToast(context, '新密码须为8至64位');
      return;
    }
    if (oldPassword == newPassword) {
      showAppToast(context, '新密码不能与原密码相同');
      return;
    }
    if (newPassword != confirmation) {
      showAppToast(context, '两次输入的新密码不一致');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认修改密码？'),
        content: const Text('修改成功后所有设备都会退出登录，需要使用新密码重新登录。'),
        actions: [
          TextButton(
            style: settingsTextActionStyle(),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: settingsFilledActionStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loadingSubmit = true);
    try {
      if (Get.isRegistered<AuthState>() &&
          !await Get.find<AuthState>().prepareSessionChange()) {
        return;
      }
      await apiClient.post('/api/auth/changePassword', data: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      });
      if (!mounted) return;
      showAppToast(context, '密码已修改，请重新登录');
      if (Get.isRegistered<AuthState>()) {
        await Get.find<AuthState>().logout();
      }
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) showAppToast(context, _message(error, '修改失败'));
    } finally {
      if (mounted) setState(() => _loadingSubmit = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '修改密码',
        children: [
          const SettingsSectionLabel('身份验证'),
          SettingsFormField(
            label: '原密码',
            controller: _oldPasswordController,
            hint: '请输入当前登录密码',
            obscureText: _obscureOld,
            keyboardType: TextInputType.visiblePassword,
            suffix: _visibilityButton(
              _obscureOld,
              () => setState(() => _obscureOld = !_obscureOld),
            ),
          ),
          const SettingsDivider(),
          const SettingsSectionLabel('设置新密码'),
          SettingsFormField(
            label: '新密码',
            controller: _newPasswordController,
            hint: '请输入8至64位新密码',
            helperText: '建议同时包含字母、数字和符号，不要使用其他平台相同密码。',
            obscureText: _obscureNew,
            keyboardType: TextInputType.visiblePassword,
            suffix: _visibilityButton(
              _obscureNew,
              () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
          const SettingsDivider(),
          SettingsFormField(
            label: '确认新密码',
            controller: _confirmPasswordController,
            hint: '请再次输入新密码',
            obscureText: _obscureConfirm,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            suffix: _visibilityButton(
              _obscureConfirm,
              () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          const SettingsHint('为了保护账号，修改成功后全部登录设备都需要重新验证。'),
          SettingsPrimaryButton(
            label: '确认修改',
            onPressed: _submit,
            loading: _loadingSubmit,
          ),
        ],
      );
}
