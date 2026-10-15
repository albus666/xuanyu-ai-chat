import 'package:flutter/material.dart';

import '../../../shared/widgets/cultural_reference_notice.dart';
import '../models/life_atlas_models.dart';
import 'life_atlas_scene.dart';
import 'life_atlas_visuals.dart';

class RoleDiagnosisShareCard extends StatelessWidget {
  const RoleDiagnosisShareCard({
    super.key,
    required this.achievement,
  });

  final LifeAtlasAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final palette = LifeAtlasPalette.forDomain(achievement.domain);
    return Container(
      width: 720,
      height: 445,
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF020302),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: const Color(0xFF8C7040), width: 1.4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.background, const Color(0xFF030504)],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              Expanded(
                flex: 43,
                child: LifeAtlasScene(
                  domain: achievement.domain,
                  sceneKey: achievement.sceneKey,
                  imageUrl: achievement.imageUrl,
                  sceneToken: achievement.sceneToken,
                  borderRadius: 0,
                ),
              ),
              Expanded(
                flex: 57,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(31, 28, 28, 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '玄遇人生图鉴',
                            style: TextStyle(
                              color: Color(0xFFD8B363),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: palette.accent.withValues(alpha: 0.7),
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              achievement.rarityLabel,
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        achievement.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF7F2E8),
                          fontSize: 39,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        LifeAtlasVisuals.subtitleFor(achievement),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.accent.withValues(alpha: 0.86),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.7,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        achievement.quote,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD4CEC1),
                          fontSize: 19,
                          height: 1.52,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (achievement.rarityPercent != null) ...[
                        Divider(
                          color: const Color(0xFFD8B363).withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              size: 21,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              '仅 ${LifeAtlasVisuals.percentText(achievement.rarityPercent!)}% 的图鉴用户点亮',
                              style: const TextStyle(
                                color: Color(0xFFBBB5A8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        CulturalReferenceNotice.text,
                        softWrap: true,
                        style: TextStyle(
                          color: Color(0xFFBBB5A8),
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
