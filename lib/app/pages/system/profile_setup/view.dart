import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/system/profile_setup/controller.dart';

class ShellProfileSetupPage extends StatelessWidget {
  const ShellProfileSetupPage({super.key});

  Widget _sectionTitle(String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: 4.h),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _genderBtn({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 96.w,
        height: 42.h,
        decoration: BoxDecoration(
          color: selected ? Colors.transparent : const Color(0xFFF2F2F2),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(8.r),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14.sp,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required Widget right,
    bool divider = true,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      decoration: BoxDecoration(
        border: divider
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _selector(BuildContext context, String text, VoidCallback onTap) {
    final placeholder = text == '去选择';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 14.sp,
              color:
                  placeholder ? AppColors.textSecondary : AppColors.textPrimary,
            ),
          ),
          SizedBox(width: 4.w),
          Icon(Icons.chevron_right, size: 18.r, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ProfileSetupController>(
      init: ProfileSetupController(),
      id: 'profile',
      builder: (c) {
        return GradientScaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
              onPressed: () =>
                  NavUtils.goBack(fallbackRoute: RouteNames.systemLogin),
            ),
            title: const Text('完善个人信息'),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 8.h),
                        _sectionTitle('设置昵称', '让大家认识你'),
                        SizedBox(height: 12.h),
                        SectionCard(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 4.h,
                          ),
                          child: TextField(
                            controller: c.nicknameCtrl,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: '请输入昵称',
                              hintStyle: TextStyle(
                                fontSize: 14.sp,
                                color: AppColors.textHint,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 14.h,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 22.h),
                        _sectionTitle(
                          '出生日期',
                          '支持公历（阳历）、农历或四柱反推，用于排盘与个性化内容',
                        ),
                        SizedBox(height: 12.h),
                        SectionCard(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 4.h,
                          ),
                          child: Column(
                            children: [
                              _row(
                                label: '性别',
                                right: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _genderBtn(
                                      text: '男',
                                      selected: c.gender == Gender.male,
                                      onTap: () => c.selectGender(Gender.male),
                                    ),
                                    SizedBox(width: 16.w),
                                    _genderBtn(
                                      text: '女',
                                      selected: c.gender == Gender.female,
                                      onTap: () =>
                                          c.selectGender(Gender.female),
                                    ),
                                  ],
                                ),
                              ),
                              _row(
                                label: '出生日期',
                                right: _selector(
                                  context,
                                  c.dateText,
                                  () => c.pickBirthDateTime(context),
                                ),
                              ),
                              _row(
                                label: '出生时间',
                                divider: false,
                                right: _selector(
                                  context,
                                  c.timeText,
                                  () => c.pickBirthDateTime(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 22.h),
                        _sectionTitle('个人简介', '简单介绍一下自己'),
                        SizedBox(height: 12.h),
                        SectionCard(
                          padding: EdgeInsets.all(14.r),
                          child: SizedBox(
                            height: 206.h,
                            child: TextField(
                              controller: c.introCtrl,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: AppColors.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: '简单介绍一下自己吧...',
                                hintStyle: TextStyle(
                                  fontSize: 14.sp,
                                  color: AppColors.textHint,
                                ),
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  child: PrimaryButton(
                    text: '完成',
                    onPressed: c.onComplete,
                    radius: 10.r,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
