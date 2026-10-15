import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/home/master_consult/controller.dart';

class MasterConsultPage extends StatelessWidget {
  const MasterConsultPage({super.key});

  Widget _bigCard({
    required String title,
    required String subtitle,
    required String imageAsset,
    required List<Color> bgColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.r),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: bgColors,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 18.w),
        child: Row(
          children: [
            SizedBox(
              width: 78.r,
              height: 78.r,
              child: Image.asset(
                imageAsset,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MasterConsultController>(
      init: MasterConsultController(),
      id: 'master_consult',
      builder: (c) {
        return GradientScaffold(
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
              onPressed: () => NavUtils.goBack(),
            ),
            title: const Text('名师咨询'),
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择咨询方式',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  _bigCard(
                    title: 'AI名师',
                    subtitle: '智能答疑，随时在线',
                    imageAsset: ImageAssets.robot,
                    bgColors: const [Color(0xFFEFE6FA), Color(0xFFF5F0FB)],
                    onTap: c.onSelectAi,
                  ),
                  SizedBox(height: 14.h),
                  _bigCard(
                    title: '真人名师',
                    subtitle: '认证专家，一对一深度解答',
                    imageAsset: ImageAssets.destinyMatchBubbles,
                    bgColors: const [Color(0xFFD9F1F1), Color(0xFFE9F8F6)],
                    onTap: c.onSelectHuman,
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
