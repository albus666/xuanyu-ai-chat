import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/core/auth/saved_account_store.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/device/app_device_identity.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/core/utils/user_cache_utils.dart';

/// 登录方式
enum LoginMode { code, password }

class LoginController extends GetxController {
  LoginController();

  LoginMode mode = LoginMode.password;

  final phoneCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final smsCodeCtrl = TextEditingController();

  bool agreed = false;
  int countdown = 0;
  Timer? _timer;
  bool loggingIn = false;

  void _showTip(String message) {
    showGlobalAppToast(message);
  }

  String? _messageFromResponse(dynamic data) {
    if (data is Map && data.containsKey('message')) {
      return data['message']?.toString();
    }
    return null;
  }

  String _dioErrorMessage(DioException e, {String fallback = '请求失败'}) {
    final msg = _messageFromResponse(e.response?.data);
    if (msg != null && msg.isNotEmpty) return msg;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '无法连接服务器，请检查网络';
      default:
        return fallback;
    }
  }

  void switchMode(LoginMode m) {
    if (mode == m) return;
    mode = m;
    update(['login']);
  }

  void toggleAgree() {
    agreed = !agreed;
    update(['login']);
  }

  Future<void> sendSmsCode() async {
    if (countdown > 0) return;
    final mobile = phoneCtrl.text.trim();
    if (mobile.length != 11) {
      _showTip('请输入正确的手机号');
      return;
    }
    try {
      await apiClient.post('/api/auth/sendCode', data: {'mobile': mobile});
      _showTip('验证码已发送');
      countdown = 60;
      update(['login']);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        countdown -= 1;
        if (countdown <= 0) t.cancel();
        update(['login']);
      });
    } on DioException catch (e) {
      _showTip(_dioErrorMessage(e, fallback: '发送失败'));
    }
  }

  Future<void> onLogin() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!agreed) {
      _showTip('请先勾选《用户协议》及《隐私政策》');
      return;
    }
    final account = phoneCtrl.text.trim();
    if (mode == LoginMode.code && account.length != 11) {
      _showTip('请输入正确的手机号');
      return;
    }
    if (mode == LoginMode.password &&
        (account.length < 4 || account.length > 32)) {
      _showTip('请输入手机号');
      return;
    }
    if (mode == LoginMode.password && passwordCtrl.text.isEmpty) {
      _showTip('请输入密码');
      return;
    }
    if (mode == LoginMode.code && smsCodeCtrl.text.trim().isEmpty) {
      _showTip('请输入验证码');
      return;
    }
    loggingIn = true;
    update(['login']);
    try {
      final device = await appDevicePayload();
      final res = await apiClient.post(
        mode == LoginMode.password
            ? '/api/auth/loginByPassword'
            : '/api/auth/login',
        data: {
          'mobile': account,
          if (mode == LoginMode.password)
            'password': passwordCtrl.text
          else
            'code': smsCodeCtrl.text.trim(),
          ...device,
        },
      );
      final body = res.data as Map<String, dynamic>?;
      final code = body?['code'];
      if (code != null && code != 0) {
        _showTip(body?['message']?.toString() ?? '登录失败');
        return;
      }
      final d = body?['data'] as Map<String, dynamic>?;
      if (d == null || d['token'] == null) {
        _showTip(body?['message']?.toString() ?? '登录失败');
        return;
      }
      final token = d['token'].toString();
      final prefs = await SharedPreferences.getInstance();
      await clearUserDependentCache();
      await prefs.setString(AppConstants.keyToken, token);
      if (d['userId'] != null) {
        await prefs.setInt(
            AppConstants.keyUserId, (d['userId'] as num).toInt());
        await SavedAccountStore.rememberLogin(
          token: token,
          userId: (d['userId'] as num).toInt(),
          account: account,
          nickname: d['nickname']?.toString() ?? '',
          avatarUrl: d['avatarUrl']?.toString() ?? '',
          minorMode: d['minorMode'] == true || d['minorMode'] == 1,
        );
      }
      await prefs.setBool(AppConstants.keyNeedOnboarding, false);
      setupApiClientToken(token);
      Get.find<AuthState>().notifyAuthChanged();
    } on DioException catch (e) {
      _showTip(_dioErrorMessage(e, fallback: '登录失败'));
    } catch (_) {
      _showTip('登录失败，请稍后重试');
    } finally {
      loggingIn = false;
      update(['login']);
    }
  }

  void goRegister() => Get.toNamed(RouteNames.systemRegister);

  void forgetPassword() => Get.toNamed(RouteNames.systemForgetPassword);

  @override
  void onClose() {
    _timer?.cancel();
    phoneCtrl.dispose();
    passwordCtrl.dispose();
    smsCodeCtrl.dispose();
    super.onClose();
  }
}
