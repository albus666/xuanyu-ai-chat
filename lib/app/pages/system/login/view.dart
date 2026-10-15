import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/system/login/controller.dart';
import 'package:xuanyu/core/auth/saved_account_store.dart';
import 'package:xuanyu/features/profile/account_switcher_page.dart';

class ShellLoginPage extends StatelessWidget {
  const ShellLoginPage({super.key});

  Widget _buildLogo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.asset('assets/app_icon.png',
          width: 80.r, height: 80.r, fit: BoxFit.cover),
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '欢迎回来',
          style: TextStyle(
            fontSize: 26.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTab(LoginController c) {
    Widget item(String text, LoginMode m) {
      final selected = c.mode == m;
      return GestureDetector(
        onTap: () => c.switchMode(m),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 6.h),
            Container(
              width: 24.w,
              height: 3.h,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        item('验证码登录', LoginMode.code),
        SizedBox(width: 28.w),
        item('密码登录', LoginMode.password),
      ],
    );
  }

  Widget _buildInputBox({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      height: 48.h,
      padding: padding ?? EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFE2E2E2), width: 1),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildPhoneField(LoginController c) {
    return _buildInputBox(
      child: TextField(
        controller: c.phoneCtrl,
        keyboardType: c.mode == LoginMode.password
            ? TextInputType.text
            : TextInputType.phone,
        maxLength: c.mode == LoginMode.password ? 32 : 11,
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
  }

  Widget _buildPasswordField(LoginController c) {
    return _buildInputBox(
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
  }

  Widget _buildSmsField(LoginController c) {
    return _buildInputBox(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: c.smsCodeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
              decoration: InputDecoration(
                counterText: '',
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '验证码',
                hintStyle: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: c.sendSmsCode,
            child: Text(
              c.countdown > 0 ? '${c.countdown}s 后重发' : '发送验证码',
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
  }

  Widget _buildAgreement(LoginController c) {
    return GestureDetector(
      onTap: c.toggleAgree,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 16.r,
            height: 16.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: c.agreed ? AppColors.primary : AppColors.textHint,
                width: 1.2,
              ),
              color: c.agreed ? AppColors.primary : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: c.agreed
                ? Icon(Icons.check, size: 11.r, color: Colors.white)
                : null,
          ),
          SizedBox(width: 6.w),
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              children: const [
                TextSpan(text: '我已同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: TextStyle(color: AppColors.primary),
                ),
                TextSpan(text: '及'),
                TextSpan(
                  text: '《隐私政策》',
                  style: TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomLinks(LoginController c) {
    if (c.mode == LoginMode.password) {
      // 左：立即注册   右：忘记密码
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: c.goRegister,
            child: Text(
              '立即注册',
              style: TextStyle(fontSize: 13.sp, color: AppColors.primary),
            ),
          ),
          GestureDetector(
            onTap: c.forgetPassword,
            child: Text(
              '忘记密码',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    } else {
      // 居中：还没有账号？立即注册
      return Center(
        child: GestureDetector(
          onTap: c.goRegister,
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
              children: const [
                TextSpan(text: '还没有账号？ '),
                TextSpan(
                  text: '立即注册',
                  style: TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LoginController>(
      init: LoginController(),
      id: 'login',
      builder: (c) {
        return GradientScaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 30.h),
                  _buildLogo(),
                  SizedBox(height: 24.h),
                  _buildTitle(),
                  SizedBox(height: 36.h),
                  _buildTab(c),
                  SizedBox(height: 28.h),
                  _buildPhoneField(c),
                  SizedBox(height: 14.h),
                  if (c.mode == LoginMode.password)
                    _buildPasswordField(c)
                  else
                    _buildSmsField(c),
                  SizedBox(height: 18.h),
                  _buildAgreement(c),
                  SizedBox(height: 28.h),
                  PrimaryButton(
                    text: c.loggingIn ? '登录中…' : '登录',
                    onPressed: c.loggingIn ? null : c.onLogin,
                    enabled: !c.loggingIn,
                    radius: 10.r,
                  ),
                  SizedBox(height: 18.h),
                  _buildBottomLinks(c),
                  SizedBox(height: 10.h),
                  const _SavedAccountEntry(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SavedAccountEntry extends StatelessWidget {
  const _SavedAccountEntry();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedAccountSession>>(
      future: SavedAccountStore.load(),
      builder: (context, snapshot) {
        if ((snapshot.data?.isEmpty ?? true)) return const SizedBox.shrink();
        return Center(
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountSwitcherPage()),
            ),
            icon: const Icon(Icons.switch_account_outlined, size: 18),
            label: const Text('返回已保存账号'),
          ),
        );
      },
    );
  }
}
