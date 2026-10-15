import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/shared/widgets/account_session_guard.dart';

import 'models/life_atlas_models.dart';
import 'models/role_diagnosis_models.dart';
import 'role_diagnosis_result_page.dart';
import 'services/life_atlas_api_service.dart';
import 'services/life_atlas_store.dart';
import 'widgets/life_atlas_visuals.dart';

class LifeAtlasTitleChoicePage extends StatefulWidget {
  const LifeAtlasTitleChoicePage({
    super.key,
    required this.birth,
    required this.hour,
    required this.isMale,
    required this.report,
    required this.generated,
  });

  final DateTime birth;
  final int hour;
  final bool isMale;
  final RoleDiagnosisReport report;
  final LifeAtlasGeneratedTitles generated;

  @override
  State<LifeAtlasTitleChoicePage> createState() =>
      _LifeAtlasTitleChoicePageState();
}

class _LifeAtlasTitleChoicePageState extends State<LifeAtlasTitleChoicePage>
    with AccountSessionGuard<LifeAtlasTitleChoicePage> {
  var _saving = false;
  String? _selectedId;

  Future<void> _choose(LifeAtlasAchievement candidate) async {
    if (_saving || !accountSession.current) return;
    setState(() {
      _selectedId = candidate.id;
      _saving = true;
    });
    final statistic = candidate.eventKey == null
        ? null
        : await LifeAtlasApiService.unlockEvent(candidate.eventKey!,
            session: accountSession);
    if (!mounted || !accountSession.current) return;
    var selected = candidate.copyWith(unlockedAt: DateTime.now());
    if (statistic?.sampleSufficient == true) {
      selected = selected.copyWith(
        rarityLabel: statistic!.rarityLabel,
        rarityPercent: statistic.percent,
      );
    }
    final achievements = await LifeAtlasStore.saveAchievement(
      session: accountSession,
      birth: widget.birth,
      hour: widget.hour,
      isMale: widget.isMale,
      achievement: selected,
    );
    if (!mounted || !accountSession.current) return;
    await LifeAtlasStore.saveMainTitleId(
      session: accountSession,
      birth: widget.birth,
      hour: widget.hour,
      isMale: widget.isMale,
      achievementId: selected.id,
    );
    if (!mounted || !accountSession.current) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RoleDiagnosisResultPage(
          result: LifeAtlasResult(
            report: widget.report,
            baseTitle: '人生记录者',
            baseQuote: '',
            achievements: achievements,
            hiddenAchievements: const [],
            confirmedQuestionIds: const [],
            answeredCount: achievements.length,
            totalQuestionCount: achievements.length,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    return Scaffold(
      backgroundColor: LifeAtlasVisuals.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: LifeAtlasVisuals.ivory,
        elevation: 0,
        title:
            const Text('选择人生称号', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: LifeAtlasBackdrop(
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(15.w, 10.h, 15.w, 38.h),
              children: [
                Text(
                  '同一段经历，\n可以有不同的名字。',
                  style: TextStyle(
                    color: LifeAtlasVisuals.ivory,
                    fontSize: 25.sp,
                    fontWeight: FontWeight.w900,
                    height: 1.26,
                  ),
                ),
                SizedBox(height: 9.h),
                Text(
                  '选一个最像你的，它会正式进入人生图鉴。',
                  style: TextStyle(
                      color: LifeAtlasVisuals.muted, fontSize: 11.5.sp),
                ),
                SizedBox(height: 22.h),
                ...widget.generated.candidates.map(
                  (item) => Padding(
                    padding: EdgeInsets.only(bottom: 14.h),
                    child: LifeAtlasAchievementCard(
                      achievement: item,
                      selected: item.id == _selectedId,
                      footerText: item.id == _selectedId && _saving
                          ? '正在点亮…'
                          : '选择这个称号  →',
                      showPercent: false,
                      onTap: () => _choose(item),
                    ),
                  ),
                ),
              ],
            ),
            if (_saving)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x22000000)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
