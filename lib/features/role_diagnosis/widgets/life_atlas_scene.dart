import 'package:flutter/material.dart';

import '../../../core/services/scene_asset_service.dart';
import '../models/life_atlas_models.dart';

class LifeAtlasPalette {
  const LifeAtlasPalette({
    required this.background,
    required this.glow,
    required this.accent,
  });

  final Color background;
  final Color glow;
  final Color accent;

  static LifeAtlasPalette forDomain(LifeAtlasDomain domain) => switch (domain) {
    LifeAtlasDomain.career => const LifeAtlasPalette(
      background: Color(0xFF120D08),
      glow: Color(0xFFE19A38),
      accent: Color(0xFFFFD37A),
    ),
    LifeAtlasDomain.wealth => const LifeAtlasPalette(
      background: Color(0xFF0C110B),
      glow: Color(0xFFB7913F),
      accent: Color(0xFFE7CA78),
    ),
    LifeAtlasDomain.love => const LifeAtlasPalette(
      background: Color(0xFF16090D),
      glow: Color(0xFFB85267),
      accent: Color(0xFFF0A6A9),
    ),
    LifeAtlasDomain.family => const LifeAtlasPalette(
      background: Color(0xFF10100B),
      glow: Color(0xFFB16A32),
      accent: Color(0xFFF0C07A),
    ),
    LifeAtlasDomain.growth => const LifeAtlasPalette(
      background: Color(0xFF070D14),
      glow: Color(0xFF315C91),
      accent: Color(0xFFE0B758),
    ),
    LifeAtlasDomain.health => const LifeAtlasPalette(
      background: Color(0xFF07110E),
      glow: Color(0xFF4F9277),
      accent: Color(0xFFDDE8B7),
    ),
    LifeAtlasDomain.social => const LifeAtlasPalette(
      background: Color(0xFF091014),
      glow: Color(0xFF3F8391),
      accent: Color(0xFFA8E2DC),
    ),
    LifeAtlasDomain.journey => const LifeAtlasPalette(
      background: Color(0xFF070C16),
      glow: Color(0xFF315EA7),
      accent: Color(0xFF7ED6D1),
    ),
  };
}

class LifeAtlasScene extends StatefulWidget {
  const LifeAtlasScene({
    super.key,
    required this.domain,
    this.sceneKey,
    this.imageUrl,
    this.sceneToken,
    this.borderRadius = 18,
    this.darkenRightEdge = true,
  });

  final LifeAtlasDomain domain;
  final String? sceneKey;
  final String? imageUrl;
  final String? sceneToken;
  final double borderRadius;
  final bool darkenRightEdge;

  static String assetFor(LifeAtlasDomain domain, String? sceneKey) {
    final eventAsset = switch (sceneKey) {
      'exam_staff_passed' => 'scene_exam.webp',
      'business_first_start' => 'scene_startup.webp',
      'overseas_first' => 'scene_overseas.webp',
      'drivers_license' => 'scene_driving.webp',
      _ => null,
    };
    if (eventAsset != null) return 'assets/life_atlas_v2/$eventAsset';
    final domainAsset = switch (domain) {
      LifeAtlasDomain.career => 'scene_startup.webp',
      LifeAtlasDomain.wealth => 'scene_wealth.webp',
      LifeAtlasDomain.love => 'scene_love.webp',
      LifeAtlasDomain.family => 'scene_family.webp',
      LifeAtlasDomain.growth => 'scene_growth.webp',
      LifeAtlasDomain.health => 'scene_health.webp',
      LifeAtlasDomain.social => 'scene_social.webp',
      LifeAtlasDomain.journey => 'scene_overseas.webp',
    };
    return 'assets/life_atlas_v2/$domainAsset';
  }

  @override
  State<LifeAtlasScene> createState() => _LifeAtlasSceneState();
}

class _LifeAtlasSceneState extends State<LifeAtlasScene> {
  String _remoteUrl = '';
  bool _refreshAttempted = false;

  @override
  void initState() {
    super.initState();
    _remoteUrl = widget.imageUrl?.trim() ?? '';
    _resolve();
  }

  @override
  void didUpdateWidget(covariant LifeAtlasScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.sceneToken != widget.sceneToken) {
      _remoteUrl = widget.imageUrl?.trim() ?? '';
      _refreshAttempted = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final token = widget.sceneToken?.trim() ?? '';
    if (_remoteUrl.isNotEmpty && token.isEmpty) return;
    final value = await SceneAssetService.resolve(
      sceneToken: token,
      initialUrl: _remoteUrl,
    );
    if (!mounted || value == null || value.isEmpty || value == _remoteUrl) {
      return;
    }
    setState(() => _remoteUrl = value);
  }

  void _refreshExpiredUrl() {
    if (_refreshAttempted) return;
    final token = widget.sceneToken?.trim() ?? '';
    if (token.isEmpty) return;
    _refreshAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final value = await SceneAssetService.refresh(token);
      if (!mounted || value == null || value.isEmpty) return;
      setState(() => _remoteUrl = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifeAtlasPalette.forDomain(widget.domain);
    final fallbackAsset = LifeAtlasScene.assetFor(
      widget.domain,
      widget.sceneKey,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: palette.background),
          if (_remoteUrl.isNotEmpty)
            Image.network(
              _remoteUrl,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) {
                _refreshExpiredUrl();
                return Image.asset(fallbackAsset, fit: BoxFit.cover);
              },
            )
          else
            Image.asset(
              fallbackAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [palette.background, palette.glow],
                  ),
                ),
                child: Icon(
                  widget.domain.icon,
                  color: palette.accent,
                  size: 42,
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x10000000), Color(0x66000000)],
                stops: [0.35, 1],
              ),
            ),
          ),
          if (widget.darkenRightEdge)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Color(0xC9000000)],
                  stops: [0.55, 1],
                ),
              ),
            ),
          const Positioned(right: 7, bottom: 6, child: _AiSceneBadge()),
        ],
      ),
    );
  }
}

class _AiSceneBadge extends StatelessWidget {
  const _AiSceneBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB8000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          'AI生成内容',
          style: TextStyle(
            color: Color(0xFFDAD4C8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
