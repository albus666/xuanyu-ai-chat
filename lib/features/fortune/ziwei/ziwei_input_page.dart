import 'package:xuanyu/shared/widgets/bottom_footer_scroll_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/core/local/archive_account_scope.dart';
import 'package:xuanyu/core/profile/account_birth_profile.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';
import 'package:xuanyu/features/fortune/paipan/models/region.dart';
import 'package:xuanyu/features/fortune/paipan/utils/date_util.dart';
import 'package:xuanyu/features/fortune/paipan/utils/region_loader.dart';
import 'package:xuanyu/features/fortune/paipan/utils/true_solar_time.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_date_picker_sheet.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_place_picker_sheet.dart';

import 'ziwei_chart_page.dart';
import 'ziwei_archive_page.dart';
import 'ziwei_archive_store.dart';
import 'ziwei_models.dart';
import 'ziwei_service.dart';
import 'ziwei_settings_sheet.dart';

class ZiweiInputPage extends StatefulWidget {
  const ZiweiInputPage({
    super.key,
    this.loadAccountProfile = true,
    this.forOther = false,
    this.professionalOnlyResult = false,
  });

  final bool loadAccountProfile;
  final bool forOther;
  final bool professionalOnlyResult;

  @override
  State<ZiweiInputPage> createState() => _ZiweiInputPageState();
}

class _ZiweiInputPageState extends State<ZiweiInputPage> {
  final TextEditingController _nameController = TextEditingController(
    text: '我的紫微',
  );
  bool _isSelf = true;
  String _relationship = ArchiveRelationship.self;
  String _gender = '男';
  int _calendarType = 0;
  DateTime _birthDate = DateTime(2000, 1, 1, 12);
  Region? _birthPlace;
  ZiweiSettings _settings = const ZiweiSettings();
  bool _submitting = false;
  bool _accountBirthLoaded = false;
  bool _accountLoadFinished = false;
  bool _autoOpening = false;
  bool _birthInputTouched = false;
  String _accountName = '我的紫微';

  @override
  void initState() {
    super.initState();
    RegionLoader.preload();
    if (widget.forOther) {
      _isSelf = false;
      _relationship = ArchiveRelationship.family;
      _nameController.clear();
      _accountLoadFinished = true;
    } else if (widget.loadAccountProfile) {
      _loadAccountBirthProfile();
    } else {
      _accountLoadFinished = true;
    }
  }

  Future<void> _loadAccountBirthProfile() async {
    try {
      final account = await AccountBirthProfileRepository.load();
      _accountName = account.nickname.isEmpty ? '我的紫微' : account.nickname;
      final parsed = account.birthDateTime;
      if (parsed == null || !account.isComplete) {
        return;
      }
      if (_birthInputTouched || !mounted) return;
      setState(() {
        _birthDate = parsed;
        if (account.gender == 2) {
          _gender = '女';
        } else {
          _gender = '男';
        }
        _calendarType = 0;
        if (_isSelf) {
          _nameController.text = _accountName;
        }
        _accountBirthLoaded = true;
      });
    } on DioException catch (_) {
      // 保持缺失态，绝不使用当前时间伪造本人命盘。
    } finally {
      if (mounted) setState(() => _accountLoadFinished = true);
    }
  }

  Future<void> _completeSelfProfile() async {
    final account = await AccountBirthProfileRepository.ensure(
      context,
      reason: '完善一次后，八字、斗数和其他本人功能都会自动使用',
    );
    if (account == null || !mounted) return;
    final parsed = account.birthDateTime;
    if (parsed == null) return;
    setState(() {
      _birthDate = parsed;
      _gender = account.isFemale ? '女' : '男';
      _calendarType = 0;
      _accountName = account.safeNickname;
      _nameController.text = _accountName;
      _accountBirthLoaded = true;
      _accountLoadFinished = true;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  DateTime get _effectiveBirthDate {
    if (_settings.useTrueSolarTime && _birthPlace?.lng != null) {
      return TrueSolarTime.toTrueSolar(_birthDate, _birthPlace!.lng!);
    }
    return _birthDate;
  }

  String get _dateText => switch (_calendarType) {
        1 => DateUtil.formatLunar(_birthDate),
        2 => DateUtil.getEightCharColumns(
            _birthDate,
          ).map((item) => item.replaceAll('\n', '')).join(' '),
        _ => DateUtil.formatGregorian(_birthDate),
      };

  String get _placeText => _birthPlace == null
      ? '选填，用于真太阳时'
      : _birthPlace!.extPath.replaceAll(' ', ' / ');

  Future<void> _pickDate() async {
    await BirthDatePickerSheet.show(
      context,
      initialDate: _birthDate,
      initialTabIndex: _calendarType,
      onConfirm: (date) {
        setState(() {
          _birthInputTouched = true;
          _birthDate = date;
        });
      },
    );
  }

  Future<void> _pickPlace() async {
    await BirthPlacePickerSheet.show(
      context,
      title: '出生地',
      initialRegion: _birthPlace,
      onConfirm: (region) {
        setState(() => _birthPlace = region);
      },
    );
  }

  Future<void> _editSettings() async {
    final result = await ZiweiSettingsSheet.show(context, _settings);
    if (result != null && mounted) {
      setState(() => _settings = result);
    }
  }

  Future<void> _openArchive() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ZiweiArchivePage()));
  }

  Future<void> _submit({bool replaceCurrent = false}) async {
    if (_submitting) return;
    final effective = _effectiveBirthDate;
    final name = _nameController.text.trim();
    if (!_isSelf && name.isEmpty) {
      showAppToast(context, '请填写对方的姓名或称呼');
      return;
    }
    if (!_isSelf && ArchiveRelationship.isReservedSelfName(name)) {
      showAppToast(context, '他人档案不能使用“本人”类名称');
      return;
    }
    if (effective.year < 1900 || effective.year > 2099) {
      showAppToast(context, '紫微排盘目前支持1900年至2099年');
      return;
    }
    final now = DateTime.now();
    final profile = ZiweiProfile(
      name: name.isEmpty ? '我的紫微' : name,
      gender: _gender,
      clockBirthDate: _birthDate,
      effectiveBirthDate: effective,
      calendarTypeIndex: _calendarType,
      settings: _settings,
      birthPlace: _birthPlace?.extPath,
      longitude: _birthPlace?.lng,
      latitude: _birthPlace?.lat,
    );
    setState(() => _submitting = true);
    try {
      final route = MaterialPageRoute<void>(
        builder: (_) => _ZiweiResultLoaderPage(
          profile: profile,
          targetDate: now,
          targetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
          isSelf: _isSelf,
          relationship: _relationship,
          professionalOnly: widget.professionalOnlyResult,
        ),
      );
      if (replaceCurrent || widget.professionalOnlyResult) {
        await Navigator.of(context).pushReplacement(route);
      } else {
        await Navigator.of(context).push(route);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildAccountGate() {
    final loading = !_accountLoadFinished || _autoOpening;
    return GradientScaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('紫微斗数'),
        actions: [
          TextButton(
            onPressed: _openArchive,
            child: Text(
              '命理档案',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 30.w),
          child: loading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    SizedBox(height: 18.h),
                    Text(
                      _autoOpening ? '正在进入我的命盘…' : '正在读取本人资料…',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68.r,
                      height: 68.r,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .09),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.primary,
                        size: 34.r,
                      ),
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      '先完善本人出生资料',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '补充性别与出生日期时辰后，八字、斗数和其他本人功能都会自动使用。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        height: 1.55,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 26.h),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _completeSelfProfile,
                        child: const Text('完善资料后排盘'),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const ZiweiInputPage(forOther: true),
                        ),
                      ),
                      child: const Text('为他人排盘'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.forOther) {
      if (_accountBirthLoaded && !_autoOpening) {
        _autoOpening = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _submit(replaceCurrent: true);
        });
      }
      return _buildAccountGate();
    }
    return GradientScaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('为他人排斗数'),
        actions: [
          TextButton(
            onPressed: _openArchive,
            child: Text(
              '命理档案',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BottomFooterScrollView(
          footer: const CulturalReferenceNotice(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0)),
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 8.h),
              Text(
                '输入对方生辰信息',
                style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                '此处只保存为他人档案，不会覆盖你的本人资料',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 16.h),
              SectionCard(
                padding: EdgeInsets.symmetric(
                  horizontal: 14.w,
                  vertical: 2.h,
                ),
                child: Column(
                  children: [
                    _row(
                      label: '档案归属',
                      right: Align(
                        alignment: Alignment.centerRight,
                        child: _segment(
                          text: '他人档案',
                          selected: true,
                          onTap: () {},
                        ),
                      ),
                    ),
                    _row(
                      label: '姓名/称呼',
                      right: TextField(
                        controller: _nameController,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '必填，用于区分命盘',
                          hintStyle: TextStyle(
                            fontSize: 14.sp,
                            color: AppColors.textSecondary,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    _row(
                      label: '与我关系',
                      right: Align(
                        alignment: Alignment.centerRight,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _relationship,
                            isDense: true,
                            borderRadius: BorderRadius.circular(12.r),
                            items: ArchiveRelationship.selectableForOthers
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      ArchiveRelationship.label(value),
                                      style: TextStyle(fontSize: 14.sp),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _relationship = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    _row(
                      label: '性别',
                      right: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _segment(
                            text: '男',
                            selected: _gender == '男',
                            onTap: () => setState(() {
                              _birthInputTouched = true;
                              _gender = '男';
                            }),
                          ),
                          SizedBox(width: 10.w),
                          _segment(
                            text: '女',
                            selected: _gender == '女',
                            onTap: () => setState(() {
                              _birthInputTouched = true;
                              _gender = '女';
                            }),
                          ),
                        ],
                      ),
                    ),
                    _row(
                      label: '历法',
                      right: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (final entry in const [
                            (0, '公历'),
                            (1, '农历'),
                            (2, '四柱'),
                          ]) ...[
                            _segment(
                              text: entry.$2,
                              selected: _calendarType == entry.$1,
                              onTap: () => setState(() {
                                _birthInputTouched = true;
                                _calendarType = entry.$1;
                              }),
                            ),
                            if (entry.$1 != 2) SizedBox(width: 8.w),
                          ],
                        ],
                      ),
                    ),
                    _row(
                      label: '出生日期时辰',
                      right: _selector(text: _dateText, onTap: _pickDate),
                    ),
                    _row(
                      label: '出生地',
                      right: _selector(
                        text: _placeText,
                        placeholder: _birthPlace == null,
                        onTap: _pickPlace,
                      ),
                    ),
                    _row(
                      label: '排盘规则',
                      divider: false,
                      right: _selector(
                        text: _settings.presetName,
                        onTap: _editSettings,
                      ),
                    ),
                  ],
                ),
              ),
              if (_birthPlace != null) ...[
                SizedBox(height: 12.h),
                SectionCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 10.h,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '使用真太阳时',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 3.h),
                                Text(
                                  '钟表 ${DateUtil.formatGregorian(_birthDate)}',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: AppColors.textHint,
                                  ),
                                ),
                                Text(
                                  '真太阳时 ${DateUtil.formatGregorian(TrueSolarTime.toTrueSolar(_birthDate, _birthPlace!.lng!))}',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _settings.useTrueSolarTime,
                            activeTrackColor: AppColors.primary,
                            onChanged: (value) => setState(() {
                              _settings = _settings.copyWith(
                                useTrueSolarTime: value,
                              );
                            }),
                          ),
                        ],
                      ),
                      if (_birthDate.hour != _effectiveBirthDate.hour)
                        Container(
                          width: double.infinity,
                          margin: EdgeInsets.only(top: 8.h),
                          padding: EdgeInsets.all(9.r),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E8),
                            borderRadius: BorderRadius.circular(9.r),
                          ),
                          child: Text(
                            '真太阳时已跨越时辰边界，命盘将按校正后的时辰计算。',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: const Color(0xFF9A6519),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (_calendarType == 2) ...[
                SizedBox(height: 10.h),
                Text(
                  '紫微斗数依赖实际出生年份。四柱可能对应多个日期，请确认显示的公历年份无误。',
                  style: TextStyle(
                    fontSize: 11.sp,
                    height: 1.45,
                    color: const Color(0xFF9A6519),
                  ),
                ),
              ],
              SizedBox(height: 24.h),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                child: PrimaryButton(
                  text: _submitting ? '正在排盘…' : '开始排盘',
                  height: 48.h,
                  enabled: !_submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32.h,
        constraints: BoxConstraints(minWidth: 48.w),
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .08)
              : const Color(0xFFF2F2F2),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required Widget right,
    bool divider = true,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        border: divider
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: .5),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _selector({
    required String text,
    required VoidCallback onTap,
    bool placeholder = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14.sp,
                color: placeholder
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 2.w),
          Icon(Icons.chevron_right, size: 18.r, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _ZiweiLoadResult {
  const _ZiweiLoadResult({required this.data, this.archiveRecord});

  final ZiweiChartData data;
  final ZiweiArchiveRecord? archiveRecord;
}

/// 先完成路由切换，再异步请求命盘，避免用户点击后停留在输入页。
class _ZiweiResultLoaderPage extends StatefulWidget {
  const _ZiweiResultLoaderPage({
    required this.profile,
    required this.targetDate,
    required this.targetTimeIndex,
    required this.isSelf,
    required this.relationship,
    required this.professionalOnly,
  });

  final ZiweiProfile profile;
  final DateTime targetDate;
  final int targetTimeIndex;
  final bool isSelf;
  final String relationship;
  final bool professionalOnly;

  @override
  State<_ZiweiResultLoaderPage> createState() => _ZiweiResultLoaderPageState();
}

class _ZiweiResultLoaderPageState extends State<_ZiweiResultLoaderPage> {
  late Future<_ZiweiLoadResult> _future;
  late final Future<int?> _archiveUserId;

  @override
  void initState() {
    super.initState();
    _archiveUserId = ArchiveAccountScope.currentUserId();
    _start();
  }

  void _start() {
    // 让加载页先绘制一帧，网络与排盘过程不阻塞点击反馈。
    _future = Future<_ZiweiLoadResult>.delayed(Duration.zero, _load);
  }

  Future<_ZiweiLoadResult> _load() async {
    final expectedUserId = await _archiveUserId;
    if (expectedUserId == null) {
      throw StateError('登录状态已失效，请重新登录');
    }
    final data = await ZiweiService.calculate(
      profile: widget.profile,
      targetDate: widget.targetDate,
      targetTimeIndex: widget.targetTimeIndex,
    );
    ZiweiArchiveRecord? archiveRecord;
    try {
      archiveRecord = await ZiweiArchiveStore.save(
        widget.profile,
        isSelf: widget.isSelf,
        relationship: widget.relationship,
        engineName: data.engineName,
        engineVersion: data.engineVersion,
        ruleCode: data.ruleCode,
        expectedUserId: expectedUserId,
      );
    } on StateError {
      rethrow;
    } catch (_) {
      // 本地档案保存失败不影响已完成的排盘。
    }
    return _ZiweiLoadResult(data: data, archiveRecord: archiveRecord);
  }

  void _retry() => setState(_start);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ZiweiLoadResult>(
      future: _future,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result != null) {
          return ZiweiChartPage(
            profile: widget.profile,
            initialData: result.data,
            initialTargetDate: widget.targetDate,
            initialTargetTimeIndex: widget.targetTimeIndex,
            archiveRecord: result.archiveRecord,
            professionalOnly: widget.professionalOnly,
          );
        }
        final error = snapshot.error;
        return GradientScaffold(
          key: const ValueKey('ziwei-loading-page'),
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('我的紫微'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(height: 18),
                        Text(
                          '正在生成完整命盘…',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          '正在计算本命、运限与十二宫星曜',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 44,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          error is ZiweiServiceException
                              ? error.message
                              : error is StateError
                                  ? error.message.toString()
                                  : '排盘失败，请稍后重试',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('重新排盘'),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
