import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/shared/widgets/account_session_guard.dart';

import 'models/life_atlas_models.dart';
import 'role_diagnosis_loading_page.dart';
import 'services/life_atlas_api_service.dart';
import 'widgets/life_atlas_scene.dart';
import 'widgets/life_atlas_visuals.dart';

class LifeAtlasExperiencePage extends StatefulWidget {
  const LifeAtlasExperiencePage({
    super.key,
    required this.birth,
    required this.hour,
    required this.isMale,
    required this.eventText,
  });

  final DateTime birth;
  final int hour;
  final bool isMale;
  final String eventText;

  @override
  State<LifeAtlasExperiencePage> createState() =>
      _LifeAtlasExperiencePageState();
}

class _LifeAtlasExperiencePageState extends State<LifeAtlasExperiencePage>
    with AccountSessionGuard<LifeAtlasExperiencePage> {
  LifeAtlasEventAnalysis? _analysis;
  String? _error;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    if (!accountSession.current) return;
    setState(() => _error = null);
    try {
      final result = await LifeAtlasApiService.analyzeEvent(widget.eventText,
          session: accountSession);
      if (mounted && accountSession.current) setState(() => _analysis = result);
    } catch (_) {
      if (mounted) setState(() => _error = '暂时没有理解这件事，请换一种说法');
    }
  }

  void _select(LifeAtlasMeaningOption meaning) {
    final analysis = _analysis;
    if (analysis == null || !accountSession.current) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RoleDiagnosisLoadingPage(
          birth: widget.birth,
          hour: widget.hour,
          isMale: widget.isMale,
          eventText: widget.eventText,
          analysis: analysis,
          meaning: meaning,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    final analysis = _analysis;
    return Scaffold(
      backgroundColor: LifeAtlasVisuals.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: LifeAtlasVisuals.ivory,
        elevation: 0,
        title:
            const Text('确认这一刻', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: LifeAtlasBackdrop(
        child: SafeArea(
          top: false,
          child: analysis == null ? _loadingOrError() : _content(analysis),
        ),
      ),
    );
  }

  Widget _loadingOrError() {
    if (_error == null) {
      return const Center(
        child: CircularProgressIndicator(
            color: LifeAtlasVisuals.gold, strokeWidth: 2),
      );
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: LifeAtlasVisuals.ivory),
            ),
            SizedBox(height: 18.h),
            OutlinedButton(
              onPressed: _analyze,
              style: OutlinedButton.styleFrom(
                foregroundColor: LifeAtlasVisuals.gold,
                side: const BorderSide(color: LifeAtlasVisuals.goldSoft),
              ),
              child: const Text('重新理解'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(LifeAtlasEventAnalysis analysis) {
    final palette = LifeAtlasPalette.forDomain(analysis.domain);
    return ListView(
      padding: EdgeInsets.fromLTRB(19.w, 16.h, 19.w, 38.h),
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
          decoration: BoxDecoration(
            color: const Color(0xFF101715).withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(analysis.domain.icon, size: 17, color: palette.accent),
              SizedBox(width: 9.w),
              Expanded(
                child: Text(
                  widget.eventText.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFD2D1CA),
                    fontSize: 12.sp,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 29.h),
        Text(
          '它对你，真正意味着什么？',
          style: TextStyle(
            color: LifeAtlasVisuals.gold,
            fontSize: 12.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          analysis.question,
          style: TextStyle(
            color: LifeAtlasVisuals.ivory,
            fontSize: 26.sp,
            fontWeight: FontWeight.w900,
            height: 1.28,
          ),
        ),
        SizedBox(height: 9.h),
        Text(
          '选最接近的一项，让称号真正属于你的经历。',
          style: TextStyle(color: LifeAtlasVisuals.muted, fontSize: 11.5.sp),
        ),
        SizedBox(height: 26.h),
        ...analysis.options.indexed.map(
          (entry) {
            final index = entry.$1;
            final item = entry.$2;
            return Padding(
              padding: EdgeInsets.only(bottom: 11.h),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _select(item),
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: const Color(0xB80B1110),
                      border: Border.all(color: const Color(0xFF384641)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 29.w,
                          height: 29.w,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.glow.withValues(alpha: 0.16),
                            border: Border.all(
                                color: palette.accent.withValues(alpha: 0.44)),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                                color: palette.accent,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              color: const Color(0xFFE7E2D7),
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              height: 1.42,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded,
                            color: palette.accent, size: 17),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
