import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/system/register/controller.dart';
import 'package:xuanyu/features/profile/legal_document_page.dart';

class ShellRegisterPage extends StatelessWidget {
  const ShellRegisterPage({super.key});

  Widget _logo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: Image.asset('assets/app_icon.png',
          width: 80.r, height: 80.r, fit: BoxFit.cover),
    );
  }

  Widget _title() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '创建账号',
          style: TextStyle(
            fontSize: 26.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          '设置密码后即可登录使用',
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

  Widget _phone(RegisterController c) => _box(
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

  Widget _sms(RegisterController c) => _box(
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
                  hintText: '验证码',
                  hintStyle:
                      TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                ),
              ),
            ),
            GestureDetector(
              onTap: c.sendSms,
              child: Text(
                c.countdown > 0 ? '${c.countdown}s 后重发' : '发送验证码',
                style: TextStyle(
                  fontSize: 14.sp,
                  color:
                      c.countdown > 0 ? AppColors.textHint : AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _password(RegisterController c) => _box(
        child: TextField(
          controller: c.passwordCtrl,
          obscureText: true,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            hintText: '密码',
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
          ),
        ),
      );

  Widget _confirm(RegisterController c) => _box(
        child: TextField(
          controller: c.confirmCtrl,
          obscureText: true,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            hintText: '确认密码',
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
          ),
        ),
      );

  void _openLegal(BuildContext context, LegalDocumentType type) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => LegalDocumentPage(type: type)),
    );
  }

  Widget _agreement(BuildContext context, RegisterController c) {
    final linkStyle = TextStyle(
      fontSize: 12.sp,
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: const ValueKey<String>('register-agreement-checkbox'),
          onTap: c.toggleAgreement,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 2.h, 8.w, 10.h),
            child: Container(
              width: 18.r,
              height: 18.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.agreed ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: c.agreed ? AppColors.primary : AppColors.textHint,
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: c.agreed
                  ? Icon(Icons.check, size: 12.r, color: Colors.white)
                  : null,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: c.toggleAgreement,
                child: Text(
                  '我已阅读并同意',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                    height: 1.7,
                  ),
                ),
              ),
              GestureDetector(
                key: const ValueKey<String>('register-user-agreement-link'),
                onTap: () => _openLegal(
                  context,
                  LegalDocumentType.userAgreement,
                ),
                child: Text('《用户协议》', style: linkStyle),
              ),
              Text(
                '及',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                  height: 1.7,
                ),
              ),
              GestureDetector(
                key: const ValueKey<String>('register-privacy-policy-link'),
                onTap: () => _openLegal(
                  context,
                  LegalDocumentType.privacyPolicy,
                ),
                child: Text('《隐私政策》', style: linkStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<RegisterController>(
      init: RegisterController(),
      id: 'register',
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
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8.h),
                  _logo(),
                  SizedBox(height: 24.h),
                  _title(),
                  SizedBox(height: 32.h),
                  _phone(c),
                  SizedBox(height: 14.h),
                  _sms(c),
                  SizedBox(height: 14.h),
                  _password(c),
                  SizedBox(height: 14.h),
                  _confirm(c),
                  SizedBox(height: 18.h),
                  _agreement(context, c),
                  SizedBox(height: 22.h),
                  PrimaryButton(
                    text: c.submitting ? '注册中…' : '注册',
                    onPressed: c.submitting ? null : c.onSubmit,
                    enabled: !c.submitting,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
