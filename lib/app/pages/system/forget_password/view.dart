import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/system/forget_password/controller.dart';

class ShellForgetPasswordPage extends StatelessWidget {
  const ShellForgetPasswordPage({super.key});

  Widget _title() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '忘记密码',
          style: TextStyle(
            fontSize: 26.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          '请输入手机号和验证码找回密码',
          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _box({required Widget child}) {
    return Container(
      height: 48.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFE2E2E2), width: 1),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _phone(ForgetPasswordController c) => _box(
    child: TextField(
      controller: c.phoneCtrl,
      keyboardType: TextInputType.phone,
      maxLength: 11,
      style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
      decoration: InputDecoration(
        counterText: '',
        border: InputBorder.none,
        isCollapsed: true,
        hintText: '手机号',
        hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
      ),
    ),
  );

  Widget _password(ForgetPasswordController c) => _box(
    child: TextField(
      controller: c.passwordCtrl,
      obscureText: true,
      style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
      decoration: InputDecoration(
        border: InputBorder.none,
        isCollapsed: true,
        hintText: '请输入新密码',
        hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
      ),
    ),
  );

  Widget _sms(ForgetPasswordController c) => _box(
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: c.smsCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
            decoration: InputDecoration(
              counterText: '',
              border: InputBorder.none,
              isCollapsed: true,
              hintText: '请输入验证码',
              hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            ),
          ),
        ),
        GestureDetector(
          onTap: c.sendSms,
          child: Text(
            c.countdown > 0 ? '${c.countdown}s 后重发' : '获取验证码',
            style: TextStyle(
              fontSize: 14.sp,
              color: c.countdown > 0 ? AppColors.textHint : AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ForgetPasswordController>(
      init: ForgetPasswordController(),
      id: 'forget_password',
      builder: (c) {
        return GradientScaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
              onPressed: () =>
                  NavUtils.goBack(fallbackRoute: RouteNames.systemLogin),
            ),
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _title(),
                        SizedBox(height: 36.h),
                        _phone(c),
                        SizedBox(height: 14.h),
                        _password(c),
                        SizedBox(height: 14.h),
                        _sms(c),
                        SizedBox(height: 36.h),
                        PrimaryButton(text: '确认', onPressed: c.onSubmit),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
