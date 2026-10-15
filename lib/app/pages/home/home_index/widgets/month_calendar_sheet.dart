import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:lunar/lunar.dart';
import 'package:xuanyu/app/common/routers/names.dart';
import 'package:xuanyu/app/common/style/colors.dart';
import 'package:xuanyu/core/local/archive_account_scope.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/features/fortune/almanac/personal_date_selection.dart';
import 'package:xuanyu/features/fortune/bazi_input_page.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/fortune/paipan/share/paipan_extra_content_service.dart';
import 'package:xuanyu/features/fortune/paipan/utils/bazi_result.dart';
import 'package:xuanyu/features/fortune/paipan/utils/decline_yongshen_parse.dart';

/// 首页左上角日历：保留轻入口，点击后展示分层的今日万年历。
class MonthCalendarSheet extends StatefulWidget {
  const MonthCalendarSheet({super.key, this.initial});

  final DateTime? initial;

  static Future<DateTime?> show(BuildContext context, {DateTime? initial}) {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
      ),
      builder: (_) => MonthCalendarSheet(initial: initial),
    );
  }

  @override
  State<MonthCalendarSheet> createState() => _MonthCalendarSheetState();
}

class _MonthCalendarSheetState extends State<MonthCalendarSheet> {
  static const Color _gold = Color(0xFFD4B56A);
  static const Color _softGold = Color(0xFFFFF6DE);
  static const Color _softRed = Color(0xFFFFEEF0);
  static const Color _red = Color(0xFFE53935);
  static const String _createPartnerArchiveAction = 'create_partner_archive';

  late DateTime _visibleMonth;
  late DateTime _selected;
  final _personalEngine = const PersonalDateSelectionEngine();
  List<PaipanRecord> _archives = const [];
  PaipanRecord? _selectedArchive;
  PersonalAlmanacProfile? _personalProfile;
  PaipanRecord? _partnerArchive;
  PersonalAlmanacProfile? _partnerProfile;
  PersonalDatePurpose _purpose = PersonalDatePurpose.communication;
  bool _personalEnabled = true;
  bool _profileLoading = true;
  int _profileLoadToken = 0;
  int _partnerLoadToken = 0;
  int? _archiveUserId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = widget.initial ?? now;
    _visibleMonth = DateTime(_selected.year, _selected.month);
    _loadArchives();
  }

  Future<void> _loadArchives() async {
    final userId = await ArchiveAccountScope.currentUserId();
    final unique = _deduplicateArchives(await PaipanRecordStore.loadAll());
    final currentUserId = await ArchiveAccountScope.currentUserId();
    if (!mounted || currentUserId != userId) return;
    setState(() {
      _archiveUserId = userId;
      _archives = unique;
      _profileLoading = unique.isNotEmpty;
      if (unique.isEmpty) {
        _profileLoadToken++;
        _partnerLoadToken++;
        _selectedArchive = null;
        _personalProfile = null;
        _partnerArchive = null;
        _partnerProfile = null;
      }
    });
    if (unique.isEmpty) return;
    await _activateArchive(unique.first);
  }

  List<PaipanRecord> _deduplicateArchives(List<PaipanRecord> loaded) {
    final seen = <String>{};
    // 同生日不代表同一人，按档案 ID 去重，确保每份档案都能独立管理。
    return loaded.where((record) => seen.add(record.id)).toList();
  }

  Future<void> _activateArchive(PaipanRecord record) async {
    final token = ++_profileLoadToken;
    setState(() {
      _selectedArchive = record;
      _personalProfile = null;
      _profileLoading = true;
      if (_partnerArchive?.id == record.id) {
        _partnerLoadToken++;
        _partnerArchive = null;
        _partnerProfile = null;
      }
    });
    try {
      final profile = await _profileFromRecord(record);
      if (!mounted || token != _profileLoadToken) return;
      setState(() {
        _personalProfile = profile;
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _profileLoadToken) return;
      setState(() => _profileLoading = false);
    }
  }

  Future<PersonalAlmanacProfile> _profileFromRecord(PaipanRecord record) async {
    final result = computeBaziResult(
      record.birthDateTime,
      isFemale: record.isFemale,
    );
    final extra = await loadPaipanExtraContent(result, record.isFemale);
    final parsed = parseYongshenYsToXiYong(extra.yongShen);
    final supportive = <String>{};
    final yong = parsed?['用神'];
    final xi = parsed?['喜神'];
    if (yong != null && yong.isNotEmpty) supportive.add(yong);
    if (xi != null && xi.isNotEmpty) supportive.add(xi);
    return PersonalAlmanacProfile(
      name: record.displayName.trim().isEmpty
          ? '未命名档案'
          : record.displayName.trim(),
      gans: result.gans,
      zhis: result.zhis,
      supportiveElements: supportive,
    );
  }

  Future<void> _activatePartnerArchive(PaipanRecord record) async {
    final token = ++_partnerLoadToken;
    setState(() {
      _partnerArchive = record;
      _partnerProfile = null;
    });
    try {
      final profile = await _profileFromRecord(record);
      if (!mounted || token != _partnerLoadToken) return;
      setState(() => _partnerProfile = profile);
    } catch (_) {
      if (!mounted || token != _partnerLoadToken) return;
      setState(() => _partnerArchive = null);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  DateTime get _effectiveSelected {
    final now = DateTime.now();
    if (_sameDay(_selected, now)) return now;
    return DateTime(_selected.year, _selected.month, _selected.day, 12);
  }

  Lunar get _lunar => Lunar.fromDate(_effectiveSelected);

  @override
  Widget build(BuildContext context) {
    final lunar = _lunar;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF7FBFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18.w, 10.h, 18.w, 8.h),
                child: Column(
                  children: [
                    Container(
                      width: 38.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    _buildHeader(lunar),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 18.h),
                  children: [
                    _buildMonthGrid(),
                    SizedBox(height: 12.h),
                    _buildPersonalDateCard(),
                    SizedBox(height: 12.h),
                    _buildYiJiCard(lunar),
                    SizedBox(height: 12.h),
                    _buildProfessionalCard(lunar),
                    SizedBox(height: 12.h),
                    _buildTimeCard(lunar),
                    SizedBox(height: 16.h),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 13.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Lunar lunar) {
    final luck = _fortuneLabel(lunar);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9BE9F5), Color(0xFFE9F8F6)],
        ),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selected.year}年${_selected.month}月${_selected.day}日',
                  style: TextStyle(
                    fontSize: 22.sp,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  '${_weekdayText(_selected)} · 农历${lunar.getMonthInChinese()}月${lunar.getDayInChinese()} · ${lunar.getDayInGanZhi()}日',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: luck.color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: luck.color.withValues(alpha: 0.26)),
            ),
            child: Text(
              luck.label,
              style: TextStyle(
                color: luck.color,
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid() {
    final firstWeekday = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    ).weekday;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leading = firstWeekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++) _dayCell(d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    return _sectionCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                color: AppColors.textSecondary,
                onPressed: () => _shiftMonth(-1),
              ),
              Expanded(
                child: Text(
                  '${_visibleMonth.year}年${_visibleMonth.month}月',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                color: AppColors.textSecondary,
                onPressed: () => _shiftMonth(1),
              ),
            ],
          ),
          Row(
            children: ['日', '一', '二', '三', '四', '五', '六']
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: 8.h),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            mainAxisSpacing: 6.h,
            crossAxisSpacing: 5.w,
            childAspectRatio: 0.92,
            children: cells,
          ),
        ],
      ),
    );
  }

  Widget _dayCell(int day) {
    final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
    final lunar = Lunar.fromDate(DateTime(date.year, date.month, date.day, 12));
    final isSelected = _sameDay(date, _selected);
    final isToday = _sameDay(date, DateTime.now());
    final personal = _personalEnabled
        ? _evaluatePersonalDate(date, includeTimes: false)
        : null;
    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isToday ? AppColors.tagBg : Colors.transparent),
          borderRadius: BorderRadius.circular(10.r),
          border: isToday && !isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.45))
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  lunar.getDayInChinese(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: isSelected ? Colors.white70 : AppColors.textHint,
                  ),
                ),
              ],
            ),
            if (personal != null)
              Positioned(
                bottom: 2.h,
                child: Container(
                  width: 4.r,
                  height: 4.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Colors.white
                        : _personalLevelColor(personal.level),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalDateCard() {
    final profile = _personalProfile;
    final evaluation = _evaluatePersonalDate(_selected);
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('个人择日', '同一天，按你的八字与具体事项分别判断')),
              Switch.adaptive(
                value: _personalEnabled,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                activeThumbColor: AppColors.primary,
                onChanged: (value) => setState(() => _personalEnabled = value),
              ),
            ],
          ),
          if (!_personalEnabled) ...[
            SizedBox(height: 12.h),
            Text(
              '开启后可使用八字档案查看个人择日。',
              style: TextStyle(
                fontSize: 12.sp,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ] else if (_profileLoading) ...[
            SizedBox(height: 16.h),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(height: 10.h),
            Center(
              child: Text(
                '正在读取八字档案…',
                style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
              ),
            ),
          ] else if (_archives.isEmpty) ...[
            SizedBox(height: 14.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FAF9),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '建立八字档案后即可启用',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Text(
                    '建立档案后可查看个人择日建议。',
                    style: TextStyle(
                      fontSize: 12.sp,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  TextButton.icon(
                    onPressed: _openBazi,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('去建立八字档案'),
                  ),
                ],
              ),
            ),
          ] else if (profile != null) ...[
            SizedBox(height: 12.h),
            _buildArchiveSelector(profile),
            SizedBox(height: 12.h),
            SizedBox(
              height: 36.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: PersonalDatePurpose.values.length,
                separatorBuilder: (_, __) => SizedBox(width: 7.w),
                itemBuilder: (_, index) {
                  final item = PersonalDatePurpose.values[index];
                  final selected = item == _purpose;
                  return ChoiceChip(
                    label: Text(item.label),
                    selected: selected,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: const Color(0xFFF3F8F8),
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.divider,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    onSelected: (_) => setState(() => _purpose = item),
                  );
                },
              ),
            ),
            SizedBox(height: 12.h),
            if (_purpose == PersonalDatePurpose.wedding) ...[
              _buildPartnerSelector(),
              SizedBox(height: 12.h),
            ],
            if (evaluation != null)
              _buildEvaluation(evaluation)
            else
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Text(
                  '请再选择一份对方八字档案，查看双方共同适合的日期。',
                  style: TextStyle(
                    fontSize: 12.sp,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: evaluation == null
                    ? null
                    : () => _showThirtyDayRecommendations(profile),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('帮我找未来30天'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.42),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 11.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13.r),
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '个人择日为传统文化参考，不代表事情必然成功；重要决定仍应结合现实条件。',
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 10.sp,
                height: 1.4,
              ),
            ),
          ] else ...[
            SizedBox(height: 12.h),
            Text(
              '当前档案暂时无法读取，请重新选择八字档案。',
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
            TextButton(
                onPressed: _showArchivePicker, child: const Text('选择八字档案')),
          ],
        ],
      ),
    );
  }

  PersonalDateEvaluation? _evaluatePersonalDate(
    DateTime date, {
    bool includeTimes = true,
  }) {
    final profile = _personalProfile;
    if (profile == null) return null;
    if (_purpose == PersonalDatePurpose.wedding) {
      final partner = _partnerProfile;
      if (partner == null) return null;
      return _personalEngine.evaluateForPair(
        date: date,
        purpose: _purpose,
        first: profile,
        second: partner,
        includeTimes: includeTimes,
      );
    }
    return _personalEngine.evaluate(
      date: date,
      purpose: _purpose,
      profile: profile,
      includeTimes: includeTimes,
    );
  }

  Widget _buildArchiveSelector(PersonalAlmanacProfile profile) {
    return InkWell(
      borderRadius: BorderRadius.circular(14.r),
      onTap: _showArchivePicker,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEAF9F7), Color(0xFFF4F1FF)],
          ),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Container(
              width: 34.r,
              height: 34.r,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 19.r,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    profile.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '切换',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary,
              size: 20.r,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerSelector() {
    final profile = _partnerProfile;
    return InkWell(
      borderRadius: BorderRadius.circular(14.r),
      onTap: () => _showArchivePicker(partner: true),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAEF),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: _gold.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(Icons.favorite_border_rounded, color: _gold, size: 22.r),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.name ?? '选择对方八字档案',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (profile != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      profile.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              profile == null ? '添加' : '切换',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: _gold,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _gold, size: 20.r),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluation(PersonalDateEvaluation evaluation) {
    final color = _personalLevelColor(evaluation.level);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  evaluation.levelLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  '${evaluation.dayGanZhi}日 · ${evaluation.purpose.label}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (evaluation.reasons.isNotEmpty) ...[
            SizedBox(height: 10.h),
            for (final reason in evaluation.reasons)
              Padding(
                padding: EdgeInsets.only(bottom: 5.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Container(
                        width: 4.r,
                        height: 4.r,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    ),
                    SizedBox(width: 7.w),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 12.sp,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (evaluation.recommendedTimes.isNotEmpty) ...[
            SizedBox(height: 5.h),
            Text(
              '参考时段',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textHint,
              ),
            ),
            SizedBox(height: 6.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: [
                for (final time in evaluation.recommendedTimes)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 5.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(9.r),
                    ),
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showArchivePicker({bool partner = false}) async {
    String? deletingId;
    String? deleteError;
    bool deleteInProgress = false;
    final selection = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final choices = partner
              ? _archives
                  .where((record) => record.id != _selectedArchive?.id)
                  .toList()
              : _archives;
          Future<void> confirmDelete(PaipanRecord record) async {
            if (deletingId != null) return;
            setSheetState(() {
              deletingId = record.id;
              deleteError = null;
            });
            final name = record.displayName.trim().isEmpty
                ? '未命名档案'
                : record.displayName.trim();
            final confirmed = await showDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('删除八字档案？'),
                content: Text(
                    '将删除「$name」及其档案笔记，其他使用此档案的入口也会同步移除，无法撤销。\n不会修改账号中的出生资料。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消')),
                  TextButton(
                    key: const ValueKey('calendar-confirm-delete'),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: TextButton.styleFrom(foregroundColor: _red),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (!sheetContext.mounted || !mounted) return;
            if (confirmed == true) {
              setSheetState(() => deleteInProgress = true);
              try {
                await _deleteArchive(record);
              } catch (_) {
                deleteError = '删除失败，档案已保留，请稍后重试';
              }
            }
            if (!sheetContext.mounted || !mounted) return;
            setSheetState(() {
              deletingId = null;
              deleteInProgress = false;
            });
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 0),
                    child: Text(
                      partner ? '选择对方八字档案' : '选择八字档案',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(18.w, 5.h, 18.w, 12.h),
                    child: Text(
                      partner ? '选择双方档案，查看共同适合的日期' : '选择本次择日使用的档案',
                      style:
                          TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                    ),
                  ),
                  if (deleteError != null)
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
                      child: Text(deleteError!,
                          style: const TextStyle(color: _red)),
                    ),
                  if (choices.isEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(18.w, 8.h, 18.w, 14.h),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16.r),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFAEF),
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              color: _gold,
                              size: 28.r,
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              partner ? '暂无可选的其他档案' : '暂无八字档案',
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              partner ? '新建对方档案后会自动带回这里' : '请先新建一份八字档案',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        itemCount: choices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final record = choices[index];
                          final checked = record.id ==
                              (partner
                                  ? _partnerArchive?.id
                                  : _selectedArchive?.id);
                          return ListTile(
                            key: ValueKey('calendar-archive-${record.id}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              record.displayName.trim().isEmpty
                                  ? '未命名档案'
                                  : record.displayName.trim(),
                            ),
                            subtitle: Text(record.summary),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (checked)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primary,
                                  )
                                else
                                  const Icon(Icons.chevron_right_rounded),
                                IconButton(
                                  key: ValueKey('calendar-delete-${record.id}'),
                                  tooltip: '删除档案',
                                  color: AppColors.textHint,
                                  onPressed: deletingId == null
                                      ? () => confirmDelete(record)
                                      : null,
                                  icon: deleteInProgress &&
                                          deletingId == record.id
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.delete_outline_rounded,
                                          size: 22),
                                ),
                              ],
                            ),
                            onTap: deletingId == null
                                ? () => Navigator.pop(sheetContext, record)
                                : null,
                          );
                        },
                      ),
                    ),
                  if (partner) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 18.h),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key:
                              const ValueKey('calendar-create-partner-archive'),
                          onPressed: deletingId == null
                              ? () => Navigator.pop(
                                    sheetContext,
                                    _createPartnerArchiveAction,
                                  )
                              : null,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('新建对方档案'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.45),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 11.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13.r),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else
                    SizedBox(height: 12.h),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    if (selection == _createPartnerArchiveAction) {
      await _createPartnerArchive();
      return;
    }
    if (selection is PaipanRecord) {
      if (partner) {
        await _activatePartnerArchive(selection);
      } else {
        await _activateArchive(selection);
      }
    }
  }

  Future<void> _deleteArchive(PaipanRecord record) async {
    // 持久化成功后再改界面，失败时保留原选择与择日结果。
    await PaipanRecordStore.delete(record.id, expectedUserId: _archiveUserId);
    if (!mounted) return;
    final wasSelected = _selectedArchive?.id == record.id;
    setState(() {
      _archives = _archives.where((item) => item.id != record.id).toList();
      if (_partnerArchive?.id == record.id) {
        _partnerLoadToken++;
        _partnerArchive = null;
        _partnerProfile = null;
      }
      if (wasSelected) {
        _profileLoadToken++;
        _selectedArchive = null;
        _personalProfile = null;
        _profileLoading = false;
      }
    });
    if (wasSelected && _archives.isNotEmpty) {
      final next = _archives.firstWhere(
        (item) => item.id != _partnerArchive?.id,
        orElse: () => _archives.first,
      );
      await _activateArchive(next);
    }
  }

  Future<void> _createPartnerArchive() async {
    final existingIds = _archives.map((record) => record.id).toSet();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const BaziInputPage(forOther: true, replaceInputWithResult: true),
      ),
    );
    final currentUserId = await ArchiveAccountScope.currentUserId();
    if (!mounted || currentUserId != _archiveUserId) {
      return;
    }

    List<PaipanRecord> refreshed = const [];
    PaipanRecord? created;
    for (var attempt = 0; attempt < 5; attempt++) {
      refreshed = _deduplicateArchives(await PaipanRecordStore.loadAll());
      for (final record in refreshed) {
        if (!existingIds.contains(record.id) &&
            record.id != _selectedArchive?.id) {
          created = record;
          break;
        }
      }
      if (created != null) break;
      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    if (!mounted) return;
    setState(() => _archives = refreshed);
    if (created != null) {
      await _activatePartnerArchive(created);
    }
  }

  Future<void> _showThirtyDayRecommendations(
    PersonalAlmanacProfile profile,
  ) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final partner = _partnerProfile;
    final allResults =
        _purpose == PersonalDatePurpose.wedding && partner != null
            ? _personalEngine.recommendForPair(
                from: start,
                days: 30,
                purpose: _purpose,
                first: profile,
                second: partner,
              )
            : _personalEngine.recommend(
                from: start,
                days: 30,
                purpose: _purpose,
                profile: profile,
              );
    final results = allResults.take(5).toList();
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7FBFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
      ),
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 10.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '未来30天 · ${_purpose.label}',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            '前三项为优选，其余为备选；点击日期回到黄历查看',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => SizedBox(height: 9.h),
                  itemBuilder: (_, index) {
                    final result = results[index];
                    final color = _personalLevelColor(result.level);
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16.r),
                        onTap: () => Navigator.pop(sheetContext, result.date),
                        child: Padding(
                          padding: EdgeInsets.all(14.r),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 46.r,
                                height: 46.r,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(13.r),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${result.date.month}月',
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: color,
                                      ),
                                    ),
                                    Text(
                                      '${result.date.day}',
                                      style: TextStyle(
                                        fontSize: 17.sp,
                                        fontWeight: FontWeight.w900,
                                        color: color,
                                      ),
                                    ),
                                  ],
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
                                          index < 3 ? '优选 ${index + 1}' : '备选',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w800,
                                            color: color,
                                          ),
                                        ),
                                        SizedBox(width: 8.w),
                                        Text(
                                          '${_weekdayText(result.date)} · ${result.dayGanZhi}日',
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 5.h),
                                    Text(
                                      result.reasons.isEmpty
                                          ? '按公共黄历与个人四柱综合排序'
                                          : result.reasons.first,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        height: 1.4,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (result.recommendedTimes.isNotEmpty) ...[
                                      SizedBox(height: 5.h),
                                      Text(
                                        '时段 ${result.recommendedTimes.take(2).join(' · ')}',
                                        style: TextStyle(
                                          fontSize: 10.sp,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textHint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        _selected = chosen;
        _visibleMonth = DateTime(chosen.year, chosen.month);
      });
    }
  }

  void _openBazi() {
    Navigator.pop(context);
    Future<void>.delayed(
      Duration.zero,
      () async => Get.toNamed(RouteNames.homeBazi),
    );
  }

  Color _personalLevelColor(PersonalDateLevel level) => switch (level) {
        PersonalDateLevel.suitable => AppColors.primary,
        PersonalDateLevel.steady => _gold,
        PersonalDateLevel.cautious => _red,
      };

  Widget _buildYiJiCard(Lunar lunar) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('今日宜忌', '先看能不能做，再看怎么做'),
          SizedBox(height: 12.h),
          _yiJiRow(
            '宜',
            lunar.getDayYi().take(8).toList(),
            AppColors.primary,
            AppColors.tagBg,
          ),
          SizedBox(height: 10.h),
          _yiJiRow('忌', lunar.getDayJi().take(8).toList(), _red, _softRed),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _metaChip(
                '冲${lunar.getDayChongShengXiao()}',
                '煞${lunar.getDaySha()}',
              ),
              _metaChip(
                '值神',
                '${lunar.getDayTianShen()} ${lunar.getDayTianShenLuck()}',
              ),
              _metaChip('建除', lunar.getZhiXing()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalCard(Lunar lunar) {
    final baZi = lunar.getBaZi();
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('专业信息', '想细看时再往下看'),
          SizedBox(height: 12.h),
          _infoGrid([
            ('年柱', baZi[0]),
            ('月柱', baZi[1]),
            ('日柱', baZi[2]),
            ('时柱', baZi[3]),
            ('五行', lunar.getDayNaYin()),
            ('星宿', lunar.getXiu()),
            ('财神', lunar.getDayPositionCai()),
            ('喜神', lunar.getDayPositionXi()),
            ('福神', lunar.getDayPositionFu()),
            ('阳贵', lunar.getDayPositionYangGui()),
          ]),
          SizedBox(height: 12.h),
          _plainLine('今日胎神', lunar.getDayPositionTai()),
          _plainLine('彭祖百忌', '${lunar.getPengZuGan()}；${lunar.getPengZuZhi()}'),
          _plainLine('吉神宜趋', _joinLimited(lunar.getDayJiShen(), 6)),
          _plainLine('凶神宜忌', _joinLimited(lunar.getDayXiongSha(), 6)),
        ],
      ),
    );
  }

  Widget _buildTimeCard(Lunar lunar) {
    final times = lunar.getTimes().take(12).toList();
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('今日时辰', '当前时辰已标记'),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final time in times) _timePill(time, lunar.getTimeZhi()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timePill(LunarTime time, String currentZhi) {
    final isCurrent = time.getZhi() == currentZhi;
    final isGood = time.getTianShenLuck().contains('吉');
    final color = isGood ? AppColors.primary : _gold;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.16) : Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isCurrent ? color.withValues(alpha: 0.48) : AppColors.divider,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${time.getZhi()}时',
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            isGood ? '吉' : '平',
            style: TextStyle(
              fontSize: 10.sp,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 4.w,
          height: 18.h,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _yiJiRow(String label, List<String> items, Color color, Color bg) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34.r,
          height: 34.r,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final item in items)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String title, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: _softGold,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        '$title $value',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _infoGrid(List<(String, String)> items) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8.h,
      crossAxisSpacing: 8.w,
      childAspectRatio: 3.6,
      children: [
        for (final item in items)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FBFB),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Text(
                  item.$1,
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _plainLine(String title, String value) {
    return Padding(
      padding: EdgeInsets.only(top: 9.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72.w,
            child: Text(
              title,
              style: TextStyle(
                color: _gold,
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _joinLimited(List<String> items, int limit) {
    if (items.isEmpty) return '无';
    return items.take(limit).join('、');
  }

  _FortuneLabel _fortuneLabel(Lunar lunar) {
    final luck = lunar.getDayTianShenLuck();
    if (luck.contains('吉')) {
      return const _FortuneLabel('小吉', AppColors.primary);
    }
    if (luck.contains('凶')) {
      return const _FortuneLabel('谨慎', _red);
    }
    return const _FortuneLabel('平稳', _gold);
  }

  String _weekdayText(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[date.weekday - 1];
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _FortuneLabel {
  const _FortuneLabel(this.label, this.color);

  final String label;
  final Color color;
}
