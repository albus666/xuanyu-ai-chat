import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/core/auth/saved_account_store.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/device/app_device_identity.dart';
import 'package:xuanyu/core/utils/user_cache_utils.dart';

class RegisterController extends GetxController {
  RegisterController();

  final phoneCtrl = TextEditingController();
  final smsCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  int countdown = 0;
  Timer? _timer;
  bool submitting = false;
  bool agreed = false;

  void toggleAgreement() {
    agreed = !agreed;
    update(['register']);
  }

  Future<void> sendSms() async {
    if (countdown > 0) return;
    final mobile = phoneCtrl.text.trim();
    if (mobile.length != 11) {
      Get.snackbar('提示', '请输入正确的手机号', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await apiClient.post('/api/auth/sendCode', data: {'mobile': mobile});
      Get.snackbar('提示', '验证码已发送', snackPosition: SnackPosition.BOTTOM);
      countdown = 60;
      update(['register']);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        countdown -= 1;
        if (countdown <= 0) t.cancel();
        update(['register']);
      });
    } on DioException catch (e) {
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      Get.snackbar('提示', msg ?? '发送失败', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> onSubmit() async {
    if (submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!agreed) {
      Get.snackbar(
        '提示',
        '请先阅读并勾选《用户协议》及《隐私政策》',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final mobile = phoneCtrl.text.trim();
    if (mobile.length != 11) {
      Get.snackbar('提示', '请输入正确的手机号', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (smsCtrl.text.trim().isEmpty) {
      Get.snackbar('提示', '请输入验证码', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (passwordCtrl.text.length < 8 || passwordCtrl.text.length > 64) {
      Get.snackbar('提示', '密码须为8至64位', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (passwordCtrl.text != confirmCtrl.text) {
      Get.snackbar('提示', '两次密码不一致', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    submitting = true;
    update(['register']);
    try {
      final acceptedAt = DateTime.now().toUtc().toIso8601String();
      final device = await appDevicePayload();
      final res = await apiClient.post(
        '/api/auth/register',
        data: {
          'mobile': mobile,
          'code': smsCtrl.text.trim(),
          'password': passwordCtrl.text,
          ...device,
          'legalConsent': {
            'accepted': agreed,
            'userAgreementVersion': AppConstants.userAgreementVersion,
            'privacyPolicyVersion': AppConstants.privacyPolicyVersion,
            'acceptedAt': acceptedAt,
            'scene': 'register',
          },
        },
      );
      final data = res.data as Map<String, dynamic>?;
      final d = data?['data'] as Map<String, dynamic>?;
      final token = d?['token'] as String?;
      if (token == null) {
        Get.snackbar('提示', data?['message']?.toString() ?? '注册失败',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await clearUserDependentCache();
      await prefs.setString(AppConstants.keyToken, token);
      await prefs.setBool(AppConstants.keyAgreementAccepted, true);
      await prefs.setString(AppConstants.keyAgreementAcceptedAt, acceptedAt);
      await prefs.setString(
        AppConstants.keyAgreementVersion,
        '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}',
      );
      final userId = d?['userId'];
      if (userId != null) {
        await prefs.setInt(AppConstants.keyUserId, (userId as num).toInt());
        await SavedAccountStore.rememberLogin(
          token: token,
          userId: userId.toInt(),
          account: mobile,
          nickname: d?['nickname']?.toString() ?? '',
          avatarUrl: d?['avatarUrl']?.toString() ?? '',
          minorMode: d?['minorMode'] == true || d?['minorMode'] == 1,
        );
      }
      await prefs.setBool(AppConstants.keyNeedOnboarding, false);
      setupApiClientToken(token);
      Get.offAllNamed(RouteNames.root);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      if (e.response?.statusCode == 409) {
        agreed = false;
        update(['register']);
      }
      Get.snackbar(
          '提示',
          e.response?.statusCode == 409
              ? '协议版本已更新，请更新 App 后重新阅读并同意'
              : (msg ?? '注册失败'),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      submitting = false;
      update(['register']);
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    phoneCtrl.dispose();
    smsCtrl.dispose();
    passwordCtrl.dispose();
    confirmCtrl.dispose();
    super.onClose();
  }
}
