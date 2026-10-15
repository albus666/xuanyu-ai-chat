import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/utils/share_card_capture.dart';
import '../../core/utils/ai_content.dart';
import '../../core/widgets/app_share_more_button.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../../shared/widgets/account_session_guard.dart';
import '../../shared/widgets/cultural_reference_notice.dart';
import 'models/life_atlas_models.dart';
import 'services/life_atlas_store.dart';
import 'widgets/life_atlas_scene.dart';
import 'widgets/life_atlas_visuals.dart';
import 'widgets/role_diagnosis_share_card.dart';

class RoleDiagnosisResultPage extends StatefulWidget {
  const RoleDiagnosisResultPage({super.key, required this.result});

  final LifeAtlasResult result;

  @override
  State<RoleDiagnosisResultPage> createState() =>
      _RoleDiagnosisResultPageState();
}

class _RoleDiagnosisResultPageState extends State<RoleDiagnosisResultPage>
    with AccountSessionGuard<RoleDiagnosisResultPage> {
  final _shareKey = GlobalKey();
  late LifeAtlasAchievement _selected;

  LifeAtlasResult get result => widget.result;

  @override
  void initState() {
    super.initState();
    _selected = result.recommendedAchievement;
    _restoreSelected();
  }

  Future<void> _restoreSelected() async {
    final report = result.report;
    final id = await LifeAtlasStore.loadMainTitleId(
      session: accountSession,
      birth: report.birthDate,
      hour: report.birthHour,
      isMale: report.genderMale,
    );
    if (!mounted || !accountSession.current || id == null) return;
    for (final achievement in result.allAchievements) {
      if (achievement.id == id) {
        setState(() => _selected = achievement);
        return;
      }
    }
  }

  Future<void> _select(LifeAtlasAchievement achievement) async {
    if (!accountSession.current) return;
    setState(() => _selected = achievement);
    final report = result.report;
    await LifeAtlasStore.saveMainTitleId(
      session: accountSession,
      birth: report.birthDate,
      hour: report.birthHour,
      isMale: report.genderMale,
      achievementId: achievement.id,
    );
  }

  Future<void> _share() async {
    if (!accountSession.current) return;
    await showAppShareSheet(
      context,
      title: '人生图鉴',
      imageBuilder: () => ShareCardCapture.captureWidget(
          repaintKey: _shareKey, aiGenerated: true),
      shareText: AiContent.markedText(
          '【玄遇人生图鉴】${_selected.title}\n${_selected.quote}', 'AI生成内容'),
    );
  }

  void _continueAtlas() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    return Scaffold(
      backgroundColor: const Color(0xFF030504),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030504),
        foregroundColor: const Color(0xFFF4F1E8),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '我的人生图鉴',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '分享称号',
            onPressed: _share,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: LifeAtlasBackdrop(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '当前佩戴',
                    style: TextStyle(
                      color: LifeAtlasVisuals.gold,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 9.h),
                  _heroCard(),
                  SizedBox(height: 25.h),
                  _sectionTitle('我的称号 · ${result.allAchievements.length}'),
                  SizedBox(height: 12.h),
                  if (result.allAchievements.isEmpty)
                    _emptyAchievements()
                  else
                    _achievementGrid(),
                  if (result.hiddenAchievements.isNotEmpty) ...[
                    SizedBox(height: 24.h),
                    _sectionTitle('命运交汇'),
                    SizedBox(height: 12.h),
                    ...result.hiddenAchievements.map(_hiddenCard),
                  ],
                  const CulturalReferenceNotice(
                    color: LifeAtlasVisuals.muted,
                  ),
                ],
              ),
            ),
            Positioned(
              left: -10000,
              top: 0,
              child: IgnorePointer(
                child: RepaintBoundary(
                  key: _shareKey,
                  child: RoleDiagnosisShareCard(achievement: _selected),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
          decoration: BoxDecoration(
            color: const Color(0xFF050706),
            border: Border(
              top: BorderSide(
                color: const Color(0xFFD8B363).withValues(alpha: 0.22),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _continueAtlas,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('继续点亮'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD8B363),
                    side: const BorderSide(color: Color(0xFF745E39)),
                    minimumSize: Size.fromHeight(48.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  icon: const ReferenceActionGlyph(
                    type: ReferenceActionIconType.shareImage,
                    size: 18,
                    color: Color(0xFF171108),
                  ),
                  label: const Text('生成分享图'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD8B363),
                    foregroundColor: const Color(0xFF171108),
                    minimumSize: Size.fromHeight(48.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard() {
    return LifeAtlasAchievementCard(achievement: _selected, selected: true);
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: const Color(0xFFF4F1E8),
        fontSize: 18.sp,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _achievementGrid() {
    return Column(
      children: [
        for (final item in result.allAchievements)
          Padding(
            padding: EdgeInsets.only(bottom: 11.h),
            child: LifeAtlasAchievementCard(
              achievement: item,
              selected: _selected.id == item.id,
              onTap: () => _select(item),
            ),
          ),
      ],
    );
  }

  Widget _emptyAchievements() {
    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D0C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF282B28)),
      ),
      child: const Text(
        '还没有点亮称号。',
        style: TextStyle(color: Color(0xFFB8B4AA), height: 1.6),
      ),
    );
  }

  Widget _hiddenCard(LifeAtlasAchievement item) {
    final palette = LifeAtlasPalette.forDomain(item.domain);
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: InkWell(
        onTap: () => _select(item),
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: EdgeInsets.all(15.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            gradient: LinearGradient(
              colors: [
                palette.glow.withValues(alpha: 0.18),
                const Color(0xFF090B0A),
              ],
            ),
            border: Border.all(color: palette.accent.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.glow.withValues(alpha: 0.2),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: palette.accent,
                  size: 21,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: const Color(0xFFF4F1E8),
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      item.quote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFAAA69C),
                        fontSize: 11.sp,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.accent,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
