import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/auth/saved_account_store.dart';
import '../../core/network/api_client.dart';
import '../../core/device/app_device_identity.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/user_cache_utils.dart';
import '../profile/legal_document_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

/// 注册页面：手机号 + 验证码 + 设置密码，注册成功后自动登录
class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.onRegisterSuccess,
  });

  final VoidCallback onRegisterSuccess;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreed = false;
  bool _loadingCode = false;
  bool _loadingRegister = false;
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
      await apiClient.post('/api/auth/sendCode', data: {'mobile': mobile});
      _showSnack('验证码已发送');
      _startCountdown();
    } on DioException catch (e) {
      final d = e.response?.data;
      final msg = (d is Map && d.containsKey('message'))
          ? d['message']?.toString()
          : null;
      _showSnack(msg ?? '发送失败: ${e.message}');
    } catch (e) {
      _showSnack('发送失败: $e');
    } finally {
      setState(() => _loadingCode = false);
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

  Future<void> _register() async {
    if (_loadingRegister) return;
    if (!_agreed) {
      _showSnack('请先阅读并勾选《用户协议》及《隐私政策》');
      return;
    }
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
      _showSnack('密码须为8至64位');
      return;
    }
    if (password != confirm) {
      _showSnack('两次输入的密码不一致');
      return;
    }

    setState(() => _loadingRegister = true);
    try {
      final device = await appDevicePayload();
      final res = await apiClient.post(
        '/api/auth/register',
        data: {
          'mobile': mobile,
          'code': code,
          'password': password,
          ...device,
          'legalConsent': {
            'accepted': _agreed,
            'acceptedAt': DateTime.now().toUtc().toIso8601String(),
            'userAgreementVersion': AppConstants.userAgreementVersion,
            'privacyPolicyVersion': AppConstants.privacyPolicyVersion,
            'scene': 'register',
          },
        },
      );
      final data = res.data as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>?;
      if (d == null) {
        _showSnack(data['message'] ?? '注册失败');
        return;
      }
      final token = d['token'] as String?;
      final userId = d['userId'];
      if (token == null) {
        _showSnack('注册成功，请重新登录');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await clearUserDependentCache();
      await prefs.setString(AppConstants.keyToken, token);
      await prefs.setBool(AppConstants.keyAgreementAccepted, true);
      await prefs.setString(AppConstants.keyAgreementVersion,
          '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}');
      await prefs.setString(AppConstants.keyAgreementAcceptedAt,
          DateTime.now().toUtc().toIso8601String());
      if (userId != null) {
        final id = userId is int ? userId : (userId as num).toInt();
        await prefs.setInt(AppConstants.keyUserId, id);
        await SavedAccountStore.rememberLogin(
          token: token,
          userId: id,
          account: mobile,
          nickname: d['nickname']?.toString() ?? '',
          avatarUrl: d['avatarUrl']?.toString() ?? '',
          minorMode: d['minorMode'] == true || d['minorMode'] == 1,
        );
      }
      await prefs.setBool(AppConstants.keyNeedOnboarding, false);
      setupApiClientToken(token);
      if (mounted) widget.onRegisterSuccess();
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = (body is Map && body.containsKey('message'))
          ? body['message']?.toString()
          : null;
      if (e.response?.statusCode == 409) {
        if (mounted) setState(() => _agreed = false);
        _showSnack('协议版本已更新，请更新 App 后重新阅读并同意');
      } else {
        _showSnack(msg ?? '注册失败，请稍后重试');
      }
    } catch (e) {
      _showSnack('注册失败: $e');
    } finally {
      if (mounted) setState(() => _loadingRegister = false);
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
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/app_icon.png',
                        width: 80, height: 80, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 28),
                  Text('创建账号', style: AppTextStyles.displayLarge),
                  const SizedBox(height: 8),
                  Text('设置密码后即可登录使用',
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 40),
                  AppTextField(
                    label: '手机号',
                    controller: _mobileController,
                    hint: '请输入中国大陆手机号',
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
                    label: '设置密码',
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
                    hint: '再次输入密码',
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
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: const ValueKey('legacy-register-agreement'),
                        value: _agreed,
                        onChanged: _loadingRegister
                            ? null
                            : (value) =>
                                setState(() => _agreed = value ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('我已阅读并同意'),
                              TextButton(
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const LegalDocumentPage(
                                            type: LegalDocumentType
                                                .userAgreement))),
                                child: const Text('《用户协议》'),
                              ),
                              const Text('及'),
                              TextButton(
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const LegalDocumentPage(
                                            type: LegalDocumentType
                                                .privacyPolicy))),
                                child: const Text('《隐私政策》'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: '注册',
                    onPressed: _register,
                    loading: _loadingRegister,
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: RichText(
                        text: TextSpan(
                          style: AppTextStyles.bodySmall,
                          children: const [
                            TextSpan(text: '已有账号？'),
                            TextSpan(
                              text: '去登录',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
