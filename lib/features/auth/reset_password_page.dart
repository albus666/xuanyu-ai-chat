import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

/// 忘记密码：手机号 + 短信验证码 + 新密码，重置后返回登录页
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loadingCode = false;
  bool _loadingSubmit = false;
  int _countdown = 0;

  @override
  void dispose() {
    _mobileController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final mobile = _mobileController.text.trim();
    if (mobile.length != 11) {
      _showSnack('请输入11位手机号');
      return;
    }
    setState(() => _loadingCode = true);
    try {
      await apiClient.post('/api/auth/sendCode',
          data: {'mobile': mobile, 'scene': 'resetPassword'});
      _showSnack('验证码已发送');
      _startCountdown();
    } on DioException catch (e) {
      _showSnack(
          (e.response?.data is Map ? e.response!.data['message'] : null) ??
              '发送失败');
    } finally {
      if (mounted) setState(() => _loadingCode = false);
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown = _countdown - 1);
      return _countdown > 0;
    });
  }

  Future<void> _submit() async {
    final mobile = _mobileController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (mobile.length != 11) {
      _showSnack('请输入11位手机号');
      return;
    }
    if (code.isEmpty) {
      _showSnack('请输入验证码');
      return;
    }
    if (password.length < 8 || password.length > 64) {
      _showSnack('新密码须为8至64位');
      return;
    }
    if (password != confirm) {
      _showSnack('两次输入的密码不一致');
      return;
    }

    setState(() => _loadingSubmit = true);
    try {
      await apiClient.post('/api/auth/resetPassword', data: {
        'mobile': mobile,
        'code': code,
        'password': password,
      });
      _showSnack('密码已重置，请使用新密码登录');
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      final msg =
          (e.response?.data is Map && e.response!.data.containsKey('message'))
              ? e.response!.data['message']?.toString()
              : null;
      _showSnack(msg ?? '重置失败');
    } finally {
      if (mounted) setState(() => _loadingSubmit = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showAppToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.lock_reset_rounded,
                  size: 48, color: AppColors.primary),
              const SizedBox(height: 28),
              Text('重置密码', style: AppTextStyles.displayLarge),
              const SizedBox(height: 8),
              Text('使用短信验证码验证身份后设置新密码',
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 40),
              AppTextField(
                label: '手机号',
                controller: _mobileController,
                hint: '请输入注册手机号',
                keyboardType: TextInputType.phone,
                prefixIcon: const Icon(Icons.phone_iphone_rounded),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: '验证码',
                      controller: _codeController,
                      hint: '6位数字',
                      keyboardType: TextInputType.number,
                      prefixIcon: const Icon(Icons.verified_outlined),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: AppButton(
                      label: _countdown > 0 ? '${_countdown}s' : '获取验证码',
                      onPressed: _countdown > 0 ? null : _sendCode,
                      loading: _loadingCode,
                      outline: true,
                      isFullWidth: false,
                      width: 110,
                      height: 48,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: '新密码',
                controller: _passwordController,
                hint: '8至64位',
                obscureText: _obscurePassword,
                keyboardType: TextInputType.visiblePassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppColors.textHint),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: '确认密码',
                controller: _confirmPasswordController,
                hint: '再次输入新密码',
                obscureText: _obscureConfirm,
                keyboardType: TextInputType.visiblePassword,
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppColors.textHint),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              const SizedBox(height: 40),
              AppButton(
                  label: '确认重置', onPressed: _submit, loading: _loadingSubmit),
            ],
          ),
        ),
      ),
    );
  }
}
