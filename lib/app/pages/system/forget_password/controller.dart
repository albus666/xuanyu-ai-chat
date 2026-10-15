import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/core/network/api_client.dart';

class ForgetPasswordController extends GetxController {
  ForgetPasswordController();

  final phoneCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final smsCtrl = TextEditingController();

  int countdown = 0;
  Timer? _timer;
  bool submitting = false;

  Future<void> sendSms() async {
    if (countdown > 0) return;
    final mobile = phoneCtrl.text.trim();
    if (mobile.length != 11) {
      Get.snackbar('提示', '请输入正确的手机号', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await apiClient.post(
        '/api/auth/sendCode',
        data: {'mobile': mobile, 'scene': 'resetPassword'},
      );
      Get.snackbar('提示', '验证码已发送', snackPosition: SnackPosition.BOTTOM);
      countdown = 60;
      update(['forget_password']);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        countdown -= 1;
        if (countdown <= 0) t.cancel();
        update(['forget_password']);
      });
    } on DioException catch (e) {
      final msg = (e.response?.data is Map && (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      Get.snackbar('提示', msg ?? '发送失败', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> onSubmit() async {
    final mobile = phoneCtrl.text.trim();
    if (mobile.length != 11) {
      Get.snackbar('提示', '请输入正确的手机号', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (smsCtrl.text.trim().isEmpty) {
      Get.snackbar('提示', '请输入验证码', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (passwordCtrl.text.length < 6) {
      Get.snackbar('提示', '密码至少 6 位', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    submitting = true;
    update(['forget_password']);
    try {
      await apiClient.post('/api/auth/resetPassword', data: {
        'mobile': mobile,
        'code': smsCtrl.text.trim(),
        'password': passwordCtrl.text,
      });
      Get.snackbar('提示', '密码已重置，请使用新密码登录', snackPosition: SnackPosition.BOTTOM);
      NavUtils.goBack(fallbackRoute: RouteNames.systemLogin);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map && (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      Get.snackbar('提示', msg ?? '重置失败', snackPosition: SnackPosition.BOTTOM);
    } finally {
      submitting = false;
      update(['forget_password']);
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    phoneCtrl.dispose();
    passwordCtrl.dispose();
    smsCtrl.dispose();
    super.onClose();
  }
}
