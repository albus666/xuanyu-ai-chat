import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../app/common/utils/nav_utils.dart';
import '../../core/profile/account_birth_profile.dart';
import '../../shared/widgets/account_session_guard.dart';
import '../../shared/widgets/cultural_reference_notice.dart';
import '../../core/network/api_session_scope.dart';
import 'engine/role_diagnosis_engine.dart';
import 'life_atlas_experience_page.dart';
import 'models/life_atlas_models.dart';
import 'role_diagnosis_result_page.dart';
import 'services/life_atlas_store.dart';
import 'widgets/life_atlas_visuals.dart';

class RoleDiagnosisInputPage extends StatefulWidget {
  const RoleDiagnosisInputPage({super.key});

  @override
  State<RoleDiagnosisInputPage> createState() => _RoleDiagnosisInputPageState();
}

class _RoleDiagnosisInputPageState extends State<RoleDiagnosisInputPage>
    with AccountSessionGuard<RoleDiagnosisInputPage> {
  static const _suggestions = ['今天考上编制了', '开始了第一次创业', '第一次去国外'];

  final _eventController = TextEditingController();
  DateTime _birth = DateTime(2000, 1, 1);
  int _hour = 12;
  bool _male = true;
  bool _loadingProfile = true;
  bool _hasAccountBirth = false;
  List<LifeAtlasAchievement> _achievements = const [];

  @override
  void initState() {
    super.initState();
    _loadAccountProfile();
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountProfile() async {
    try {
      final profile = await AccountBirthProfileRepository.load();
      final parsed = profile.birthDateTime;
      if (!mounted || !accountSession.current) return;
      if (parsed != null && profile.isComplete) {
        _birth = DateTime(parsed.year, parsed.month, parsed.day);
        _hour = parsed.hour;
        _male = profile.gender == 1;
        _hasAccountBirth = true;
      }
    } on ApiSessionChangedException {
      return;
    } on DioException catch (_) {
      // 账号资料暂时不可用时保留统一补充入口，不使用默认生辰生成内容。
    } finally {
      if (mounted && accountSession.current) {
        setState(() => _loadingProfile = false);
        await _loadAtlas();
      }
    }
  }

  Future<void> _loadAtlas() async {
    if (!mounted || !accountSession.current) return;
    final items = await LifeAtlasStore.loadAchievements(
      session: accountSession,
      birth: _birth,
      hour: _hour,
      isMale: _male,
    );
    if (mounted && accountSession.current) {
      setState(() => _achievements = items);
    }
  }

  Future<void> _pickDate() async {
    if (!accountSession.current) return;
    final profile = await AccountBirthProfileRepository.ensure(
      context,
      reason: '完善一次后，人生图鉴和其他本人功能都会自动使用',
    );
    final parsed = profile?.birthDateTime;
    if (!mounted ||
        !accountSession.current ||
        parsed == null ||
        profile == null) {
      return;
    }
    setState(() {
      _birth = DateTime(parsed.year, parsed.month, parsed.day);
      _hour = parsed.hour;
      _male = profile.gender == 1;
      _hasAccountBirth = true;
      _achievements = const [];
    });
    await _loadAtlas();
  }

  Future<void> _start() async {
    if (!accountSession.current) return;
    if (!_hasAccountBirth) {
      await _pickDate();
      if (!_hasAccountBirth || !mounted || !accountSession.current) return;
    }
    final text = _eventController.text.trim();
    if (text.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写下一件今天或最近发生的事')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LifeAtlasExperiencePage(
          birth: _birth,
          hour: _hour,
          isMale: _male,
          eventText: text,
        ),
      ),
    ).then((_) {
      _eventController.clear();
      _loadAtlas();
    });
  }

  void _openAtlas([LifeAtlasAchievement? selected]) {
    if (_achievements.isEmpty || !accountSession.current) return;
    final report = RoleDiagnosisEngine.diagnose(
      birth: _birth,
      hour: _hour,
      isMale: _male,
    );
    final ordered = selected == null
        ? _achievements
        : [selected, ..._achievements.where((item) => item.id != selected.id)];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoleDiagnosisResultPage(
          result: LifeAtlasResult(
            report: report,
            baseTitle: '人生记录者',
            baseQuote: '',
            achievements: ordered,
            hiddenAchievements: const [],
            confirmedQuestionIds: const [],
            answeredCount: ordered.length,
            totalQuestionCount: ordered.length,
          ),
        ),
      ),
    ).then((_) => _loadAtlas());
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
        scrolledUnderElevation: 0,
        leading: const IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: NavUtils.goBack,
        ),
        title:
            const Text('人生图鉴', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          if (_achievements.isNotEmpty)
            TextButton(
              onPressed: _openAtlas,
              child: Text(
                '${_achievements.length} 枚',
                style: const TextStyle(color: LifeAtlasVisuals.gold),
              ),
            ),
        ],
      ),
      body: LifeAtlasBackdrop(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(18.w, 10.h, 18.w, 38.h),
            children: [
              _profilePill(),
              SizedBox(height: 26.h),
              Text(
                '把今天，写进人生。',
                style: TextStyle(
                  color: LifeAtlasVisuals.gold,
                  fontSize: 29.sp,
                  fontWeight: FontWeight.w900,
                  height: 1.22,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                '一件真实发生的事，点亮一枚只属于你的称号。',
                style: TextStyle(
                  color: LifeAtlasVisuals.muted,
                  fontSize: 12.5.sp,
                  height: 1.55,
                ),
              ),
              SizedBox(height: 20.h),
              _eventInput(),
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: _suggestions.map(_suggestionChip).toList(),
              ),
              SizedBox(height: 19.h),
              _generateButton(),
              if (_achievements.isNotEmpty) ...[
                SizedBox(height: 31.h),
                Row(
                  children: [
                    Text(
                      '最近点亮',
                      style: TextStyle(
                        color: LifeAtlasVisuals.ivory,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _openAtlas,
                      child: const Text(
                        '查看图鉴  →',
                        style: TextStyle(color: LifeAtlasVisuals.gold),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                ..._achievements.take(2).map(
                      (item) => Padding(
                        padding: EdgeInsets.only(bottom: 12.h),
                        child: LifeAtlasAchievementCard(
                          achievement: item,
                          onTap: () => _openAtlas(item),
                        ),
                      ),
                    ),
              ],
              const CulturalReferenceNotice(color: LifeAtlasVisuals.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profilePill() {
    final label = _loadingProfile
        ? '正在连接出生信息'
        : _hasAccountBirth
            ? '出生信息已连接'
            : '完善本人出生资料';
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _loadingProfile ? null : _pickDate,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: EdgeInsets.fromLTRB(11.w, 7.h, 9.w, 7.h),
            decoration: BoxDecoration(
              color: const Color(0xFF15201E).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF405A55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: LifeAtlasVisuals.gold, size: 15),
                SizedBox(width: 7.w),
                Text(
                  label,
                  style: TextStyle(
                      color: const Color(0xFFD1D5CE), fontSize: 11.sp),
                ),
                SizedBox(width: 7.w),
                const Icon(Icons.tune_rounded,
                    color: Color(0xFF8FA39E), size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xB80B1110),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF42524E)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: TextField(
        controller: _eventController,
        minLines: 3,
        maxLines: 4,
        maxLength: 240,
        textInputAction: TextInputAction.newline,
        style: TextStyle(
            color: LifeAtlasVisuals.ivory, fontSize: 15.sp, height: 1.55),
        decoration: InputDecoration(
          hintText: '例如：今天考上编制了',
          hintStyle: const TextStyle(color: Color(0xFF77817E)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(16.w, 15.h, 16.w, 8.h),
          counterStyle:
              TextStyle(color: const Color(0xFF68736F), fontSize: 10.sp),
        ),
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return ActionChip(
      onPressed: () {
        _eventController.text = text;
        _eventController.selection =
            TextSelection.collapsed(offset: text.length);
      },
      backgroundColor: const Color(0xFF111917),
      side: const BorderSide(color: Color(0xFF354440)),
      label: Text(text),
      labelStyle: TextStyle(color: const Color(0xFFBDC5C0), fontSize: 10.5.sp),
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _generateButton() {
    return SizedBox(
      height: 51.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            colors: [Color(0xFFE7C478), Color(0xFFB88A3D)],
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x407A5A27), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: FilledButton.icon(
          onPressed: _loadingProfile ? null : _start,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: const Color(0xFF3D403B),
            foregroundColor: const Color(0xFF181208),
            shadowColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 17),
          label: Text(
            '生成我的人生称号',
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}
