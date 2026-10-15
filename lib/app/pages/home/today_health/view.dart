import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/home/today_health/controller.dart';
import 'package:xuanyu/core/widgets/app_gpt_markdown.dart';
import 'package:xuanyu/core/widgets/ai_generated_badge.dart';
import 'package:xuanyu/features/fortune/weekly_health_check_page.dart';

class _WellnessBackdropPainter extends CustomPainter {
  const _WellnessBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.08),
      32,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    final mountain = Path()
      ..moveTo(0, size.height * 0.14)
      ..quadraticBezierTo(
        size.width * 0.24,
        size.height * 0.08,
        size.width * 0.48,
        size.height * 0.17,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.22,
        size.width,
        size.height * 0.13,
      )
      ..lineTo(size.width, size.height * 0.28)
      ..lineTo(0, size.height * 0.28)
      ..close();
    canvas.drawPath(
      mountain,
      Paint()..color = const Color(0xFF43CDD6).withValues(alpha: 0.09),
    );

    final ripplePaint = Paint()
      ..color = const Color(0xFF47CAD6).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = 0; index < 6; index++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.56, size.height * 0.23 + index * 20),
          width: size.width * (0.42 + index * 0.08),
          height: 13,
        ),
        ripplePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TodayHealthPage extends StatelessWidget {
  const TodayHealthPage({super.key});

  static const Color _jade = Color(0xFF0FAFAE);
  static const Color _jadeDark = Color(0xFF126C70);
  static const Color _cyan = Color(0xFF37CFE0);

  static String _stripCodeFence(String raw) {
    if (raw.isEmpty) return raw;
    String s = raw.trim();
    if (s.startsWith('```')) {
      final firstLineEnd = s.indexOf('\n');
      if (firstLineEnd != -1) {
        s = s.substring(firstLineEnd + 1);
      } else {
        s = s.replaceFirst(RegExp(r'^```\w*\s*'), '');
      }
    }
    if (s.trimRight().endsWith('```')) {
      s = s.trimRight();
      final lastFence = s.lastIndexOf('```');
      if (lastFence != -1) s = s.substring(0, lastFence).trimRight();
    }
    return s.trim();
  }

  Widget _sourceTag(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: const Color(0xFFE0FAF8),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: const Color(0xFF8CE5DF)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _jadeDark,
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _focusBlock({
    required String title,
    required String source,
    required HealthFocus focus,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 13.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.r,
            height: 38.r,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7FE9E0), Color(0xFF55C8EC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.spa_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    _sourceTag(source),
                  ],
                ),
                SizedBox(height: 6.h),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.sp,
                      height: 1.55,
                    ),
                    children: [
                      const TextSpan(text: '重点关注：'),
                      TextSpan(
                        text: focus.bodyArea,
                        style: const TextStyle(
                          color: _jadeDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: '\n'),
                      TextSpan(text: focus.summary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthFocusCard(TodayHealthController c) {
    final ageText = c.decadalFocus.ageRange;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: _cyan.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '身体养护关注',
            style: TextStyle(
              color: _jadeDark,
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4.h),
          if (!c.healthFocusAvailable)
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(vertical: 12.h),
              padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(13.r),
                border: Border.all(color: const Color(0xFFF1D59B)),
              ),
              child: Text(
                c.healthFocusMessage.isEmpty
                    ? '请先在个人信息中完善出生日期、准确时辰和性别。'
                    : c.healthFocusMessage,
                style: TextStyle(
                  color: const Color(0xFF8A6426),
                  fontSize: 12.sp,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else ...[
            _focusBlock(
              title: '先天关注',
              source: '原局疾厄宫',
              focus: c.natalFocus,
            ),
            Divider(height: 1, color: _jade.withValues(alpha: 0.12)),
            _focusBlock(
              title: '阶段关注',
              source: ageText == null ? '大限疾厄宫' : '大限 $ageText岁',
              focus: c.decadalFocus,
            ),
          ],
        ],
      ),
    );
  }

  Widget _adviceCard(HealthSection section) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 20.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
        boxShadow: [
          BoxShadow(
            color: _cyan.withValues(alpha: 0.09),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4.w,
                height: 20.h,
                decoration: BoxDecoration(
                  color: _jade,
                  borderRadius: BorderRadius.circular(99.r),
                ),
              ),
              SizedBox(width: 9.w),
              Text(
                '今日饮食与作息',
                style: TextStyle(
                  color: _jadeDark,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          AppGptMarkdown(
            data: _stripCodeFence(section.content),
            enableBoldHighlight: false,
            enableEqualsHighlight: false,
            bodyStyle: TextStyle(
              fontSize: 13.sp,
              color: AppColors.textPrimary,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _directionCard(TodayHealthController c) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 17.w, vertical: 15.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE0FAF8), Color(0xFFEEF5FF)],
        ),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.r,
            height: 38.r,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: _jadeDark,
              size: 20,
            ),
          ),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日饮食方向 · ${c.recommendationDirection}',
                  style: TextStyle(
                    color: _jadeDark,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5.h),
                Text(
                  c.recommendationPrinciples.join(' · '),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyCheckCard(TodayHealthController c) {
    return Material(
      color: const Color(0xFF172A2C),
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: () async {
          final changed =
              await Get.to<bool>(() => const WeeklyHealthCheckPage());
          if (changed == true) await c.refreshHealth();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 17.w, vertical: 16.h),
          child: Row(
            children: [
              Container(
                width: 39.r,
                height: 39.r,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(13.r),
                ),
                child: const Icon(Icons.refresh_rounded,
                    color: Color(0xFF72DED7), size: 21),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('用 30 秒更新本周状态',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800)),
                    if (c.weeklyCheckMessage.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(c.weeklyCheckMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.sp,
                              height: 1.45)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<TodayHealthController>(
      init: TodayHealthController(),
      id: 'health',
      builder: (c) {
        final advice = c.sections.isEmpty
            ? const HealthSection('养生建议', '暂无内容。')
            : c.sections.first;
        return GradientScaffold(
          extendBodyBehindAppBar: false,
          useGradient: true,
          gradientColors: const [
            Color(0xFF8FEAF6),
            Color(0xFFDFF9F8),
            Color(0xFFF8FCFF),
          ],
          gradientStops: const [0.0, 0.24, 1.0],
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18.r,
                color: AppColors.textPrimary,
              ),
              onPressed: () => NavUtils.goBack(),
            ),
            title: Text(
              '今日养生',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _WellnessBackdropPainter()),
                ),
              ),
              SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 28.h),
                  child: Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: AiGeneratedBadge(compact: true),
                      ),
                      SizedBox(height: 10.h),
                      _healthFocusCard(c),
                      SizedBox(height: 14.h),
                      if (c.weeklyCheckDue) ...[
                        _weeklyCheckCard(c),
                        SizedBox(height: 14.h),
                      ],
                      _directionCard(c),
                      SizedBox(height: 14.h),
                      _adviceCard(advice),
                      SizedBox(height: 14.h),
                      Text(
                        '传统养护与健康科普参考 · 非医疗诊断',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 10.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
