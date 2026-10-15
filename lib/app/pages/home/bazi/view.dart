import 'package:xuanyu/shared/widgets/bottom_footer_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/home/bazi/controller.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';

class BaziPage extends StatelessWidget {
  const BaziPage({
    super.key,
    this.startForOther = false,
    this.replaceInputWithResult = false,
  });

  final bool startForOther;
  final bool replaceInputWithResult;

  Widget _segment({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32.h,
        constraints: BoxConstraints(minWidth: 52.w),
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : const Color(0xFFF2F2F2),
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
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
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
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        border: divider
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 72.w,
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

  Widget _selectorRight(String text, VoidCallback onTap,
      {bool placeholder = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.sp,
                color: placeholder
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 2.w),
          Icon(Icons.chevron_right, size: 18.r, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<BaziController>(
      init: BaziController(startForOther: startForOther),
      id: 'bazi',
      builder: (c) {
        if (!c.startForOther && c.isSelf) {
          if (c.accountBirthLoaded) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => c.openSelfResult(context),
            );
          }
          return _buildAccountGate(context, c);
        }
        return GradientScaffold(
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('为他人排盘'),
            actions: [
              TextButton(
                onPressed: () => c.openArchive(context),
                child: Text(
                  '命理档案',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: BottomFooterScrollView(
              footer: const CulturalReferenceNotice(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0)),
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8.h),
                  Text(
                    '新建他人档案',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  SectionCard(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 2.h,
                    ),
                    child: Column(
                      children: [
                        _row(
                          label: '档案归属',
                          right: Align(
                            alignment: Alignment.centerRight,
                            child: _segment(
                              text: '他人档案',
                              selected: true,
                              onTap: () {},
                            ),
                          ),
                        ),
                        _row(
                          label: '姓名/称呼',
                          right: TextField(
                            controller: c.nameCtrl,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: '必填，用于区分档案',
                              hintStyle: TextStyle(
                                fontSize: 14.sp,
                                color: AppColors.textSecondary,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                        _row(
                          label: '与我关系',
                          right: Align(
                            alignment: Alignment.centerRight,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: c.relationship,
                                isDense: true,
                                borderRadius: BorderRadius.circular(12.r),
                                items: ArchiveRelationship.selectableForOthers
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          ArchiveRelationship.label(value),
                                          style: TextStyle(fontSize: 14.sp),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    c.selectRelationship(value);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        _row(
                          label: '性别',
                          right: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _segment(
                                text: '男',
                                selected: c.gender == BaziGender.male,
                                onTap: () => c.selectGender(BaziGender.male),
                              ),
                              SizedBox(width: 10.w),
                              _segment(
                                text: '女',
                                selected: c.gender == BaziGender.female,
                                onTap: () => c.selectGender(BaziGender.female),
                              ),
                            ],
                          ),
                        ),
                        _row(
                          label: '历法',
                          right: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _segment(
                                text: '公历',
                                selected: c.calendar == BaziCalendar.gongli,
                                onTap: () =>
                                    c.selectCalendar(BaziCalendar.gongli),
                              ),
                              SizedBox(width: 8.w),
                              _segment(
                                text: '农历',
                                selected: c.calendar == BaziCalendar.nongli,
                                onTap: () =>
                                    c.selectCalendar(BaziCalendar.nongli),
                              ),
                              SizedBox(width: 8.w),
                              _segment(
                                text: '四柱',
                                selected: c.calendar == BaziCalendar.sizhu,
                                onTap: () =>
                                    c.selectCalendar(BaziCalendar.sizhu),
                              ),
                            ],
                          ),
                        ),
                        _row(
                          label: '出生日期时辰',
                          right: _selectorRight(
                            c.dateText,
                            () => c.pickBirthDate(context),
                          ),
                        ),
                        _row(
                          label: '出生地',
                          divider: false,
                          right: _selectorRight(
                            c.birthPlaceText,
                            () => c.pickBirthPlace(context),
                            placeholder: c.birthPlace == null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    c.trueSolarTimeText,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    c.coordText,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                    child: PrimaryButton(
                      text: '开始排盘',
                      height: 48.h,
                      onPressed: () => c.onSubmit(
                        context,
                        replaceCurrent: replaceInputWithResult,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountGate(BuildContext context, BaziController c) {
    return GradientScaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('八字排盘'),
        actions: [
          TextButton(
            onPressed: () => c.openArchive(context),
            child: const Text('命理档案'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: c.accountLoadFinished
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64.r,
                      height: 64.r,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_search_rounded,
                        color: AppColors.primary,
                        size: 32.r,
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Text(
                      '完善本人出生资料',
                      style: TextStyle(
                        fontSize: 19.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '只需填写一次，八字、斗数和其他本人功能都会自动使用',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 22.h),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => c.completeSelfProfileAndOpen(context),
                        child: const Text('完善资料后排盘'),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextButton(
                      onPressed: () => c.selectOwner(false),
                      child: const Text('为他人排盘'),
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 14),
                    Text('正在读取本人资料…'),
                  ],
                ),
        ),
      ),
    );
  }
}
