import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/life_atlas_models.dart';
import 'life_atlas_scene.dart';

class LifeAtlasVisuals {
  LifeAtlasVisuals._();

  static const background = Color(0xFF040706);
  static const surface = Color(0xFF0A0E0D);
  static const gold = Color(0xFFE2BA67);
  static const goldSoft = Color(0xFF8C7040);
  static const ivory = Color(0xFFF5EFE3);
  static const muted = Color(0xFFAAA79E);

  static String subtitleFor(LifeAtlasAchievement achievement) =>
      switch (achievement.eventKey) {
        'exam_staff_passed' => 'THE LONG WAIT ANSWERED',
        'business_first_start' => 'BEGIN FROM ZERO',
        'overseas_first' => 'THE WORLD OPENED',
        'drivers_license' => 'THE ROAD IS YOURS',
        _ => switch (achievement.domain) {
            LifeAtlasDomain.career => 'A NEW CHAPTER BEGINS',
            LifeAtlasDomain.wealth => 'BUILT WITH PATIENCE',
            LifeAtlasDomain.love => 'HEARTS IN MOTION',
            LifeAtlasDomain.family => 'WHERE HOME BEGINS',
            LifeAtlasDomain.growth => 'RISE, ONCE MORE',
            LifeAtlasDomain.health => 'RETURN TO RHYTHM',
            LifeAtlasDomain.social => 'FOUND IN COMPANY',
            LifeAtlasDomain.journey => 'BEYOND THE HORIZON',
          },
      };

  static String percentText(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

class LifeAtlasBackdrop extends StatelessWidget {
  const LifeAtlasBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101D1A), Color(0xFF050807), Color(0xFF020403)],
              stops: [0, 0.38, 1],
            ),
          ),
        ),
        Positioned(
          top: -100.h,
          right: -90.w,
          child: Container(
            width: 260.w,
            height: 260.w,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                  colors: [Color(0x5539877B), Colors.transparent]),
            ),
          ),
        ),
        Positioned(
          bottom: 70.h,
          left: -120.w,
          child: Container(
            width: 280.w,
            height: 280.w,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                  colors: [Color(0x334E5B91), Colors.transparent]),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class LifeAtlasAchievementCard extends StatelessWidget {
  const LifeAtlasAchievementCard({
    super.key,
    required this.achievement,
    this.onTap,
    this.selected = false,
    this.footerText,
    this.showPercent = true,
  });

  final LifeAtlasAchievement achievement;
  final VoidCallback? onTap;
  final bool selected;
  final String? footerText;
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    final palette = LifeAtlasPalette.forDomain(achievement.domain);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: LifeAtlasVisuals.surface,
            border: Border.all(
              color: selected
                  ? palette.accent
                  : palette.accent.withValues(alpha: 0.36),
              width: selected ? 1.4 : 0.8,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                    color: palette.glow.withValues(alpha: 0.2), blurRadius: 18),
            ],
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Row(
              children: [
                Expanded(
                  flex: 44,
                  child: LifeAtlasScene(
                    domain: achievement.domain,
                    sceneKey: achievement.sceneKey,
                    imageUrl: achievement.imageUrl,
                    sceneToken: achievement.sceneToken,
                    borderRadius: 0,
                  ),
                ),
                Expanded(
                  flex: 56,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 11.h, 11.w, 10.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                LifeAtlasVisuals.subtitleFor(achievement),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.accent.withValues(alpha: 0.82),
                                  fontSize: 7.2.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.75,
                                ),
                              ),
                            ),
                            SizedBox(width: 5.w),
                            _RarityBadge(
                                label: achievement.rarityLabel,
                                color: palette.accent),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          achievement.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LifeAtlasVisuals.ivory,
                            fontSize: 17.5.sp,
                            fontWeight: FontWeight.w900,
                            height: 1.13,
                          ),
                        ),
                        SizedBox(height: 7.h),
                        Text(
                          achievement.quote,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFC8C2B6),
                            fontSize: 9.4.sp,
                            height: 1.42,
                          ),
                        ),
                        const Spacer(),
                        if (footerText != null)
                          Text(
                            footerText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: palette.accent,
                                fontSize: 8.8.sp,
                                fontWeight: FontWeight.w800),
                          )
                        else if (showPercent &&
                            achievement.rarityPercent != null)
                          Row(
                            children: [
                              Icon(Icons.emoji_events_outlined,
                                  size: 12, color: palette.accent),
                              SizedBox(width: 4.w),
                              Expanded(
                                child: Text(
                                  '仅 ${LifeAtlasVisuals.percentText(achievement.rarityPercent!)}% 的用户点亮',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: LifeAtlasVisuals.muted,
                                      fontSize: 8.2.sp),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RarityBadge extends StatelessWidget {
  const _RarityBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.62), width: 0.7),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
            color: color, fontSize: 7.2.sp, fontWeight: FontWeight.w700),
      ),
    );
  }
}
