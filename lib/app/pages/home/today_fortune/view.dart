import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/index.dart';
import 'package:xuanyu/app/pages/home/today_fortune/controller.dart';
import 'package:xuanyu/core/widgets/ai_generated_badge.dart';

class TodayFortunePage extends StatelessWidget {
  const TodayFortunePage({super.key});

  Widget _buildDateTabs(TodayFortuneController c) {
    return Container(
      height: 56.h,
      alignment: Alignment.center,
      child: SizedBox(
        width: double.infinity,
        child: Row(
          children: List.generate(c.dates.length, (i) {
            final selected = i == c.selectedDate;
            return Expanded(
              child: GestureDetector(
                onTap: () => c.selectDate(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      c.dates[i],
                      style: TextStyle(
                        fontSize: (c.dates.length > 3 ? 11.5 : 14).sp,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      c.dateTextAt(i),
                      style: TextStyle(
                        fontSize: (c.dates.length > 3 ? 8.5 : 9.5).sp,
                        color: selected
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Container(
                      width: (c.dates.length > 3 ? 18 : 22).w,
                      height: 3.h,
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildScoreCard(TodayFortuneController c) {
    final score = c.energyScore.overall;
    return SectionCard(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
            decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12.r)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FortuneScoreRing(
                        score: score,
                        size: 82,
                        bottomLabel: '趋势分',
                        large: true),
                    SizedBox(width: 14.w),
                    Expanded(
                        child: FortuneBars(
                            maxBarHeight: 60,
                            items: c.energyScore.toBarItems())),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(FortuneSection s) {
    final blocks = s.content
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();
    return SectionCard(
      padding: EdgeInsets.fromLTRB(16.w, 15.h, 16.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.title != '今日分析') ...[
            Row(
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(width: 4.w),
                Container(
                  width: 4.r,
                  height: 4.r,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryLight,
                  ),
                ),
              ],
            ),
            SizedBox(height: 13.h),
          ],
          ...blocks.indexed.expand((entry) {
            final lines = entry.$2.split('\n');
            final hasHeading = lines.length > 1;
            final heading = hasHeading ? lines.first.trim() : null;
            final body = (hasHeading ? lines.skip(1) : lines).join('\n').trim();
            return [
              if (entry.$1 > 0)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Divider(
                    height: 1,
                    color: AppColors.divider.withValues(alpha: 0.55),
                  ),
                ),
              if (heading != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 6.h),
                  child: Row(children: [
                    Container(
                      width: 3.w,
                      height: 14.h,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                    SizedBox(width: 7.w),
                    Text(heading,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        )),
                  ]),
                ),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textPrimary,
                  height: 1.78,
                ),
              ),
            ];
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<TodayFortuneController>(
      init: TodayFortuneController(),
      id: 'fortune',
      builder: (c) {
        return GradientScaffold(
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
              onPressed: () => NavUtils.goBack(),
            ),
            title: const Text('今日能量'),
          ),
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDateTabs(c),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: AiGeneratedBadge(compact: true),
                            ),
                            SizedBox(height: 8.h),
                            _buildScoreCard(c),
                            SizedBox(height: 12.h),
                            ...c.sections.expand(
                              (s) => [_buildSection(s), SizedBox(height: 12.h)],
                            ),
                          ],
                        ),
                        const CulturalReferenceNotice(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        ),
                      ],
                    ),
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
