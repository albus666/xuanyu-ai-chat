import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/avatar_placeholder.dart';
import 'package:xuanyu/app/pages/voice/voice_match/controller.dart';

class VoiceMatchPage extends StatefulWidget {
  const VoiceMatchPage({super.key});

  @override
  State<VoiceMatchPage> createState() => _VoiceMatchPageState();
}

class _VoiceMatchPageState extends State<VoiceMatchPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  // ============ idle ============
  Widget _avatarCenter(VoiceMatchController c, {double size = 96}) {
    final label = c.myDisplayName.isNotEmpty ? c.myDisplayName : '我';
    if (c.myAvatarUrl.isNotEmpty) {
      return Container(
        width: size.r,
        height: size.r,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primaryLight, width: 2.5),
        ),
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: Image.network(
            c.myAvatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                AvatarPlaceholder(text: label, size: size - 6),
          ),
        ),
      );
    }
    return Container(
      width: size.r,
      height: size.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryLight, width: 2.5),
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: AvatarPlaceholder(text: label, size: size - 6),
      ),
    );
  }

  Widget _idleCenter(VoiceMatchController c) {
    return _avatarCenter(c);
  }

  Widget _buildAnimatedRings() {
    return AnimatedBuilder(
      animation: _ringController,
      builder: (_, __) {
        final t = _ringController.value;
        return SizedBox(
          width: 320.r,
          height: 320.r,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++) _pulseRing((t + i * 0.33) % 1),
            ],
          ),
        );
      },
    );
  }

  Widget _pulseRing(double progress) {
    final eased = Curves.easeOut.transform(progress);
    final base = 0.68 + eased * 0.34;
    final opacity = (1 - eased) * 0.42;
    return Transform.scale(
      scale: base,
      child: Container(
        width: 320.r,
        height: 320.r,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primary.withOpacity(opacity.clamp(0.08, 0.42)),
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _circlesArea({required Widget center, bool animate = false}) {
    return SizedBox(
      height: 320.h,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (animate) ...[
            _buildAnimatedRings(),
            ...List.generate(3, (index) {
              final size = 220.r + (index * 36.r);
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryLight.withOpacity(
                      0.35 - index * 0.08,
                    ),
                    width: 1,
                  ),
                ),
              );
            }),
          ] else
            Image.asset(
              ImageAssets.iconPipei,
              width: 320.r,
              height: 320.r,
              fit: BoxFit.contain,
            ),
          center,
        ],
      ),
    );
  }

  Widget _idleBody(VoiceMatchController c) {
    return Column(
      children: [
        SizedBox(height: 10.h),
        _circlesArea(
          center: Transform.translate(
            offset: Offset(0, 18.h),
            child: _idleCenter(c),
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          '一对一语音匹配',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          '根据命理同频与交流节奏，为您智能配对',
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
        ),
        SizedBox(height: 10.h),
        const Spacer(),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: Text(
            '完善出生资料后，系统会优先寻找成长经历相近、五行同频或能够彼此补位的人',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.sp,
              height: 1.5,
              color: AppColors.textHint,
            ),
          ),
        ),
        if (c.error?.isNotEmpty ?? false)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
            child: Text(
              c.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        SizedBox(height: 14.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: PrimaryButton(
            text: c.loading ? '正在加入…' : '开启语音匹配',
            enabled: !c.loading,
            onPressed: c.startMatch,
          ),
        ),
        SizedBox(height: 16.h),
      ],
    );
  }

  // ============ matching ============
  Widget _matchingCenter(VoiceMatchController c) => _avatarCenter(c);

  Widget _matchingBody(VoiceMatchController c) {
    return Column(
      children: [
        SizedBox(height: 10.h),
        _circlesArea(center: _matchingCenter(c), animate: true),
        SizedBox(height: 6.h),
        Text(
          '匹配中',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          (c.error?.isNotEmpty ?? false) ? c.error! : '正在等待同时开启匹配的用户…',
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
        ),
        SizedBox(height: 10.h),
        Text(
          '已等待 ${c.matchingDuration}',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: PrimaryButton(
            text: '退出匹配',
            enabled: true,
            onPressed: c.cancelMatch,
          ),
        ),
        SizedBox(height: 16.h),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VoiceMatchController>(
      init: VoiceMatchController(),
      id: 'voice_match',
      builder: (c) {
        Widget body;
        switch (c.state) {
          case VoiceMatchState.idle:
            body = _idleBody(c);
            break;
          case VoiceMatchState.matching:
            body = _matchingBody(c);
            break;
        }
        return WillPopScope(
          onWillPop: () async {
            if (c.state == VoiceMatchState.matching || c.loading) {
              await c.cancelMatch();
            }
            return true;
          },
          child: GradientScaffold(
            extendBodyBehindAppBar: false,
            appBar: AppBar(
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
                onPressed: () async {
                  if (c.state == VoiceMatchState.matching || c.loading) {
                    await c.cancelMatch();
                  }
                  NavUtils.goBack();
                },
              ),
              title: const Text('语音匹配'),
            ),
            body: SafeArea(top: false, child: body),
          ),
        );
      },
    );
  }
}
