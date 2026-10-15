import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/auth/saved_account_store.dart';
import '../../core/network/api_client.dart';
import '../../core/device/app_device_identity.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/user_cache_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import 'register_page.dart';
import 'reset_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoginSuccess});
  final VoidCallback onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _usePassword = false;
  bool _obscurePassword = true;
  bool _loadingCode = false;
  bool _loadingLogin = false;
  int _countdown = 0;

  @override
  void dispose() {
    _mobileController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
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
      await apiClient.post('/api/auth/sendCode', data: {'mobile': mobile});
      _showSnack('验证码已发送');
      _startCountdown();
    } on DioException catch (e) {
      _showSnack(e.response?.data['message'] ?? '发送失败');
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

  Future<void> _login() async {
    final account = _mobileController.text.trim();
    if (!_usePassword && account.length != 11) {
      _showSnack('请输入有效手机号');
      return;
    }
    if (_usePassword && (account.length < 4 || account.length > 32)) {
      _showSnack('请输入手机号');
      return;
    }
    setState(() => _loadingLogin = true);
    try {
      final device = await appDevicePayload();
      final res = await apiClient.post(
          _usePassword ? '/api/auth/loginByPassword' : '/api/auth/login',
          data: {
            'mobile': account,
            if (_usePassword)
              'password': _passwordController.text
            else
              'code': _codeController.text.trim(),
            ...device,
          });
      final d = res.data['data'];
      if (d == null) {
        _showSnack(res.data['message'] ?? '登录失败');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await clearUserDependentCache();
      await prefs.setString(AppConstants.keyToken, d['token']);
      if (d['userId'] != null) {
        await prefs.setInt(
            AppConstants.keyUserId, (d['userId'] as num).toInt());
        await SavedAccountStore.rememberLogin(
          token: d['token'].toString(),
          userId: (d['userId'] as num).toInt(),
          account: account,
          nickname: d['nickname']?.toString() ?? '',
          avatarUrl: d['avatarUrl']?.toString() ?? '',
          minorMode: d['minorMode'] == true || d['minorMode'] == 1,
        );
      }
      await prefs.setBool(AppConstants.keyNeedOnboarding, false);
      setupApiClientToken(d['token']);
      widget.onLoginSuccess();
    } on DioException catch (e) {
      _showSnack(e.response?.data['message'] ?? '登录失败');
    } finally {
      if (mounted) setState(() => _loadingLogin = false);
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
      body: Stack(
        children: [
          _buildBackgroundDecoration(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  _buildLogo(),
                  const SizedBox(height: 32),
                  Text('欢迎回来', style: AppTextStyles.displayLarge),
                  const SizedBox(height: 48),
                  _buildModeSwitcher(),
                  const SizedBox(height: 32),
                  AppTextField(
                      label: '手机号',
                      controller: _mobileController,
                      hint: '请输入手机号',
                      keyboardType: _usePassword
                          ? TextInputType.text
                          : TextInputType.phone,
                      prefixIcon: const Icon(Icons.phone_iphone_rounded)),
                  const SizedBox(height: 20),
                  if (_usePassword)
                    _buildPasswordField()
                  else
                    _buildCodeField(),
                  const SizedBox(height: 40),
                  AppButton(
                      label: '立即登录', loading: _loadingLogin, onPressed: _login),
                  const SizedBox(height: 28),
                  _buildFooterActions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.asset('assets/app_icon.png',
          width: 80.0, height: 80.0, fit: BoxFit.cover),
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _switcherTab('验证码登录', !_usePassword),
          _switcherTab('密码登录', _usePassword),
        ],
      ),
    );
  }

  Widget _switcherTab(String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _usePassword = label == '密码登录'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05), blurRadius: 5)
                  ]
                : null,
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? AppColors.textPrimary : AppColors.textHint)),
        ),
      ),
    );
  }

  Widget _buildCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
                child: AppTextField(
                    label: '验证码',
                    controller: _codeController,
                    hint: '6位数字',
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.verified_outlined))),
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
                  height: 48),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('开发环境验证码：123456',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: '登录密码',
          controller: _passwordController,
          hint: '请输入您的密码',
          obscureText: _obscurePassword,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
              icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: AppColors.textHint),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ResetPasswordPage())),
            child: Text('忘记密码？',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterActions() {
    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => RegisterPage(onRegisterSuccess: () {
                Navigator.of(context).pop();
                widget.onLoginSuccess();
              }),
            )),
            child: RichText(
                text:
                    TextSpan(style: AppTextStyles.bodyMedium, children: const [
              TextSpan(text: '还没有账号？'),
              TextSpan(
                  text: '立即注册',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold))
            ])),
          ),
        ),
        const SizedBox(height: 24),
        Center(
            child: Text('登录即代表您同意《用户协议》与《隐私政策》',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint))),
      ],
    );
  }

  Widget _buildBackgroundDecoration() {
    return Positioned(
        top: -100,
        right: -50,
        child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.3),
                shape: BoxShape.circle)));
  }
}
