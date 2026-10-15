import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/shared/widgets/account_session_guard.dart';

import 'engine/role_diagnosis_engine.dart';
import 'life_atlas_title_choice_page.dart';
import 'models/life_atlas_models.dart';
import 'models/role_diagnosis_models.dart';
import 'services/life_atlas_api_service.dart';
import 'services/role_diagnosis_api_service.dart';
import 'services/role_diagnosis_cache_service.dart';
import 'widgets/life_atlas_visuals.dart';

class RoleDiagnosisLoadingPage extends StatefulWidget {
  const RoleDiagnosisLoadingPage({
    super.key,
    required this.birth,
    required this.hour,
    required this.isMale,
    required this.eventText,
    required this.analysis,
    required this.meaning,
  });

  final DateTime birth;
  final int hour;
  final bool isMale;
  final String eventText;
  final LifeAtlasEventAnalysis analysis;
  final LifeAtlasMeaningOption meaning;

  @override
  State<RoleDiagnosisLoadingPage> createState() =>
      _RoleDiagnosisLoadingPageState();
}

class _RoleDiagnosisLoadingPageState extends State<RoleDiagnosisLoadingPage>
    with
        SingleTickerProviderStateMixin,
        AccountSessionGuard<RoleDiagnosisLoadingPage> {
  static const _lines = [
    '正在读懂这件事…',
    '正在寻找它真正改变的部分…',
    '正在写下属于你的三个名字…',
  ];

  Timer? _lineTimer;
  var _lineIndex = 0;
  late final AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _lineTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted) {
        setState(() => _lineIndex = (_lineIndex + 1) % _lines.length);
      }
    });
    _run();
  }

  Future<void> _run() async {
    RoleDiagnosisReport report;
    final cached = await RoleDiagnosisCacheService.load(
      session: accountSession,
      birth: widget.birth,
      hour: widget.hour,
      isMale: widget.isMale,
    );
    if (!mounted || !accountSession.current) return;
    if (cached != null) {
      report = cached;
    } else {
      try {
        final result = await RoleDiagnosisApiService.diagnose(
          session: accountSession,
          birth: widget.birth,
          hour: widget.hour,
          isMale: widget.isMale,
          waitForLongReport: false,
        );
        if (!mounted || !accountSession.current) return;
        report = result.report;
        if (result.cacheable) {
          await RoleDiagnosisCacheService.save(
            session: accountSession,
            birth: widget.birth,
            hour: widget.hour,
            isMale: widget.isMale,
            report: report,
          );
        }
      } catch (_) {
        if (!mounted || !accountSession.current) return;
        report = RoleDiagnosisEngine.diagnose(
          birth: widget.birth,
          hour: widget.hour,
          isMale: widget.isMale,
        );
      }
    }
    if (!mounted || !accountSession.current) return;
    final generated = await LifeAtlasApiService.generateEvent(
      session: accountSession,
      eventText: widget.eventText,
      analysis: widget.analysis,
      meaning: widget.meaning,
      report: report,
    );
    if (!mounted || !accountSession.current) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LifeAtlasTitleChoicePage(
          birth: widget.birth,
          hour: widget.hour,
          isMale: widget.isMale,
          report: report,
          generated: generated,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _lineTimer?.cancel();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    return Scaffold(
      backgroundColor: LifeAtlasVisuals.background,
      body: LifeAtlasBackdrop(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RotationTransition(
                turns: _orbitController,
                child: Container(
                  width: 78.w,
                  height: 78.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: LifeAtlasVisuals.gold.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: LifeAtlasVisuals.gold,
                          size: 18,
                        ),
                      ),
                      Center(
                        child: Icon(
                          Icons.fingerprint_rounded,
                          color: Color(0xFF75A59C),
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 30.h),
              Text(
                '玄遇人生图鉴',
                style: TextStyle(
                  color: LifeAtlasVisuals.gold,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 14.h),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _lines[_lineIndex],
                  key: ValueKey(_lineIndex),
                  style: TextStyle(
                    color: LifeAtlasVisuals.ivory,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
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
